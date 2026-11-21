import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { checkHygiene, classifyRisk, parseDiff, RISK_LABELS, untrackedFile } from "./pr-checks.mjs";

function diffFor(path, { added = [], removed = [], start = 1, isNew = false } = {}) {
  return [
    `diff --git a/${path} b/${path}`,
    ...(isNew ? ["new file mode 100644"] : []),
    `--- ${isNew ? "/dev/null" : `a/${path}`}`,
    `+++ b/${path}`,
    `@@ -${start},${removed.length} +${start},${added.length} @@`,
    ...removed.map((line) => `-${line}`),
    ...added.map((line) => `+${line}`),
  ].join("\n");
}

const noFile = () => [];
const rulesOf = (findings) => findings.map((finding) => [finding.line, finding.rule]);

test("parseDiff numbers added lines in the new file and reads header-like content as content", () => {
  const [file] = parseDiff(diffFor("BarosTests/A.swift", { added: ["let a = 1", "++ not a header"], removed: ["-- gone"], start: 7 }));
  assert.equal(file.path, "BarosTests/A.swift");
  assert.deepEqual(file.added, [
    { line: 7, text: "let a = 1" },
    { line: 8, text: "++ not a header" },
  ]);
  assert.deepEqual(file.removedText, ["-- gone"]);
  const [deleted] = parseDiff(["diff --git a/BarosTests/B.swift b/BarosTests/B.swift", "deleted file mode 100644", "--- a/BarosTests/B.swift", "+++ /dev/null"].join("\n"));
  assert.equal(deleted.path, "BarosTests/B.swift");
});

test("paths with spaces or non-ASCII letters in real git output are still checked", () => {
  const repo = mkdtempSync(join(tmpdir(), "pr-checks-"));
  try {
    const run = (...args) => execFileSync("git", args, { cwd: repo, encoding: "utf8" });
    const commit = (message) => run("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", message);
    run("init", "-q");
    commit("base");
    mkdirSync(join(repo, "BarosUITests"));
    const body = "func testA() {\n    Thread.sleep(forTimeInterval: 1)\n}\n";
    writeFileSync(join(repo, "BarosUITests", "Sleep Test.swift"), body);
    writeFileSync(join(repo, "BarosUITests", "Séance.swift"), body);
    run("add", ".");
    commit("head");
    const files = parseDiff(run("-c", "core.quotePath=false", "diff", "-U0", "--no-renames", "HEAD~1", "HEAD"));
    assert.deepEqual(files.map((file) => file.path).sort(), ["BarosUITests/Sleep Test.swift", "BarosUITests/Séance.swift"]);
    assert.equal(checkHygiene(files, () => body.split("\n")).length, 2);
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});

test("a new sleep in a test target fails unless a reason sits on the line or in a comment above", () => {
  const lines = [
    "func testA() async throws {",
    "    // allow-sleep: the system clock is the thing under test",
    "    try await Task.sleep(for: .milliseconds(5))",
    "    Thread.sleep(forTimeInterval: 1)",
    "    usleep(100)",
    "    try await clock.sleep(for: .seconds(1))",
    "    RunLoop.current.run(until: Date().addingTimeInterval(1))",
    "    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { done.fulfill() }",
    "    Thread.sleep(forTimeInterval: 2) // allow-sleep: measures real elapsed time",
    "}",
  ];
  const files = parseDiff(
    diffFor("BarosCore/Tests/BarosCoreTests/ATests.swift", { added: lines.slice(2, 9), start: 3 }),
  );

  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [
    [4, "no-new-sleep"],
    [5, "no-new-sleep"],
    [7, "no-new-sleep"],
    [8, "no-new-sleep"],
  ]);
});

test("sleeps outside test targets, in comments, or in strings are not test hygiene findings", () => {
  const files = parseDiff(
    [
      diffFor("Baros/App.swift", { added: ["Thread.sleep(forTimeInterval: 1)"] }),
      diffFor("BarosTests/A.swift", {
        added: [
          "// Thread.sleep(forTimeInterval: 1) was flaky",
          "let x = 1 // was Thread.sleep(forTimeInterval: 1)",
          'XCTAssertEqual(log, "called Task.sleep(for:) then XCTSkip")',
          "let y = 2 /* usleep(5) */",
          'let example = "Task.sleep(for: .seconds(1))"',
          "/* Waits with",
          " * Thread.sleep(forTimeInterval: 1)",
          "   usleep(5) */",
        ],
      }),
    ].join("\n"),
  );
  assert.deepEqual(checkHygiene(files, noFile), []);
});

test("a new skip needs a tracking issue or an environment reason", () => {
  const lines = [
    'try XCTSkipIf(true, "Flaky under load (#403).")',
    "// allow-skip: needs the on-screen keyboard",
    'throw XCTSkip("Requires the software keyboard.")',
    'try XCTSkipUnless(ProcessInfo.processInfo.environment["X"] != nil)',
    'throw XCTSkip("Set #1 fails")',
    "Button(\"Save\") {}.disabled(isSaving)",
    "func sleep(until deadline: Instant) async throws {}",
  ];
  const files = parseDiff(diffFor("BarosUITests/A.swift", { added: lines, isNew: true }));

  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [
    [4, "skip-needs-reason"],
    [5, "skip-needs-reason"],
  ]);
});

test("a multi-line skip may name its issue in a later argument line", () => {
  const lines = [
    "try XCTSkipUnless(",
    '    ProcessInfo.processInfo.environment["RUN"] != nil,',
    '    "Parked on #403."',
    ")",
    "try XCTSkipIf(",
    "    true,",
    '    "No reason given."',
    ")",
    'let note = "see #99"',
  ];
  const files = parseDiff(diffFor("BarosUITests/A.swift", { added: lines, isNew: true }));
  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [[5, "skip-needs-reason"]]);
});

test("a parenthesis inside a string doesn't end a skip's arguments early", () => {
  const lines = ["try XCTSkipIf(", '    value == ")",', '    "Parked on #403."', ")"];
  const files = parseDiff(diffFor("BarosUITests/A.swift", { added: lines, isNew: true }));
  assert.deepEqual(checkHygiene(files, () => lines), []);
});

test("a bare marker on the line above, with no reason, doesn't count", () => {
  const lines = [
    "// allow-sleep:",
    "Thread.sleep(forTimeInterval: 1)",
    "// allow-skip:",
    'throw XCTSkip("later")',
  ];
  const files = parseDiff(diffFor("BarosTests/A.swift", { added: lines, isNew: true }));
  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [
    [2, "no-new-sleep"],
    [4, "skip-needs-reason"],
  ]);
});

test("an issue number in code above a skip doesn't explain it; a comment does", () => {
  const lines = [
    'let ticket = "#403"',
    'throw XCTSkip("later")',
    "// #403",
    'throw XCTSkip("later")',
  ];
  const files = parseDiff(diffFor("BarosUITests/A.swift", { added: lines, isNew: true }));
  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [[2, "skip-needs-reason"]]);
});

test("moving an existing sleep or dropping its comment passes; changing its duration doesn't", () => {
  const files = parseDiff(
    diffFor("BarosTests/A.swift", {
      removed: ["        Thread.sleep(forTimeInterval: 1) // settle", "    Thread.sleep(forTimeInterval: 0.005)"],
      added: ["    Thread.sleep(forTimeInterval: 1)", "    Thread.sleep(forTimeInterval: 60)"],
    }),
  );
  assert.deepEqual(rulesOf(checkHygiene(files, () => [])), [[2, "no-new-sleep"]]);
});

test("moving a sleep to another test file is a move, not a new sleep", () => {
  const files = parseDiff(
    [
      diffFor("BarosTests/Old.swift", { removed: ["    Thread.sleep(forTimeInterval: 1)"] }),
      diffFor("BarosTests/New.swift", { added: ["        Thread.sleep(forTimeInterval: 1)"], isNew: true }),
    ].join("\n"),
  );
  assert.deepEqual(checkHygiene(files, noFile), []);
});

test("an untracked file counts as wholly added", () => {
  const file = untrackedFile("BarosTests/New.swift", "func testA() {\n}\n");
  assert.deepEqual(file.added, [
    { line: 1, text: "func testA() {" },
    { line: 2, text: "}" },
  ]);
});

test("risk is high for any change in a data-safety path or what the Convex deploy ships", () => {
  const high = [
    "BarosCore/Sources/BarosCore/Sync/SyncCoordinator.swift",
    "Baros/Core/Sync/ConvexSyncClient.swift",
    "BarosCore/Sources/BarosCore/Models/LoggedSet.swift",
    "BarosCore/Sources/BarosCore/Domain/WorkoutSessionStatus.swift",
    "BarosCore/Sources/BarosCore/Persistence/LocalDataResetService.swift",
    "BarosCore/Sources/BarosCore/Features/Workout/ActiveWorkoutEngine.swift",
    "BarosCore/Sources/BarosCore/AccountDeletion/AccountDeletionCoordinator.swift",
    "BarosCore/Sources/BarosCore/Auth/ClerkJWTIdentityResolver.swift",
    "Baros/Features/Settings/DeleteDataConfirmationView.swift",
    "convex/schema.ts",
    "convex/sync/merge.helpers.ts",
    "package.json",
    "pnpm-lock.yaml",
    ".github/workflows/convex-ci.yml",
  ];
  for (const path of high) assert.equal(classifyRisk([path]).label, "risk:high", path);
  assert.deepEqual(classifyRisk(["docs/a.md", "BarosCore/Sources/BarosCore/Sync/X.swift", "convex/sync.ts"]).areas, [
    "stored data or sync",
    "what the Convex deploy ships",
  ]);
});

test("risk is low for docs and tests only, and medium for anything else", () => {
  const low = ["AGENTS.md", "docs/adr/1.md", "BarosUITests/A.swift", "BarosCore/Tests/BarosCoreTests/A.swift", "convex/sync.test.ts", "convex/syncSim/fleet.sim.ts", "SupportSite/tests/a.test.mjs"];
  assert.equal(classifyRisk(low).label, "risk:low");
  assert.equal(classifyRisk([]).label, "risk:low");
  for (const path of ["Baros/Features/Workout/WorkoutView.swift", "BarosCore/Sources/BarosCore/Formatting/WorkoutFormatters.swift", "convex/tsconfig.json", "SupportSite/package.json", ".github/workflows/app-ci.yml", "Baros/Assets.xcassets/AppIcon.png"]) {
    assert.equal(classifyRisk(["AGENTS.md", path]).label, "risk:medium", path);
  }
  // A rename shows as both paths, so moving app code into Tests/ isn't low.
  assert.equal(classifyRisk(["Baros/Features/X.swift", "BarosTests/X.swift"]).label, "risk:medium");
});

test("every SwiftData model is under a high-risk path", () => {
  const root = new URL("../", import.meta.url);
  const sources = "BarosCore/Sources/BarosCore";
  const models = readdirSync(new URL(sources, root), { recursive: true })
    .filter((path) => path.endsWith(".swift"))
    .map((path) => `${sources}/${path}`)
    .filter((path) => /@Model\b/.test(readFileSync(new URL(path, root), "utf8")));
  assert.ok(models.length >= 10);
  for (const path of models) assert.equal(classifyRisk([path]).label, "risk:high", path);
});

test("the label job allows exactly the risk labels, and reads the author's line from the PR body", () => {
  const workflow = readFileSync(new URL("../.github/workflows/pr-checks.yml", import.meta.url), "utf8");
  const allowed = [...workflow.matchAll(/^\s+(risk:\w+)\) color=\w+ ;;$/gm)].map((match) => match[1]);
  assert.deepEqual(allowed.sort(), [...RISK_LABELS].sort());
  assert.match(workflow, /PR_BODY: \$\{\{ github\.event\.pull_request\.body \}\}/);
});
