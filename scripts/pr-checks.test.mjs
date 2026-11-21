import assert from "node:assert/strict";
import { test } from "node:test";

import {
  checkHygiene,
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

test("a new sleep in a test target fails unless a reason sits on or above it", () => {
  const lines = [
    "func testA() async throws {",
    "    // allow-sleep: the system clock is the thing under test",
    "    try await Task.sleep(for: .milliseconds(5))",
    "    Thread.sleep(forTimeInterval: 1)",
    "    usleep(100)",
    "    try await clock.sleep(for: .seconds(1))",
    "}",
  ];
  const files = parseDiff(
    diffFor("BarosCore/Tests/BarosCoreTests/ATests.swift", { added: lines.slice(2, 6), start: 3 }),
  );

  const findings = checkHygiene(files, () => lines);
  assert.deepEqual(
    findings.map((finding) => [finding.line, finding.rule]),
    [
      [4, "no-new-sleep"],
      [5, "no-new-sleep"],
    ],
  );
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
  ];
  const files = parseDiff(diffFor("BarosUITests/A.swift", { added: lines, isNew: true }));

  const findings = checkHygiene(files, () => lines);
  assert.deepEqual(
    findings.map((finding) => [finding.line, finding.rule]),
    [
      [4, "skip-needs-reason"],
      [5, "skip-needs-reason"],
    ],
  );
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
        added: ["    func testParses() {", "    @Test func rounds() {", "    func helper() {"],
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
    kinds: { core: 2, hosted: 0, ui: 1, convex: 2, tooling: 0 },
    net: 5,
  });
});

test("the delta comment appears for net new UI tests or a large suite increase", () => {
  const quiet = { kinds: { core: 5, hosted: 0, ui: 0, convex: 0, tooling: 0 }, net: 5 };
  assert.equal(deltaComment(quiet), null);

  const swapped = { kinds: { core: 0, hosted: 0, ui: 0, convex: 0, tooling: 0 }, net: 0 };
  assert.equal(deltaComment(swapped), null);

  const ui = { kinds: { core: 0, hosted: 1, ui: 1, convex: 0, tooling: 0 }, net: 2 };
  assert.match(deltaComment(ui), /\*\*Test delta:\*\* \+1 BarosTests, \+1 BarosUITests \(net \+2\)/);
  assert.match(deltaComment(ui), /adds 1 `BarosUITests` case,/);

  const large = { kinds: { core: 25, hosted: 0, ui: 0, convex: 0, tooling: 0 }, net: 25 };
  assert.doesNotMatch(deltaComment(large), /UI tests/);
});

test("an untracked file counts as wholly added", () => {
  const file = untrackedFile("BarosTests/New.swift", "func testA() {\n}\n");
  assert.deepEqual(file.added, [
    { line: 1, text: "func testA() {" },
    { line: 2, text: "}" },
  ]);
});

test("editing or moving an existing sleep within a file is not a new one", () => {
  const files = parseDiff(
    diffFor("BarosTests/A.swift", {
      removed: ["        Thread.sleep(forTimeInterval: 1) // settle"],
      added: ["        Thread.sleep(forTimeInterval: 1)", "        Thread.sleep(forTimeInterval: 2)"],
    }),
  );
  const findings = checkHygiene(files, () => []);
  assert.deepEqual(findings.map((finding) => [finding.line, finding.rule]), [[2, "no-new-sleep"]]);
});
