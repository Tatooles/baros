#!/usr/bin/env node
// Reads a branch's diff and reports test hygiene, PR risk, and test delta.
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
  /^(BarosTests|BarosUITests|BarosCore\/Tests|SupportSite\/tests|convex\/syncSim)\/|\.test\.[cm]?[jt]s$/;
const DOC_PATH = /\.md$|^docs\//;
const CODE_PATH = /\.(swift|[cm]?[jt]sx?)$/;

export const RISK_LABELS = [
  { name: "risk:high", color: "b60205" },
  { name: "risk:medium", color: "fbca04" },
  { name: "risk:low", color: "0e8a16" },
];

// Where a mistake can lose or overwrite a user's workouts, or reaches production on merge.
// A file counts toward the first area it matches. Keep in step with AGENTS.md → "PR risk".
const APP_SOURCES = "(?:BarosCore/Sources/BarosCore|Baros/Core)";
export const HIGH_RISK_AREAS = [
  {
    name: "stored data models",
    path: /^BarosCore\/Sources\/BarosCore\/(?:Models\/|Persistence\/(?:BarosSchema|ModelContainerFactory)\.swift$|Sync\/(?:SyncOutboxEntry|SyncCursorState)\.swift$)/,
  },
  { name: "sync", path: new RegExp(`^${APP_SOURCES}/Sync/`) },
  {
    name: "edits to saved data",
    path: /^BarosCore\/Sources\/BarosCore\/Domain\/\w+MutationService\.swift$/,
  },
  {
    name: "sign-out, local-data reset, account deletion, or workout recovery",
    path: new RegExp(
      `^${APP_SOURCES}/(?:AccountDeletion|AccountTransition|Ownership)/|^BarosCore/Sources/BarosCore/Persistence/LocalDataResetService\\.swift$`,
    ),
  },
  {
    name: "Convex functions or schema, which deploy on merge",
    path: /^convex\/(?!_generated\/|syncSim\/|README\.md$|tsconfig\.json$|env\.d\.ts$)(?!.*\.test\.[cm]?[jt]s$)/,
  },
];

export const COMMENT_MARKER = "<!-- pr-checks -->";

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
    else if (!inHunk && line.startsWith("--- ")) file.oldPath = headerPath(line.slice(4), "a/");
    else if (!inHunk && line.startsWith("+++ ")) {
      const target = headerPath(line.slice(4), "b/");
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
      file.oldPath = decodeGitPath(line.slice("rename from ".length));
    } else if (!inHunk && line.startsWith("rename to ")) {
      file.path = decodeGitPath(line.slice("rename to ".length));
    }
  }
  return files.filter((entry) => entry.path);
}

function headerPath(raw, prefix) {
  // Git ends a ---/+++ path that contains a space with a tab.
  const path = decodeGitPath(raw.replace(/\t$/, ""));
  if (path === "/dev/null") return null;
  return path.startsWith(prefix) ? path.slice(prefix.length) : path;
}

const C_ESCAPES = { a: 7, b: 8, t: 9, n: 10, v: 11, f: 12, r: 13, '"': 34, "\\": 92 };

/** Decodes a path Git wrote in C-quoted form, such as "BarosUITests/S\303\251ance.swift". */
export function decodeGitPath(raw) {
  if (!(raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2)) return raw;
  const bytes = [];
  const body = raw.slice(1, -1);
  for (let index = 0; index < body.length; index += 1) {
    const char = body[index];
    if (char !== "\\") {
      bytes.push(...Buffer.from(char, "utf8"));
      continue;
    }
    const octal = body.slice(index + 1, index + 4);
    if (/^[0-7]{3}$/.test(octal)) {
      bytes.push(Number.parseInt(octal, 8));
      index += 3;
    } else {
      bytes.push(C_ESCAPES[body[index + 1]] ?? body.charCodeAt(index + 1));
      index += 1;
    }
  }
  return Buffer.from(bytes).toString("utf8");
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

const SLEEP =
  /(?:\bThread\.sleep|\bTask\.sleep|(?<![.\w]|\bfunc\s)u?sleep)\s*\(|\bRunLoop\.\w+\.run\s*\(\s*until:|\.asyncAfter\s*\(/;
const SKIP = /\bXCTSkip(?:If|Unless)?\b|\bXCTExpectFailure\b/;
// `.disabled(` is a skip only as a Swift Testing trait, never as the SwiftUI modifier.
const DISABLED = /\.disabled\s*\(/;
const DISABLED_ALL = /\.disabled\s*\(/g;
const TEST_ATTRIBUTE_ALL = /@(?:Test|Suite)\s*\(/g;
// [ \t] rather than \s, so a bare marker on the line above can't borrow the next line as its reason.
const ALLOW_SLEEP = /allow-sleep:[ \t]*\S/;
const ALLOW_SKIP = /allow-skip:[ \t]*\S|#\d{2,}/;

const MAX_CALL_LINES = 8;

const isComment = (text) => /^\s*\/\//.test(text);
const codeOf = (text) => text.replace(/\s*\/\/.*$/, "").replace(/\s+/g, " ").trim();

/** The line with string contents and comments blanked out, keeping every column in place. */
function maskCode(text) {
  const blank = (span) => " ".repeat(span.length);
  // A line inside a multi-line block comment conventionally starts with `*`.
  if (/^\s*\*(?:\s|\/|$)/.test(text)) return blank(text);
  return text
    .replace(/"(?:[^"\\]|\\.)*"/g, (literal) => `"${blank(literal.slice(2))}"`)
    .replace(/\/\*.*?\*\//g, blank)
    .replace(/\/\*.*$/, blank)
    .replace(/^.*?\*\//, blank)
    .replace(/\/\/.*$/, blank);
}

/** Open minus closed parentheses, not counting any inside strings or comments. */
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

/** Where an attribute's argument list closes: [row, column] of its matching `)`, or null if still open at `lastRow`. */
function closingParen(masked, row, column, lastRow) {
  let depth = 0;
  for (; row <= lastRow; row += 1, column = 0) {
    const text = masked(row);
    for (; column < text.length; column += 1) {
      if (text[column] === "(") depth += 1;
      else if (text[column] === ")" && --depth === 0) return [row, column];
    }
  }
  return null;
}

/** Whether a `.disabled(` on 1-based `line` sits between an `@Test(` or `@Suite(` and its matching `)`. */
function disablesTest(lines, line) {
  const at = line - 1;
  const masked = (row) => maskCode(lines[row] ?? "");
  const targets = [...masked(at).matchAll(DISABLED_ALL)].map((match) => match.index);
  for (let start = at; start >= Math.max(0, at - MAX_CALL_LINES); start -= 1) {
    for (const attribute of masked(start).matchAll(TEST_ATTRIBUTE_ALL)) {
      const open = attribute.index + attribute[0].length - 1;
      const close = closingParen(masked, start, open, at);
      const inside = (column) =>
        (start < at || column > open) &&
        (close === null || close[0] > at || (close[0] === at && column < close[1]));
      if (targets.some(inside)) return true;
    }
  }
  return false;
}

/**
 * Flags new sleeps and unexplained skips on added lines of Swift test files.
 * A reason counts on the line itself, in a comment on the line above, or, for
 * a skip, anywhere in the call's arguments. A line whose code the same file's
 * diff removes is an edit or move, not a new one. `readLines(path)` returns
 * the file after the change.
 */
export function checkHygiene(files, readLines) {
  const findings = [];
  for (const file of files) {
    if (!SWIFT_TEST_DIR.test(file.path) || !file.path.endsWith(".swift")) continue;
    // Patterns match masked code, so a mention inside a string or comment isn't a call.
    const unchanged = file.removedText
      // A bare `.disabled(` opener could be SwiftUI's modifier, so it can't excuse a new trait.
      .filter((text) => {
        const code = maskCode(text);
        return SLEEP.test(code) || SKIP.test(code) || (DISABLED.test(code) && !/\.disabled\s*\(\s*$/.test(code));
      })
      .map(codeOf);
    let lines = null;
    for (const { line, text } of file.added) {
      const code = maskCode(text);
      const isSleep = SLEEP.test(code);
      let isSkip = SKIP.test(code);
      if (!isSkip && DISABLED.test(code)) {
        lines ??= readLines(file.path);
        isSkip = disablesTest(lines, line);
      }
      if (!isSleep && !isSkip) continue;
      lines ??= readLines(file.path);
      const above = isComment(lines[line - 2] ?? "") ? lines[line - 2] : "";
      const missing = [];
      if (isSleep && !ALLOW_SLEEP.test(`${above}\n${text}`)) missing.push("no-new-sleep");
      if (isSkip && !ALLOW_SKIP.test(`${above}\n${callText(lines, line, text)}`)) {
        missing.push("skip-needs-reason");
      }
      if (missing.length === 0) continue;
      const kept = unchanged.indexOf(codeOf(text));
      if (kept !== -1) {
        unchanged.splice(kept, 1);
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

// A line that opens or closes a block comment on its own can comment out code it doesn't touch.
const opensOrClosesBlockComment = (text) => /\/\*|\*\//.test(text.replace(/\/\*.*?\*\//g, ""));

/** The line's code with comments removed and strings kept, so a changed string still counts. */
function codeWithoutComments(text) {
  if (/^\s*\*(?:\s|\/|$)/.test(text)) return "";
  return text
    .replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`|\/\*.*?\*\/|\/\/.*$/g, (match) =>
      /^["'`]/.test(match) ? match : "",
    )
    .trim();
}

/** True when a code file's changes only add, remove, or re-indent comments and blank lines. */
function onlyCommentsChange(file) {
  // A rename is never only comments: Convex names each function after its file.
  if (!CODE_PATH.test(file.path) || (file.oldPath && file.oldPath !== file.path)) return false;
  const added = file.added.map((entry) => entry.text);
  if ([...added, ...file.removedText].some(opensOrClosesBlockComment)) return false;
  const code = (lines) => lines.map(codeWithoutComments).filter(Boolean);
  const before = code(file.removedText);
  const after = code(added);
  return before.length === after.length && before.every((line, index) => line === after[index]);
}

/**
 * The PR's risk from what it touches, not how much: high when it reaches a data-safety area or
 * production, low when it changes only docs, tests, or comments, and medium otherwise.
 */
export function classifyRisk(files) {
  const areas = [];
  for (const file of files) {
    if (onlyCommentsChange(file)) continue;
    for (const path of new Set([file.path, file.oldPath].filter(Boolean))) {
      const area = HIGH_RISK_AREAS.find((candidate) => candidate.path.test(path));
      if (!area) continue;
      let entry = areas.find((existing) => existing.name === area.name);
      if (!entry) areas.push((entry = { name: area.name, paths: [] }));
      if (!entry.paths.includes(path)) entry.paths.push(path);
      break;
    }
  }
  if (areas.length) return { label: "risk:high", areas };
  const low = files.every(
    (file) => DOC_PATH.test(file.path) || TEST_PATH.test(file.path) || onlyCommentsChange(file),
  );
  return { label: low ? "risk:low" : "risk:medium", areas };
}

function kindOf(path) {
  if (path.startsWith("BarosCore/Tests/")) return "core";
  if (path.startsWith("BarosTests/")) return "hosted";
  if (path.startsWith("BarosUITests/")) return "ui";
  if (path.startsWith("convex/") && /\.test\.[cm]?[jt]s$/.test(path)) return "convex";
  if (/\.test\.[cm]?[jt]s$/.test(path) || path.startsWith("SupportSite/tests/")) return "tooling";
  return null;
}

// XCTest runs only non-private test methods, so private helpers named test… don't count.
const SWIFT_TEST_FUNC =
  /^\s*(?:(?:@\w+|override|public|internal|final|nonisolated)\s+)*func\s+test\w*\s*\(/;
const SWIFT_TEST_ATTRIBUTE = /^\s*(?:@\w+\s+)*@Test\b/;
const JS_CASE = /^\s*(?:it|test)(?:\.\w+)*\s*\(/;

function countCases(lines, path) {
  if (!path.endsWith(".swift")) return lines.filter((text) => JS_CASE.test(text)).length;
  let count = 0;
  let afterAttribute = false;
  for (const text of lines) {
    if (SWIFT_TEST_ATTRIBUTE.test(text)) {
      count += 1;
      afterAttribute = !/\bfunc\b/.test(text);
    } else if (SWIFT_TEST_FUNC.test(text)) {
      if (!afterAttribute) count += 1;
      afterAttribute = false;
    }
  }
  return count;
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

const MAX_LISTED_PATHS = 3;

/** The sticky PR comment, or null when the PR isn't high risk and doesn't grow the UI suite. */
export function prComment(risk, delta) {
  const sections = [];
  if (risk.label === "risk:high") {
    const lines = risk.areas.map((area) => {
      const listed = area.paths.slice(0, MAX_LISTED_PATHS).map((path) => `\`${path}\``);
      const more = area.paths.length - listed.length;
      return `- **${area.name}:** ${listed.join(", ")}${more > 0 ? ` and ${more} more` : ""}`;
    });
    sections.push(
      [
        "**Risk: high.** This PR changes:",
        ...lines,
        "",
        'AGENTS.md → "PR risk" lists the proof each area needs under Tests.',
      ].join("\n"),
    );
  }
  const added = delta.kinds.ui;
  if (added > 0) {
    sections.push(
      `**Test delta:** ${describeDelta(delta)}\n\nThis PR adds ${added} \`BarosUITests\` case${added === 1 ? "" : "s"}, and the full UI suite already takes about two hours in CI. Check each one against AGENTS.md → "UI tests", and say in the description which allowed case it covers, or move it to a unit test.`,
    );
  }
  return sections.length ? [COMMENT_MARKER, ...sections].join("\n\n") : null;
}

function git(args) {
  return execFileSync("git", args, { encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
}

function loadFiles({ base, head }) {
  const range = head ? [`${base}...${head}`] : [base];
  const files = parseDiff(
    git([
      "-c",
      "core.quotePath=false",
      "diff",
      "-U0",
      "--no-color",
      "--no-ext-diff",
      "--src-prefix=a/",
      "--dst-prefix=b/",
      "-M",
      ...range,
    ]),
  );
  if (!head) {
    const untracked = git(["ls-files", "--others", "--exclude-standard", "-z"])
      .split("\0")
      .filter(Boolean);
    for (const path of untracked) {
      try {
        const contents = readFileSync(path, "utf8");
        // Binary files, such as screenshots left for a PR, aren't changed lines.
        if (!contents.includes("\0")) files.push(untrackedFile(path, contents));
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
  // Compare with the merge base, so commits that landed on the base since the branch started
  // don't read as removals.
  options.base = git(["merge-base", options.base ?? "origin/main", options.head ?? "HEAD"]).trim();
  return options;
}

function main(argv) {
  process.chdir(git(["rev-parse", "--show-toplevel"]).trim());
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

  const risk = classifyRisk(files);
  const delta = measureTestDelta(files);
  const comment = prComment(risk, delta);

  if (options.command === "summary") {
    const why = risk.areas.length
      ? `: ${risk.areas.map((area) => area.name).join("; ")}`
      : risk.label === "risk:low"
        ? ": only docs, tests, or comments"
        : "";
    console.log(`PR risk: ${risk.label}${why} (see AGENTS.md → "PR risk")`);
    console.log(`Test delta: ${describeDelta(delta)}`);
    if (delta.kinds.ui > 0) console.log(comment.split("\n").at(-1));
    return 0;
  }

  if (options.command === "report") {
    const { color } = RISK_LABELS.find((entry) => entry.name === risk.label);
    console.log(JSON.stringify({ ...risk, color, delta, comment, marker: COMMENT_MARKER }));
    return 0;
  }

  throw new Error(`Unknown command ${options.command}; use hygiene, summary, or report.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2));
}
