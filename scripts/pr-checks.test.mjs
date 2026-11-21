import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  checkHygiene,
  classifyRisk,
  COMMENT_MARKER,
  decodeGitPath,
  measureTestDelta,
  parseDiff,
  prComment,
  RISK_LABELS,
  swiftCodeView,
  untrackedFile,
} from "./pr-checks.mjs";

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

test("parseDiff numbers added lines in the new file and keeps renames' old paths", () => {
  const diff = [
    diffFor("BarosTests/A.swift", { added: ["let a = 1", "let b = 2"], start: 7 }),
    "diff --git a/BarosUITests/Old.swift b/BarosUITests/New.swift",
    "similarity index 100%",
    "rename from BarosUITests/Old.swift",
    "rename to BarosUITests/New.swift",
  ].join("\n");

  const [modified, renamed] = parseDiff(diff);
  assert.deepEqual(modified.added, [
    { line: 7, text: "let a = 1" },
    { line: 8, text: "let b = 2" },
  ]);
  assert.equal(renamed.path, "BarosUITests/New.swift");
  assert.equal(renamed.oldPath, "BarosUITests/Old.swift");
});

test("parseDiff reads added content that looks like a file header as content", () => {
  const [file] = parseDiff(diffFor("docs/a.md", { added: ["++ not a header"], removed: ["-- gone"] }));
  assert.equal(file.path, "docs/a.md");
  assert.deepEqual(file.added.map((entry) => entry.text), ["++ not a header"]);
  assert.deepEqual(file.removedText, ["-- gone"]);
});

test("decodeGitPath reads C-quoted paths and leaves plain ones alone", () => {
  assert.equal(decodeGitPath('"BarosUITests/S\\303\\251ance.swift"'), "BarosUITests/Séance.swift");
  assert.equal(decodeGitPath('"a/Say \\"hi\\".swift"'), 'a/Say "hi".swift');
  assert.equal(decodeGitPath("BarosTests/A.swift"), "BarosTests/A.swift");
});

test("paths with spaces or non-ASCII letters in real git output are still checked", () => {
  const repo = mkdtempSync(join(tmpdir(), "pr-checks-"));
  try {
    const run = (...args) => execFileSync("git", args, { cwd: repo, encoding: "utf8" });
    run("init", "-q");
    run("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "base");
    mkdirSync(join(repo, "BarosUITests"));
    const body = "func testA() {\n    Thread.sleep(forTimeInterval: 1)\n}\n";
    writeFileSync(join(repo, "BarosUITests", "Sleep Test.swift"), body);
    writeFileSync(join(repo, "BarosUITests", "Séance.swift"), body);
    run("add", ".");
    run("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "head");

    for (const quotePath of ["true", "false"]) {
      const files = parseDiff(run("-c", `core.quotePath=${quotePath}`, "diff", "-U0", "HEAD~1", "HEAD"));
      assert.deepEqual(files.map((file) => file.path).sort(), [
        "BarosUITests/Sleep Test.swift",
        "BarosUITests/Séance.swift",
      ]);
      assert.equal(checkHygiene(files, () => body.split("\n")).length, 2);
      assert.equal(measureTestDelta(files).kinds.ui, 2);
    }
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
    '@Test(.disabled("broken")) func parses() {}',
    'throw XCTSkip("Set #1 fails")',
    "Button(\"Save\") {}.disabled(isSaving)",
    "func sleep(until deadline: Instant) async throws {}",
  ];
  const files = parseDiff(diffFor("BarosUITests/A.swift", { added: lines, isNew: true }));

  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [
    [4, "skip-needs-reason"],
    [5, "skip-needs-reason"],
    [6, "skip-needs-reason"],
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

test("a Swift Testing disable needs a reason in any layout, and SwiftUI's .disabled never does", () => {
  const lines = [
    '@Test(.tags(.slow), .disabled("flaky")) func a() {}',
    "@Test(",
    "    .tags(.slow),",
    '    .disabled("flaky")',
    ")",
    "func b() {}",
    "@Test(",
    '    .disabled("Parked on #403")',
    ") func c() {}",
    'Button("Save") {}',
    "    .disabled(isSaving)",
  ];
  const files = parseDiff(diffFor("BarosCore/Tests/BarosCoreTests/A.swift", { added: lines, isNew: true }));
  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [
    [1, "skip-needs-reason"],
    [4, "skip-needs-reason"],
  ]);
});

test("SwiftUI's .disabled in an enabled test's body isn't a skip, and a comment can't hide a real one", () => {
  const lines = [
    "@Test(.tags(.slow))",
    "func renders() {",
    "    let host = UIHostingController(",
    '        rootView: Button("Save") {}',
    "            .disabled(isSaving)",
    "    )",
    "}",
    '@Test("x") func inline() { let v = Text("a").disabled(true) }',
    "@Test(",
    "    .tags(.slow), // closes ) early?",
    '    .disabled("flaky")',
    ")",
    "func hidden() {}",
  ];
  const files = parseDiff(diffFor("BarosCore/Tests/BarosCoreTests/A.swift", { added: lines, isNew: true }));
  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [[11, "skip-needs-reason"]]);
});

test("re-indenting an existing .disabled trait is an edit, not a new skip", () => {
  const lines = [
    "@Suite struct Wrapped {",
    "    @Test(",
    '        .disabled("flaky")',
    "    )",
    "    func a() {}",
    '    @Test(.disabled("flaky")) func b() {}',
    "}",
  ];
  const files = parseDiff(
    diffFor("BarosCore/Tests/BarosCoreTests/A.swift", {
      removed: ["@Test(", '    .disabled("flaky")', ")", "func a() {}", '@Test(.disabled("flaky")) func b() {}'],
      added: lines,
    }),
  );
  assert.deepEqual(checkHygiene(files, () => lines), []);
});

test("a removed SwiftUI .disabled( line can't excuse a new trait, and a block comment can't hide one", () => {
  const lines = [
    "@Test(",
    "    .disabled(",
    '        "flaky"',
    "    )",
    ") func a() {}",
    "@Test(/* https://example.com */ .disabled()) func b() {}",
    '@Test(/* :) */ .disabled("x")) func c() {}',
  ];
  const files = parseDiff(
    diffFor("BarosCore/Tests/BarosCoreTests/A.swift", {
      removed: ["    .disabled("],
      added: lines,
    }),
  );
  assert.deepEqual(rulesOf(checkHygiene(files, () => lines)), [
    [2, "skip-needs-reason"],
    [6, "skip-needs-reason"],
    [7, "skip-needs-reason"],
  ]);
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

const riskOf = (...diffs) => classifyRisk(parseDiff(diffs.join("\n")));

/** Classifies one file changed from `before` to `after`, reading whole files as the CLI does. */
function riskOfEdit(path, before, after) {
  const files = parseDiff(
    diffFor(path, { removed: before?.split("\n") ?? [], added: after?.split("\n") ?? [], isNew: before === null }),
  );
  const texts = { before: { [path]: before }, after: { [path]: after } };
  return classifyRisk(files, (side, file) => texts[side][file] ?? null);
}

const CONVEX_AREA = "Convex functions, schema, or deploy setup, which ship on merge";

test("risk is high for a one-line change to a data-safety area or what deploys Convex", () => {
  const oneLine = { added: ["let merged = local"], removed: ["let merged = remote"] };
  const recovery = "sign-out, local-data reset, account deletion, or workout recovery";
  const cases = [
    ["BarosCore/Sources/BarosCore/Sync/SyncCoordinator.swift", "sync"],
    ["Baros/Core/Sync/ConvexSyncClient.swift", "sync"],
    ["BarosCore/Sources/BarosCore/Sync/SyncOutboxEntry.swift", "stored data models"],
    ["BarosCore/Sources/BarosCore/Models/LoggedSet.swift", "stored data models"],
    ["BarosCore/Sources/BarosCore/Domain/WorkoutHistoryMutationService.swift", "edits to saved data"],
    ["BarosCore/Sources/BarosCore/Persistence/LocalDataResetService.swift", recovery],
    ["Baros/Core/AccountDeletion/AccountDeletionService.swift", recovery],
    ["convex/schema.ts", CONVEX_AREA],
    ["convex/sync/merge.ts", CONVEX_AREA],
    ["package.json", CONVEX_AREA],
    ["pnpm-lock.yaml", CONVEX_AREA],
    [".github/workflows/convex-ci.yml", CONVEX_AREA],
  ];
  for (const [path, area] of cases) {
    assert.deepEqual(riskOf(diffFor(path, oneLine)), { label: "risk:high", areas: [{ name: area, paths: [path] }] }, path);
  }

  const moved = parseDiff(
    [
      "diff --git a/BarosCore/Sources/BarosCore/Sync/Old.swift b/BarosCore/Sources/BarosCore/Other/New.swift",
      "rename from BarosCore/Sources/BarosCore/Sync/Old.swift",
      "rename to BarosCore/Sources/BarosCore/Other/New.swift",
    ].join("\n"),
  );
  assert.equal(classifyRisk(moved).label, "risk:high", "moving a file out of an area still touches it");
});

test("app code that queues uploads is a saved-data edit wherever it lives", () => {
  const engine = "BarosCore/Sources/BarosCore/Features/Workout/ActiveWorkoutEngine.swift";
  assert.deepEqual(
    riskOfEdit(engine, "session.finish()\ntry outboxRecorder.recordUpsert(session)", "session.finish()"),
    { label: "risk:high", areas: [{ name: "edits to saved data", paths: [engine] }] },
  );
  assert.equal(riskOfEdit(engine, "let a = 1", "let a = 2").label, "risk:medium");
});

test("risk is low for docs, tests, and Swift comment-only changes, however large", () => {
  const sync = "BarosCore/Sources/BarosCore/Sync/SyncCoordinator.swift";
  const comments = Array.from({ length: 2000 }, (_, index) => `    // note ${index}`).join("\n");
  const lowEdits = [
    [`${comments}\nfunc a() {}`, "func a() {}"],
    ["    detailText: nil, // One line, like .syncing above.", "detailText: nil,"],
    ["/** Doc.\n * More doc.\n */\nfunc a() {}", "func a() {}"],
    ["/* outer /* nested */ still a comment */\nfunc a() {}", "func a() {}"],
    ['let url = "https://baros.fit" // old', 'let url = "https://baros.fit" // new, it\'s "*/" here'],
    ['let s = "a \\(f("x")) b" // old', 'let s = "a \\(f("x")) b"'],
    ["apply()", "apply() /* why */ // note"],
  ];
  for (const [before, after] of lowEdits) {
    assert.deepEqual(riskOfEdit(sync, before, after), { label: "risk:low", areas: [] }, after);
  }

  assert.deepEqual(
    riskOf(
      diffFor("AGENTS.md", { added: ["Some rule."] }),
      diffFor("convex/sync.test.ts", { added: ['test("x", () => {})'] }),
      diffFor("convex/syncSim/merge-vectors.json", { added: ["{}"] }),
      diffFor("BarosUITests/BarosUITests.swift", { added: ["    func testA() {}"] }),
    ),
    { label: "risk:low", areas: [] },
  );
  assert.equal(classifyRisk([]).label, "risk:low");
});

test("a comment edit can't hide a code change", () => {
  const sync = "BarosCore/Sources/BarosCore/Sync/SyncCoordinator.swift";
  const view = "Baros/Features/Workout/WorkoutView.swift";
  const changed = [
    [view, 'Text("Save")', 'Text("Saved")'],
    [view, "let x = a\n    * 1", "let x = a\n    * 0"],
    [view, "a()\nb()", "/*\na()\n*/\nb()"],
    [view, 'let s = """\n// one\n"""', 'let s = """\n// two\n"""'],
    [view, 'let s = "a \\(f("x")) b"', 'let s = "a \\(f("y")) b"'],
    [view, 'let s = "abc', 'let s = "abc // x'],
    [view, null, "// a new file of comments"],
    [view, "let r = #/a/#\n// x", "let r = #/a/#\n// y"],
    ["SupportSite/src/page.js", "const s = `\n// one\n`", "const s = `\n// two\n`"],
  ];
  for (const [path, before, after] of changed) {
    assert.equal(riskOfEdit(path, before, after).label, "risk:medium", `${before} → ${after}`);
  }
  assert.equal(
    riskOfEdit(sync, "delete(record)\nguard ok else { return }", "guard ok else { return }\ndelete(record)").label,
    "risk:high",
    "moving a call past an unchanged guard changes behavior",
  );
  assert.equal(
    riskOfEdit("convex/sync.ts", "// a\nexport const x = 1", "// b\nexport const x = 1").label,
    "risk:high",
    "only Swift files can be comment-only",
  );
  for (const path of ["SupportSite/index.html", ".github/workflows/app-ci.yml", "SupportSite/pnpm-lock.yaml"]) {
    assert.equal(riskOf(diffFor(path, { added: ["# note"] })).label, "risk:medium", path);
  }
});

test("swiftCodeView keeps strings, drops comments, and gives up when unsure", () => {
  assert.equal(swiftCodeView('  let a = "x // y" // z\n\n  /* c */ b()'), 'let a = "x // y"\nb()');
  assert.equal(swiftCodeView('let a = #"raw \\(x) "# + ##"two"##'), 'let a = #"raw \\(x) "# + ##"two"##');
  assert.equal(swiftCodeView("/* unterminated"), null);
  assert.equal(swiftCodeView('let a = "unterminated\nb()'), null);
  assert.equal(swiftCodeView('let a = "\\(f(")"'), null);
});

test("test delta counts declarations per target, and a moved test nets zero", () => {
  const files = parseDiff(
    [
      diffFor("BarosUITests/BarosUITests.swift", {
        added: ["    func testOpensSheet() {", "    @MainActor func testSwipes() throws {"],
        removed: ["    func testOldFlow() {"],
      }),
      diffFor("BarosCore/Tests/BarosCoreTests/ATests.swift", {
        added: [
          "    func testParses() {",
          "    @Test func rounds() {",
          "    func helper() {",
          "    @Test",
          "    func testBoth() {",
          "    @MainActor @Test func isolated() {",
          "    private func testHelper() {",
        ],
      }),
      diffFor("convex/workouts.test.ts", { added: ['  test("saves", async () => {', '  it.each([1])("x", () => {'] }),
      "diff --git a/BarosTests/Old.swift b/BarosTests/New.swift",
      "rename from BarosTests/Old.swift",
      "rename to BarosTests/New.swift",
      "--- a/BarosTests/Old.swift",
      "+++ b/BarosTests/New.swift",
      "@@ -1,1 +1,1 @@",
      "-    func testMoved() {",
      "+    func testMoved() {",
    ].join("\n"),
  );

  assert.deepEqual(measureTestDelta(files), {
    kinds: { core: 4, hosted: 0, ui: 1, convex: 2, tooling: 0 },
    net: 7,
  });
});

test("the PR comment appears only for high risk or a growing UI suite", () => {
  const unitOnly = { kinds: { core: 25, hosted: 0, ui: 0, convex: 0, tooling: 0 }, net: 25 };
  const ui = { kinds: { core: 0, hosted: 1, ui: 1, convex: 0, tooling: 0 }, net: 2 };
  const medium = { label: "risk:medium", areas: [] };
  assert.equal(prComment(medium, unitOnly), null);

  const delta = prComment(medium, ui);
  assert.ok(delta.startsWith(COMMENT_MARKER));
  assert.match(delta, /\*\*Test delta:\*\* \+1 BarosTests, \+1 BarosUITests \(net \+2\)/);
  assert.match(delta, /adds 1 `BarosUITests` case,/);
  assert.doesNotMatch(delta, /Risk: high/);

  const paths = ["a.swift", "b.swift", "c.swift", "d.swift", "e.swift"].map((name) => `BarosCore/Sources/BarosCore/Sync/${name}`);
  const high = prComment({ label: "risk:high", areas: [{ name: "sync", paths }] }, unitOnly);
  assert.ok(high.startsWith(COMMENT_MARKER));
  assert.match(high, /\*\*Risk: high\.\*\*/);
  assert.match(high, /- \*\*sync:\*\* `BarosCore\/Sources\/BarosCore\/Sync\/a\.swift`, `[^`]+`, `[^`]+` and 2 more/);
  assert.doesNotMatch(high, /Test delta/);
});

test("an untracked file counts as wholly added", () => {
  const file = untrackedFile("BarosTests/New.swift", "func testA() {\n}\n");
  assert.deepEqual(file.added, [
    { line: 1, text: "func testA() {" },
    { line: 2, text: "}" },
  ]);
});

test("a stray */ inside a line comment can't hide a sleep before it", () => {
  const files = parseDiff(
    diffFor("BarosTests/ATests.swift", {
      added: [
        "        Thread.sleep(forTimeInterval: 1) // unmatched */ in a line comment",
        '        let s = "*/"; Thread.sleep(forTimeInterval: 1)',
        "        still a comment */ Thread.sleep(forTimeInterval: 1)",
      ],
    }),
  );
  assert.deepEqual(rulesOf(checkHygiene(files, noFile)), [
    [1, "no-new-sleep"],
    [2, "no-new-sleep"],
    [3, "no-new-sleep"],
  ]);
});

test("binary and mode-only changes still count toward risk", () => {
  const files = parseDiff(
    [
      "diff --git a/Baros/Assets/App Icon.png b/Baros/Assets/App Icon.png",
      "index f584f40..6bf43ff 100644",
      "Binary files a/Baros/Assets/App Icon.png and b/Baros/Assets/App Icon.png differ",
      "diff --git a/scripts/run.sh b/scripts/run.sh",
      "old mode 100644",
      "new mode 100755",
      "diff --git a/docs/new.png b/docs/new.png",
      "new file mode 100644",
      "Binary files /dev/null and b/docs/new.png differ",
      diffFor("README.md", { added: ["A note."] }),
    ].join("\n"),
  );
  assert.deepEqual(
    files.map((file) => file.path),
    ["Baros/Assets/App Icon.png", "scripts/run.sh", "docs/new.png", "README.md"],
  );
  assert.equal(classifyRisk(files).label, "risk:medium");
});

test("SeedDataService counts as ownership code", () => {
  const path = "BarosCore/Sources/BarosCore/Persistence/SeedDataService.swift";
  assert.deepEqual(riskOf(diffFor(path, { added: ["claim()"], removed: ["keep()"] })).areas, [
    { name: "sign-out, local-data reset, account deletion, or workout recovery", paths: [path] },
  ]);
});

test("stored enums, @Model files anywhere, and every deployed Convex file are high", () => {
  const oneLine = { added: ['    case discarded = "gone"'], removed: ['    case discarded = "discarded"'] };
  const status = "BarosCore/Sources/BarosCore/Domain/WorkoutSessionStatus.swift";
  assert.deepEqual(riskOf(diffFor(status, oneLine)).areas, [{ name: "stored data models", paths: [status] }]);

  const model = "BarosCore/Sources/BarosCore/Features/Notes/Note.swift";
  assert.deepEqual(riskOfEdit(model, null, "@Model\nfinal class Note {}").areas, [
    { name: "stored data models", paths: [model] },
  ]);

  const convex = (path) => riskOf(diffFor(path, { added: ["export const x = 1"] })).label;
  assert.equal(convex("convex/syncSim/helpers.ts"), "risk:high", "Convex deploys single-dot files anywhere in convex/");
  assert.equal(convex("convex/auth.config.ts"), "risk:high");
  assert.equal(convex("convex/syncSim/fleet.sim.ts"), "risk:low", "Convex skips names with several dots");
  assert.equal(convex("convex/env.d.ts"), "risk:medium");
});

test("a tests-only PR that removes tests is medium, and moving one is still low", () => {
  const removed = riskOf(diffFor("BarosCore/Tests/BarosCoreTests/SyncCoordinatorTests.swift", { removed: ["    func testMerges() {"] }));
  assert.deepEqual(removed, { label: "risk:medium", areas: [], removesTests: true });
  const moved = riskOf(
    diffFor("BarosTests/A.swift", { removed: ["    func testA() {"] }),
    diffFor("BarosTests/B.swift", { added: ["    func testA() {"] }),
  );
  assert.equal(moved.label, "risk:low");
});

test("every stored model and stored enum in BarosCore is in the stored-models area", async () => {
  const { readdirSync, readFileSync } = await import("node:fs");
  const root = new URL("../", import.meta.url);
  const sources = "BarosCore/Sources/BarosCore";
  const files = readdirSync(new URL(sources, root), { recursive: true })
    .filter((path) => path.endsWith(".swift"))
    .map((path) => ({ path: `${sources}/${path}`, text: readFileSync(new URL(`${sources}/${path}`, root), "utf8") }));
  const high = (path) =>
    classifyRisk([{ path, oldPath: null, added: [{ line: 1, text: "x()" }], removedText: [] }]).label === "risk:high";

  const models = files.filter((file) => /^\s*@Model\b/m.test(file.text));
  assert.ok(models.length >= 10);
  const enums = new Set(models.flatMap((file) => [...file.text.matchAll(/\b([A-Z]\w+)\((?:stored)?[rR]awValue:/g)].map((match) => match[1])));
  const enumFiles = files.filter((file) => [...enums].some((name) => new RegExp(`\\benum ${name}\\b`).test(file.text)));
  assert.ok(enumFiles.length >= 10);
  for (const file of [...models, ...enumFiles]) assert.ok(high(file.path), `${file.path} must match a high-risk area by path`);
});

test("the label job allows exactly the labels, colors, and marker the script reports", async () => {
  const { readFileSync } = await import("node:fs");
  const workflow = readFileSync(new URL("../.github/workflows/pr-checks.yml", import.meta.url), "utf8");
  const allowed = [...workflow.matchAll(/^\s+(risk:\w+)\) color=(\w+) ;;$/gm)].map((match) => ({ name: match[1], color: match[2] }));
  assert.deepEqual(allowed, RISK_LABELS);
  assert.match(workflow, new RegExp(`marker='${COMMENT_MARKER}'`));
});
