#!/usr/bin/env node
// Reads a branch's diff and reports test hygiene, PR size, and test delta.
// `scripts/check-changed.sh` runs it locally; `.github/workflows/pr-checks.yml` runs it in CI.
//
//   node scripts/pr-checks.mjs hygiene [--base <ref>] [--head <ref>]
//   node scripts/pr-checks.mjs summary [--base <ref>] [--head <ref>]
//   node scripts/pr-checks.mjs report  --base <sha> --head <sha>    (JSON for the workflow)
//
// Without --head it reads the working tree, including uncommitted and untracked files.
// Without --base it compares with the merge base of origin/main.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const SWIFT_TEST_DIR = /^(BarosTests|BarosUITests|BarosCore\/Tests)\//;
const TEST_PATH =
  /^(BarosTests|BarosUITests|BarosCore\/Tests|SupportSite\/tests)\/|\.test\.[cm]?[jt]s$/;
const GENERATED_PATH =
  /(^|\/)(pnpm-lock\.yaml|Package\.resolved)$|^Baros\.xcodeproj\/|^convex\/_generated\//;

export const SIZE_LABELS = [
  { name: "size:XS", below: 10, color: "0e8a16" },
  { name: "size:S", below: 30, color: "5ebd3e" },
  { name: "size:M", below: 100, color: "fbca04" },
  { name: "size:L", below: 500, color: "fe7d37" },
  { name: "size:XL", below: 1000, color: "d93f0b" },
  { name: "size:XXL", below: Infinity, color: "b60205" },
];

export const DELTA_MARKER = "<!-- pr-checks:test-delta -->";
const NET_CASES_TO_REPORT = 20;

const KIND_NAMES = {
  core: "BarosCore",
  hosted: "BarosTests",
  ui: "BarosUITests",
  convex: "Convex",
  tooling: "tooling",
};

/** Parses `git diff -U0` output into files with their added lines (new-file line numbers). */
export function parseDiff(diff) {
  const files = [];
  let file = null;
  let nextLine = 0;
  let inHunk = false;
  for (const line of diff.split("\n")) {
    if (line.startsWith("diff --git ")) {
      file = { path: null, oldPath: null, isNew: false, added: [], removedText: [] };
      files.push(file);
      inHunk = false;
      continue;
    }
    if (!file) continue;
    if (line.startsWith("new file mode")) file.isNew = true;
    else if (!inHunk && line.startsWith("--- ")) file.oldPath = stripPrefix(line.slice(4), "a/");
    else if (!inHunk && line.startsWith("+++ ")) {
      const target = stripPrefix(line.slice(4), "b/");
      file.path = target ?? file.oldPath;
    } else if (line.startsWith("@@")) {
      inHunk = true;
      const match = line.match(/\+(\d+)/);
      nextLine = match ? Number(match[1]) : 0;
    } else if (line.startsWith("+")) {
      file.added.push({ line: nextLine++, text: line.slice(1) });
    } else if (line.startsWith("-")) {
      file.removedText.push(line.slice(1));
    } else if (!inHunk && line.startsWith("rename from ")) {
      file.oldPath = line.slice("rename from ".length);
    } else if (!inHunk && line.startsWith("rename to ")) {
      file.path = line.slice("rename to ".length);
    }
  }
  return files.filter((entry) => entry.path);
}

function stripPrefix(path, prefix) {
  if (path === "/dev/null") return null;
  return path.startsWith(prefix) ? path.slice(prefix.length) : path;
}

/** Treats an untracked file as wholly added. */
export function untrackedFile(path, contents) {
  const lines = contents.split("\n");
  if (lines.at(-1) === "") lines.pop();
  return {
    path,
    oldPath: null,
    isNew: true,
    added: lines.map((text, index) => ({ line: index + 1, text })),
    removedText: [],
  };
}

const SLEEP = /(?:\bThread\.sleep|\bTask\.sleep|(?<![.\w])u?sleep)\s*\(/;
const SKIP = /\bXCTSkip(?:If|Unless)?\b|\bXCTExpectFailure\b|\.disabled\s*\(/;
const ALLOW_SLEEP = /allow-sleep:\s*\S/;
const ALLOW_SKIP = /allow-skip:\s*\S|#\d+/;

const isCode = (text) => !/^\s*\/\//.test(text);

/**
 * Flags new sleeps and unexplained skips on added lines of Swift test files.
 * A file may keep as many as its diff removes, so editing or moving an
 * existing one is not new. `readLines(path)` returns the file after the
 * change, so a reason on an unchanged line above an added line counts.
 */
export function checkHygiene(files, readLines) {
  const findings = [];
  for (const file of files) {
    if (!SWIFT_TEST_DIR.test(file.path) || !file.path.endsWith(".swift")) continue;
    const removed = file.removedText.filter(isCode);
    const budget = {
      "no-new-sleep": removed.filter((text) => SLEEP.test(text)).length,
      "skip-needs-reason": removed.filter((text) => SKIP.test(text)).length,
    };
    let lines = null;
    for (const { line, text } of file.added) {
      if (!isCode(text)) continue;
      const rules = [];
      if (SLEEP.test(text)) rules.push(["no-new-sleep", ALLOW_SLEEP]);
      if (SKIP.test(text)) rules.push(["skip-needs-reason", ALLOW_SKIP]);
      if (rules.length === 0) continue;
      lines ??= readLines(file.path);
      const nearby = `${lines[line - 2] ?? ""}\n${text}`;
      for (const [rule, allow] of rules) {
        if (allow.test(nearby)) continue;
        if (budget[rule] > 0) {
          budget[rule] -= 1;
          continue;
        }
        findings.push({ path: file.path, line, rule, message: MESSAGES[rule] });
      }
    }
  }
  return findings;
}

const MESSAGES = {
  "no-new-sleep":
    "Wait on the event, not on time (waitUntil, a continuation, or an injected clock). If a sleep is the only option, add `// allow-sleep: <why>` on or above this line.",
  "skip-needs-reason":
    "Name the tracking issue in the skip message or a comment above it (`#403`). For a skip that depends on the environment, add `// allow-skip: <why>`.",
};

/** Changed lines that measure review effort: generated files never count, and tests count only in a tests-only PR. */
export function measureSize(files) {
  const counted = files.filter((file) => !GENERATED_PATH.test(file.path));
  const nonTest = counted.filter((file) => !TEST_PATH.test(file.path));
  const measured = nonTest.length > 0 ? nonTest : counted;
  const lines = measured.reduce(
    (total, file) => total + file.added.length + file.removedText.length,
    0,
  );
  const label = SIZE_LABELS.find((entry) => lines < entry.below).name;
  return { lines, label, testsExcluded: nonTest.length > 0 && nonTest.length < counted.length };
}

function kindOf(path) {
  if (path.startsWith("BarosCore/Tests/")) return "core";
  if (path.startsWith("BarosTests/")) return "hosted";
  if (path.startsWith("BarosUITests/")) return "ui";
  if (path.startsWith("convex/") && /\.test\.[cm]?[jt]s$/.test(path)) return "convex";
  if (/\.test\.[cm]?[jt]s$/.test(path) || path.startsWith("SupportSite/tests/")) return "tooling";
  return null;
}

const SWIFT_CASE =
  /^\s*(?:(?:@\w+|override|private|fileprivate|public|internal|final|static|nonisolated)\s+)*func\s+test\w*\s*\(|^\s*@Test\b/;
const JS_CASE = /^\s*(?:it|test)(?:\.\w+)*\s*\(/;

function countCases(lines, path) {
  const pattern = path.endsWith(".swift") ? SWIFT_CASE : JS_CASE;
  return lines.filter((text) => pattern.test(text)).length;
}

/** Net test cases added per kind, counted from declarations so the number is deterministic. */
export function measureTestDelta(files) {
  const kinds = { core: 0, hosted: 0, ui: 0, convex: 0, tooling: 0 };
  for (const file of files) {
    const kind = kindOf(file.path);
    const oldKind = file.oldPath ? kindOf(file.oldPath) : kind;
    const added = kind ? countCases(file.added.map((entry) => entry.text), file.path) : 0;
    const removed = oldKind ? countCases(file.removedText, file.oldPath ?? file.path) : 0;
    if (kind) kinds[kind] += added;
    if (oldKind) kinds[oldKind] -= removed;
  }
  const net = Object.values(kinds).reduce((sum, value) => sum + value, 0);
  return { kinds, net };
}

const signed = (value) => (value > 0 ? `+${value}` : value < 0 ? `−${-value}` : "0");

export function describeDelta(delta) {
  const parts = Object.entries(delta.kinds)
    .filter(([, value]) => value !== 0)
    .map(([kind, value]) => `${signed(value)} ${KIND_NAMES[kind]}`);
  return parts.length ? `${parts.join(", ")} (net ${signed(delta.net)})` : "no change";
}

/** The sticky PR comment, or null when the change doesn't grow the suite enough to mention. */
export function deltaComment(delta) {
  if (delta.kinds.ui <= 0 && delta.net < NET_CASES_TO_REPORT) return null;
  const lines = [DELTA_MARKER, `**Test delta:** ${describeDelta(delta)}`];
  if (delta.kinds.ui > 0) {
    lines.push(
      "",
      `This PR adds ${delta.kinds.ui} \`BarosUITests\` case${delta.kinds.ui === 1 ? "" : "s"}, and the full UI suite already takes about an hour. Check each one against AGENTS.md → "UI tests", and say in the description which allowed case it covers, or move it to a unit test.`,
    );
  }
  return lines.join("\n");
}

function git(args) {
  return execFileSync("git", args, { encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
}

function loadFiles({ base, head }) {
  const range = head ? [`${base}...${head}`] : [base];
  const files = parseDiff(git(["diff", "-U0", "--no-color", "--no-ext-diff", "-M", ...range]));
  if (!head) {
    const untracked = git(["ls-files", "--others", "--exclude-standard", "-z"])
      .split("\0")
      .filter(Boolean);
    for (const path of untracked) {
      try {
        files.push(untrackedFile(path, readFileSync(path, "utf8")));
      } catch {
        // Unreadable or binary; it can't hold a test case or a sleep.
      }
    }
  }
  const readLines = (path) =>
    (head ? git(["show", `${head}:${path}`]) : readFileSync(path, "utf8")).split("\n");
  return { files, readLines };
}

function parseArgs(argv) {
  const options = { command: argv[0] };
  for (let index = 1; index < argv.length; index += 2) {
    const flag = argv[index];
    if (flag !== "--base" && flag !== "--head") throw new Error(`Unknown option ${flag}`);
    options[flag.slice(2)] = argv[index + 1];
  }
  options.base ??= git(["merge-base", "origin/main", "HEAD"]).trim();
  return options;
}

function main(argv) {
  const options = parseArgs(argv);
  const { files, readLines } = loadFiles(options);

  if (options.command === "hygiene") {
    const findings = checkHygiene(files, readLines);
    for (const finding of findings) {
      if (process.env.GITHUB_ACTIONS) {
        console.log(`::error file=${finding.path},line=${finding.line},title=${finding.rule}::${finding.message}`);
      } else {
        console.log(`${finding.path}:${finding.line}: ${finding.rule}: ${finding.message}`);
      }
    }
    console.log(
      findings.length
        ? `Test hygiene: ${findings.length} finding${findings.length === 1 ? "" : "s"}.`
        : "Test hygiene: no new sleeps or unexplained skips.",
    );
    return findings.length ? 1 : 0;
  }

  const size = measureSize(files);
  const delta = measureTestDelta(files);

  if (options.command === "summary") {
    const note = size.testsExcluded ? ", not counting tests" : "";
    console.log(`PR size: ${size.label} (${size.lines} changed lines${note}; see AGENTS.md → "PR size")`);
    console.log(`Test delta: ${describeDelta(delta)}`);
    const comment = deltaComment(delta);
    if (comment && delta.kinds.ui > 0) console.log(comment.split("\n").at(-1));
    return 0;
  }

  if (options.command === "report") {
    const { color } = SIZE_LABELS.find((entry) => entry.name === size.label);
    console.log(
      JSON.stringify({ ...size, color, delta, comment: deltaComment(delta), marker: DELTA_MARKER }),
    );
    return 0;
  }

  throw new Error(`Unknown command ${options.command}; use hygiene, summary, or report.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2));
}
