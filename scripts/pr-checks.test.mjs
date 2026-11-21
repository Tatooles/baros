import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  checkHygiene,
  decodeGitPath,
  deltaComment,
  measureSize,
  measureTestDelta,
  parseDiff,
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

test("sleeps outside test targets and in comments are not test hygiene findings", () => {
  const files = parseDiff(
    [
      diffFor("Baros/App.swift", { added: ["Thread.sleep(forTimeInterval: 1)"] }),
      diffFor("BarosTests/A.swift", { added: ["// Thread.sleep(forTimeInterval: 1) was flaky"] }),
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

test("size counts code, not tests or generated files, unless the PR is only tests", () => {
  const code = Array.from({ length: 40 }, (_, index) => `let v${index} = ${index}`);
  const mixed = parseDiff(
    [
      diffFor("Baros/Views/A.swift", { added: code.slice(0, 20), removed: code.slice(20, 25) }),
      diffFor("BarosCore/Tests/BarosCoreTests/ATests.swift", { added: code }),
      diffFor("pnpm-lock.yaml", { added: code }),
      diffFor("Baros.xcodeproj/project.pbxproj", { added: code }),
    ].join("\n"),
  );
  assert.deepEqual(measureSize(mixed), { lines: 25, label: "size:S", testsExcluded: true });

  const testsOnly = parseDiff(diffFor("BarosTests/ATests.swift", { added: code }));
  assert.deepEqual(measureSize(testsOnly), { lines: 40, label: "size:M", testsExcluded: false });

  assert.equal(measureSize([]).label, "size:XS");
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

test("the delta comment appears only when the UI suite grows", () => {
  const unitOnly = { kinds: { core: 25, hosted: 0, ui: 0, convex: 0, tooling: 0 }, net: 25 };
  assert.equal(deltaComment(unitOnly), null);

  const ui = { kinds: { core: 0, hosted: 1, ui: 1, convex: 0, tooling: 0 }, net: 2 };
  assert.match(deltaComment(ui), /\*\*Test delta:\*\* \+1 BarosTests, \+1 BarosUITests \(net \+2\)/);
  assert.match(deltaComment(ui), /adds 1 `BarosUITests` case,/);
});

test("an untracked file counts as wholly added", () => {
  const file = untrackedFile("BarosTests/New.swift", "func testA() {\n}\n");
  assert.deepEqual(file.added, [
    { line: 1, text: "func testA() {" },
    { line: 2, text: "}" },
  ]);
});
