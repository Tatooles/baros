#!/usr/bin/env node
// Checks a branch's diff for new test sleeps and skips, and gives the PR's risk floor.
// `scripts/check-changed.sh` runs it locally; `.github/workflows/pr-checks.yml` runs it in CI.
//
//   node scripts/pr-checks.mjs hygiene [--base <ref>] [--head <ref>]
//   node scripts/pr-checks.mjs risk    [--base <ref>] [--head <ref>]
//
// Without --head it reads the working tree, including uncommitted and untracked files.
// Without --base it compares with the merge base of origin/main.

import { execFileSync } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";

const SWIFT_TEST_DIR = /^(BarosTests|BarosUITests|BarosCore\/Tests)\//;
const TEST_PATH =
  /^(BarosTests|BarosUITests|BarosCore\/Tests|SupportSite\/tests|convex\/syncSim)\/|\.test\.[cm]?[jt]s$/;
const DOC_PATH = /\.md$|^docs\//;

export const RISK_LABELS = ["risk:low", "risk:medium", "risk:high"];

// The floor is only where a mistake can lose a user's workouts or reaches production on merge.
// It can't see everything; the agent opening the PR raises the label, and review flags one that's
// too low. Keep in step with AGENTS.md → "PR risk".
const CORE = "BarosCore/Sources/BarosCore";
export const HIGH_RISK_AREAS = [
  {
    name: "stored data or sync",
    path: new RegExp(
      `^${CORE}/(?:Models|Domain|Sync|Persistence)/|^Baros/Core/Sync/|^${CORE}/Features/Workout/ActiveWorkoutEngine\\.swift$`,
    ),
  },
  {
    name: "sign-out, reset, deletion, or recovery",
    path: new RegExp(
      `^(?:${CORE}|Baros/Core)/(?:AccountDeletion|AccountTransition|Ownership|Auth)/|^Baros/Features/Settings/(?:DeleteDataConfirmationView|SettingsAccountRow)\\.swift$`,
    ),
  },
  {
    name: "what the Convex deploy ships",
    path: /^convex\/(?!_generated\/|syncSim\/)(?!.*\.(?:test\.[cm]?[jt]s|md|json)$)|^(?:package\.json|pnpm-lock\.yaml|\.github\/workflows\/convex-ci\.yml)$/,
  },
];

/** The risk floor from the paths a PR changes, both sides of any rename included. */
export function classifyRisk(paths) {
  const areas = HIGH_RISK_AREAS.filter((area) => paths.some((path) => area.path.test(path))).map(
    (area) => area.name,
  );
  if (areas.length) return { label: "risk:high", areas };
  const low = paths.every((path) => DOC_PATH.test(path) || TEST_PATH.test(path));
  return { label: low ? "risk:low" : "risk:medium", areas };
}

/** Parses `git diff -U0 --no-renames` output into files with their added lines (new-file line numbers). */
export function parseDiff(diff) {
  const files = [];
  let file = null;
  let nextLine = 0;
  let inHunk = false;
  for (const line of diff.split("\n")) {
    if (line.startsWith("diff --git ")) {
      file = { path: null, added: [], removedText: [] };
      files.push(file);
      inHunk = false;
    } else if (!file) {
      continue;
    } else if (!inHunk && line.startsWith("--- ")) {
      file.path ??= headerPath(line.slice(4), "a/");
    } else if (!inHunk && line.startsWith("+++ ")) {
      file.path = headerPath(line.slice(4), "b/") ?? file.path;
    } else if (line.startsWith("@@")) {
      inHunk = true;
      nextLine = Number(line.match(/\+(\d+)/)?.[1] ?? 0);
    } else if (line.startsWith("+")) {
      file.added.push({ line: nextLine++, text: line.slice(1) });
    } else if (line.startsWith("-")) {
      file.removedText.push(line.slice(1));
    }
  }
  return files.filter((entry) => entry.path);
}

function headerPath(raw, prefix) {
  // Git ends a ---/+++ path that contains a space with a tab.
  const path = raw.replace(/\t$/, "");
  if (path === "/dev/null") return null;
  return path.startsWith(prefix) ? path.slice(prefix.length) : path;
}

/** Treats an untracked file as wholly added. */
export function untrackedFile(path, contents) {
  const lines = contents.split("\n");
  if (lines.at(-1) === "") lines.pop();
  return { path, added: lines.map((text, index) => ({ line: index + 1, text })), removedText: [] };
}

const SLEEP =
  /(?:\bThread\.sleep|\bTask\.sleep|(?<![.\w]|\bfunc\s)u?sleep)\s*\(|\bRunLoop\.\w+\.run\s*\(\s*until:|\.asyncAfter\s*\(/;
const SKIP = /\bXCTSkip(?:If|Unless)?\b|\bXCTExpectFailure\b/;
// [ \t] rather than \s, so a bare marker on the line above can't borrow the next line as its reason.
const ALLOW_SLEEP = /allow-sleep:[ \t]*\S/;
const ALLOW_SKIP = /allow-skip:[ \t]*\S|#\d{2,}/;
const MAX_CALL_LINES = 8;

const isComment = (text) => /^\s*\/\//.test(text);
const codeOf = (text) => text.replace(/\s*\/\/.*$/, "").replace(/\s+/g, " ").trim();

/** The line with string contents and comments blanked out, so a mention isn't a call. */
function maskCode(text) {
  const blank = (span) => " ".repeat(span.length);
  // A line inside a multi-line block comment conventionally starts with `*`.
  if (/^\s*\*(?:\s|\/|$)/.test(text)) return blank(text);
  // A `*/` before any string or comment opens closes a block comment from an earlier line.
  const close = text.indexOf("*/");
  const lead = close >= 0 && !/"|\/\/|\/\*/.test(text.slice(0, close)) ? close + 2 : 0;
  // One pass in source order, so a `*/` or `"` inside a `//` comment has no effect.
  return (
    blank(text.slice(0, lead)) +
    text
      .slice(lead)
      .replace(/"(?:[^"\\]|\\.)*"|\/\*.*?\*\/|\/\*.*$|\/\/.*$/g, (match) =>
        match[0] === '"' ? `"${blank(match.slice(2))}"` : blank(match),
      )
  );
}

function parenDepth(text) {
  const code = maskCode(text);
  return (code.match(/\(/g) ?? []).length - (code.match(/\)/g) ?? []).length;
}

/** The call's own line plus the lines that finish its arguments. */
function callText(lines, line, text) {
  const parts = [text];
  let depth = parenDepth(text);
  for (let index = line; depth > 0 && index < Math.min(lines.length, line - 1 + MAX_CALL_LINES); index += 1) {
    parts.push(lines[index]);
    depth += parenDepth(lines[index]);
  }
  return parts.join("\n");
}

/**
 * Flags new sleeps and unexplained skips on added lines of Swift test files. A reason counts on
 * the line itself, in a comment on the line directly above, or, for a skip, in the call's
 * arguments. A line whose code the diff also removes is a move or re-indent, not a new one.
 * `readLines(path)` returns the file after the change.
 */
export function checkHygiene(files, readLines) {
  const tests = files.filter((file) => SWIFT_TEST_DIR.test(file.path) && file.path.endsWith(".swift"));
  // Pooled across files, so moving a test to another file isn't a new sleep.
  const removed = tests.flatMap((file) => file.removedText.map(codeOf));
  const findings = [];
  for (const file of tests) {
    let lines = null;
    for (const { line, text } of file.added) {
      const code = maskCode(text);
      const isSleep = SLEEP.test(code);
      const isSkip = SKIP.test(code);
      if (!isSleep && !isSkip) continue;
      lines ??= readLines(file.path);
      const above = isComment(lines[line - 2] ?? "") ? lines[line - 2] : "";
      const missing = [];
      if (isSleep && !ALLOW_SLEEP.test(`${above}\n${text}`)) missing.push("no-new-sleep");
      if (isSkip && !ALLOW_SKIP.test(`${above}\n${callText(lines, line, text)}`)) missing.push("skip-needs-reason");
      if (missing.length === 0) continue;
      const kept = removed.indexOf(codeOf(text));
      if (kept !== -1) {
        removed.splice(kept, 1);
        continue;
      }
      for (const rule of missing) findings.push({ path: file.path, line, rule, message: MESSAGES[rule] });
    }
  }
  return findings;
}

const MESSAGES = {
  "no-new-sleep":
    "Wait on the event, not on time (waitUntil, a continuation, or an injected clock). If waiting on time is the only option, add `// allow-sleep: <why>` at the end of this line or as a comment on the line directly above.",
  "skip-needs-reason":
    "Name the tracking issue (`#403`) in the skip's message, at the end of the line, or in a comment on the line directly above. For a skip that depends on the environment, add `// allow-skip: <why>` there instead.",
};

function git(args) {
  return execFileSync("git", ["-c", "core.quotePath=false", ...args], {
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
  });
}

function untracked() {
  return git(["ls-files", "--others", "--exclude-standard", "-z"]).split("\0").filter(Boolean);
}

/** Every path the branch changes; a rename shows as its old and new paths. */
function changedPaths({ base, head }) {
  const range = head ? [`${base}...${head}`] : [base];
  const paths = git(["diff", "--name-only", "--no-renames", "-z", ...range]).split("\0").filter(Boolean);
  return head ? paths : [...paths, ...untracked()];
}

function loadDiff({ base, head }) {
  const range = head ? [`${base}...${head}`] : [base];
  const files = parseDiff(
    git(["diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", "--src-prefix=a/", "--dst-prefix=b/", ...range]),
  );
  if (!head) {
    for (const path of untracked()) {
      try {
        const contents = readFileSync(path, "utf8");
        // Binary files, such as screenshots left for a PR, have no lines to check.
        if (!contents.includes("\0")) files.push(untrackedFile(path, contents));
      } catch {
        // Unreadable; it can't hold a sleep.
      }
    }
  }
  const readLines = (path) => (head ? git(["show", `${head}:${path}`]) : readFileSync(path, "utf8")).split("\n");
  return { files, readLines };
}

function parseArgs(argv) {
  const options = { command: argv[0] };
  for (let index = 1; index < argv.length; index += 2) {
    const flag = argv[index];
    if (flag !== "--base" && flag !== "--head") throw new Error(`Unknown option ${flag}`);
    options[flag.slice(2)] = argv[index + 1];
  }
  // Compare with the merge base, so commits that landed on the base since the branch started
  // don't read as removals.
  options.base = git(["merge-base", options.base ?? "origin/main", options.head ?? "HEAD"]).trim();
  return options;
}

function main(argv) {
  process.chdir(git(["rev-parse", "--show-toplevel"]).trim());
  const options = parseArgs(argv);

  if (options.command === "hygiene") {
    const { files, readLines } = loadDiff(options);
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

  if (options.command === "risk") {
    const { label, areas } = classifyRisk(changedPaths(options));
    console.log(areas.length ? `${label} (${areas.join("; ")})` : label);
    return 0;
  }

  throw new Error(`Unknown command ${options.command}; use hygiene or risk.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  process.exitCode = main(process.argv.slice(2));
}
