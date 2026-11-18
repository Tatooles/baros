import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { parse } from "yaml";

const repositoryRoot = process.env.CI_WORKFLOW_ROOT
  ? pathToFileURL(`${process.env.CI_WORKFLOW_ROOT}/`)
  : new URL("../../", import.meta.url);
const appPaths = [
  ".github/workflows/app-ci.yml",
  "Baros/**",
  "BarosCore/**",
  "BarosLiveActivity/**",
  "BarosTests/**",
  "BarosUITests/**",
  "Baros.xcodeproj/**",
  "LiftingLog.xcodeproj/**",
  "ci_scripts/**",
  "convex/auth.config.ts",
  "project.yml",
];
const convexPaths = [
  ".github/workflows/convex-ci.yml",
  "convex/**",
  "package.json",
  "pnpm-lock.yaml",
  "vitest.config.ts",
];
const supportSitePaths = [
  ".github/workflows/support-site-ci.yml",
  "SupportSite/**",
  "docs/release/app-store/**",
  "docs/release/app-store-submission-pack.md",
  "docs/release/listing.json",
  "docs/release/listing-approved.json",
  "BarosUITests/MarketingScreenshotTests.swift",
];
const requiredGateCondition = [
  "${{ always() && (needs.app-changes.result != 'success'",
  "|| needs.app-changes.outputs.changed == 'true') }}",
].join(" ");
const requiredGateRunner = [
  "${{ needs.app-changes.outputs.changed == 'true'",
  "&& 'macos-26' || 'ubuntu-latest' }}",
].join(" ");

async function readWorkflow(name) {
  const source = await readFile(
    new URL(`.github/workflows/${name}`, repositoryRoot),
    "utf8",
  );
  return parse(source);
}

function classifierPaths(script) {
  const match = script.match(/git diff --quiet "\$\{diff_range\}" -- \\\n([\s\S]*?); then/);
  assert.notEqual(match, null, "app classifier must use git diff with an explicit path set");

  return match[1]
    .split("\n")
    .map((line) => line.trim().replace(/ \\$/, "").replace(/^['"]|['"]$/g, ""))
    .filter(Boolean);
}

function requireFailClosedGate(job) {
  assert.equal(job.needs, "app-changes");
  assert.equal(job.if, requiredGateCondition);
  assert.equal(job["runs-on"], requiredGateRunner);

  const guard = job.steps.find(
    (step) => step.name === "Require successful app change classification",
  );
  assert.deepEqual(guard, {
    name: "Require successful app change classification",
    if: "needs.app-changes.result != 'success'",
    run: "exit 1",
  });
}

test("required iOS gates fail closed when app-change classification fails or is cancelled", async () => {
  const workflow = await readWorkflow("app-ci.yml");

  requireFailClosedGate(workflow.jobs["baros-core-tests"]);
  requireFailClosedGate(workflow.jobs["ios-unit-tests"]);
  requireFailClosedGate(workflow.jobs["ios-ui-smoke"]);
});

test("BarosCore package tests run once on macOS without a simulator", async () => {
  const workflow = await readWorkflow("app-ci.yml");
  const job = workflow.jobs["baros-core-tests"];
  const steps = job.steps;
  const testStep = steps.find((step) => step.name === "Run BarosCore package tests");

  // Branch protection requires this check by name.
  assert.equal(job.name, "baros-core-tests");
  assert.ok(testStep, "baros-core-tests must run the package tests");
  assert.equal(
    testStep.run,
    'set -o pipefail\nswift test --package-path BarosCore 2>&1 | tee "${RUNNER_TEMP}/BarosCoreTests.log"\n',
  );
  assert.ok(
    steps.every((step) => !step.run?.includes("retry")),
    "package test failures must fail the job instead of retrying",
  );
  assert.ok(
    steps.every((step) => !step.run?.includes("xcodebuild")),
    "the package gate must not build the app or boot a simulator",
  );
});

test("required iOS gates retry failed tests and report retries that passed", async () => {
  const workflow = await readWorkflow("app-ci.yml");

  for (const jobName of ["ios-unit-tests", "ios-ui-smoke"]) {
    const steps = workflow.jobs[jobName].steps;
    const testIndex = steps.findIndex((step) => step.run?.includes("xcodebuild test"));
    const reportIndex = steps.findIndex((step) =>
      step.run?.includes("ci_scripts/report_retried_tests.py"),
    );

    assert.match(steps[testIndex].run, /-retry-tests-on-failure/);
    assert.match(steps[testIndex].run, /-test-iterations 2/);
    assert.equal(reportIndex, testIndex + 1);
  }
});

test("app classification uses the correct comparison for pull requests and pushes", async () => {
  const workflow = await readWorkflow("app-ci.yml");
  const classifier = workflow.jobs["app-changes"].steps.find((step) => step.id === "detect");

  assert.match(
    classifier.run,
    /if \[\[ "\$\{EVENT_NAME\}" == "pull_request" \]\]; then\n\s+diff_range="\$\{BASE_SHA\}\.\.\.\$\{HEAD_SHA\}"\n\s*else\n\s+diff_range="\$\{BASE_SHA\}\.\.\$\{HEAD_SHA\}"\n\s*fi/,
  );
});

test("app classification is always reported and preserves its decision polarity", async () => {
  const workflow = await readWorkflow("app-ci.yml");
  const appChanges = workflow.jobs["app-changes"];
  const classifier = appChanges.steps.find((step) => step.id === "detect");
  const checkout = appChanges.steps.find(
    (step) => step.name === "Check out repository history",
  );

  assert.equal(workflow.on.pull_request, null);
  assert.deepEqual(workflow.on.push.branches, ["main"]);
  assert.equal(appChanges.outputs.changed, "${{ steps.detect.outputs.changed }}");
  assert.deepEqual(checkout, {
    name: "Check out repository history",
    uses: "actions/checkout@v4",
    with: { "fetch-depth": 0 },
  });
  assert.deepEqual(classifier.env, {
    BASE_SHA: "${{ github.event.pull_request.base.sha || github.event.before }}",
    EVENT_NAME: "${{ github.event_name }}",
    HEAD_SHA: "${{ github.event.pull_request.head.sha || github.sha }}",
  });
  assert.match(
    classifier.run,
    /; then\n\s+echo "changed=false" >> "\$\{GITHUB_OUTPUT\}"\n\s*else\n\s+echo "changed=true" >> "\$\{GITHUB_OUTPUT\}"\n\s*fi\n?$/,
  );
});

test("push triggers and pull-request classification cover the same app paths", async () => {
  const workflow = await readWorkflow("app-ci.yml");
  const classifier = workflow.jobs["app-changes"].steps.find((step) => step.id === "detect");

  assert.deepEqual(workflow.on.push.paths, appPaths);
  assert.deepEqual(classifierPaths(classifier.run), appPaths);
});

test("the lightweight classifier always runs the workflow contract tests", async () => {
  const workflow = await readWorkflow("app-ci.yml");
  const classifierSteps = workflow.jobs["app-changes"].steps;
  const pnpmIndex = classifierSteps.findIndex((step) => step.name === "Set up pnpm");
  const nodeIndex = classifierSteps.findIndex((step) => step.name === "Set up Node.js");
  const installIndex = classifierSteps.findIndex(
    (step) => step.name === "Install workflow test dependencies",
  );
  const contractIndex = classifierSteps.findIndex(
    (step) => step.name === "Validate CI workflow contracts",
  );

  assert.deepEqual(classifierSteps[pnpmIndex], {
    name: "Set up pnpm",
    uses: "pnpm/action-setup@v4",
    with: { version: "10.26.1" },
  });
  assert.deepEqual(classifierSteps[nodeIndex], {
    name: "Set up Node.js",
    uses: "actions/setup-node@v4",
    with: { "node-version": "22.12.0" },
  });
  assert.deepEqual(classifierSteps[installIndex], {
    name: "Install workflow test dependencies",
    run: "pnpm --dir SupportSite install --frozen-lockfile",
  });
  assert.ok(
    pnpmIndex < nodeIndex && nodeIndex < installIndex && installIndex < contractIndex,
    "workflow test dependencies must be installed before the contract tests run",
  );
  assert.deepEqual(classifierSteps[contractIndex], {
    name: "Validate CI workflow contracts",
    run: "node --test SupportSite/tests/ci-workflows.test.mjs",
  });
});

test("Support Site CI watches the complete release surface on pull requests and pushes", async () => {
  const workflow = await readWorkflow("support-site-ci.yml");

  assert.deepEqual(workflow.on.pull_request.paths, supportSitePaths);
  assert.deepEqual(workflow.on.push.paths, supportSitePaths);
});

test("Convex CI watches the complete backend surface on pull requests and pushes", async () => {
  const workflow = await readWorkflow("convex-ci.yml");

  assert.deepEqual(workflow.on.pull_request.paths, convexPaths);
  assert.deepEqual(workflow.on.push.paths, convexPaths);
});

test("the nightly UI suite runs only on schedule or manual dispatch, never as a PR check", async () => {
  const workflow = await readWorkflow("ios-ui-nightly.yml");

  assert.deepEqual(Object.keys(workflow.on).sort(), ["schedule", "workflow_dispatch"]);
  assert.equal(workflow.on.schedule.length, 1);
  assert.match(workflow.on.schedule[0].cron, /^\d+ \d+ \* \* \*$/);
  assert.equal(workflow.on.workflow_dispatch, null);
});

test("the nightly UI suite runs the full target serially with the smoke job's setup", async () => {
  const nightly = await readWorkflow("ios-ui-nightly.yml");
  const appCI = await readWorkflow("app-ci.yml");
  const job = nightly.jobs["ios-ui-full"];
  const smoke = appCI.jobs["ios-ui-smoke"];
  const stepNamed = (steps, name) => steps.find((step) => step.name === name);

  assert.equal(job["runs-on"], "macos-26");
  assert.equal(job["timeout-minutes"], 120);
  assert.equal(job.strategy, undefined, "the full suite must stay one job until sharding is planned");
  assert.deepEqual(job.env, smoke.env);
  for (const name of ["Check out repository", "Select Xcode 26.5", "Show Xcode and simulator environment"]) {
    assert.deepEqual(stepNamed(job.steps, name), stepNamed(smoke.steps, name));
  }

  const testIndex = job.steps.findIndex((step) => step.run?.includes("xcodebuild test"));
  const testRun = job.steps[testIndex].run;
  assert.deepEqual(testRun.match(/-only-testing:\S+/g), ["-only-testing:BarosUITests"]);
  assert.match(testRun, /-parallel-testing-enabled NO/);
  // A stuck test must fail by itself instead of using up the whole step.
  assert.match(testRun, /-test-timeouts-enabled YES/);
  const allowances = [
    ...testRun.matchAll(/-(?:default|maximum)-test-execution-time-allowance (\d+)/g),
  ].map((match) => Number(match[1]));
  assert.equal(allowances.length, 2, "set both the default and maximum per-test allowance");
  for (const seconds of allowances) {
    assert.ok(seconds >= 180 && seconds * 4 <= job.steps[testIndex]["timeout-minutes"] * 60);
  }
  assert.match(testRun, /-maximum-concurrent-test-simulator-destinations 1\b/);
  assert.doesNotMatch(testRun, /-parallel-testing-enabled YES|-parallel-testing-worker-count/);
  assert.ok(job.steps[testIndex]["timeout-minutes"] < job["timeout-minutes"]);

  // Retry behavior must match the smoke gate.
  const smokeRun = smoke.steps.find((step) => step.run?.includes("xcodebuild test")).run;
  for (const flag of ["-retry-tests-on-failure", "-test-iterations 2"]) {
    assert.ok(smokeRun.includes(flag) && testRun.includes(flag), `both jobs must pass ${flag}`);
  }
  const bundleStep = job.steps[testIndex + 1];
  assert.equal(bundleStep.id, "bundle");
  assert.equal(bundleStep.if, "${{ !cancelled() }}");
  assert.match(bundleStep.run, /readable=true/);
  assert.match(bundleStep.run, /readable=false/);
  const retriedStep = job.steps[testIndex + 2];
  assert.match(retriedStep.run, /ci_scripts\/report_retried_tests\.py/);

  const countStep = stepNamed(job.steps, "Report executed UI test count");
  assert.match(countStep.run, /xcresulttool get test-results summary/);
  assert.match(countStep.run, /totalTestCount/);

  const failedStep = job.steps.find((step) => step.id === "failed");
  assert.match(failedStep.run, /ci_scripts\/report_failed_tests\.py\s+\\\s+"\$\{RUNNER_TEMP\}\/BarosUIFull\.xcresult"\s+\\\s+"\$\{RUNNER_TEMP\}\/BarosUIFull\.log"/);
  assert.equal(failedStep.if, "${{ !cancelled() }}", "failed names must be collected after any failure");
  assert.equal(job.outputs["failed-tests"], "${{ steps.failed.outputs.names }}");

  for (const step of [retriedStep, countStep]) {
    assert.equal(
      step.if,
      "${{ !cancelled() && steps.bundle.outputs.readable == 'true' }}",
      `${step.name} must run after test failures whenever the result bundle is readable`,
    );
  }

  const upload = stepNamed(job.steps, "Upload UI suite failure diagnostics");
  assert.equal(upload.if, "failure()");
  assert.equal(upload.uses, "actions/upload-artifact@v4");
  assert.match(upload.with.path, /BarosUIFull\.xcresult/);
  assert.match(upload.with.path, /BarosUIFull\.log/);
});

test("the nightly tracking issue uses minimal permissions and only follows main", async () => {
  const workflow = await readWorkflow("ios-ui-nightly.yml");
  const tracker = workflow.jobs["track-nightly-result"];

  assert.deepEqual(Object.keys(workflow.jobs).sort(), [
    "ios-ui-full",
    "main-changes",
    "track-nightly-result",
  ]);
  assert.deepEqual(workflow.permissions, { contents: "read" });
  assert.equal(workflow.jobs["ios-ui-full"].permissions, undefined);
  assert.deepEqual(tracker.permissions, { issues: "write" });
  assert.equal(tracker.needs, "ios-ui-full");
  assert.match(tracker.if, /^\$\{\{ always\(\) && github\.ref == 'refs\/heads\/main' && /);
  assert.equal(tracker.env.GH_TOKEN, "${{ github.token }}");
  assert.equal(tracker.env.FAILED_TESTS, "${{ needs.ios-ui-full.outputs.failed-tests }}");
  assert.equal(tracker.steps.some((step) => step.uses?.startsWith("actions/checkout")), false);

  const script = tracker.steps[0].run;
  assert.match(script, /gh issue close/);
  assert.match(script, /gh issue comment/);
  assert.match(script, /gh issue create/);
  assert.match(script, /RUN_URL/);
});

test("the nightly gate runs on ubuntu before the macOS job and fails open", async () => {
  const workflow = await readWorkflow("ios-ui-nightly.yml");
  const gate = workflow.jobs["main-changes"];
  const suite = workflow.jobs["ios-ui-full"];

  assert.equal(gate["runs-on"], "ubuntu-latest");
  assert.deepEqual(gate.permissions, { actions: "read" });
  assert.equal(gate.outputs.run, "${{ steps.decide.outputs.run }}");
  assert.equal(gate.env.EVENT_NAME, "${{ github.event_name }}");
  assert.equal(gate.env.HEAD_SHA, "${{ github.sha }}");
  assert.equal(suite.needs, "main-changes");
  assert.equal(
    suite.if,
    "${{ !cancelled() && (needs.main-changes.result != 'success' || needs.main-changes.outputs.run == 'true') }}",
  );
});

async function runNightlyGate({ eventName, headSha, ghOutput = "", ghExitCode = 0 }) {
  const workflow = await readWorkflow("ios-ui-nightly.yml");
  const script = workflow.jobs["main-changes"].steps.find((step) => step.id === "decide").run;
  const directory = await mkdtemp(join(tmpdir(), "nightly-gate-"));

  try {
    const fakeGh = join(directory, "gh");
    await writeFile(
      fakeGh,
      `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> "${directory}/gh-calls"\nprintf '%s' "$FAKE_GH_OUTPUT"\nexit "$FAKE_GH_EXIT"\n`,
    );
    await chmod(fakeGh, 0o755);
    for (const file of ["output", "summary", "gh-calls"]) {
      await writeFile(join(directory, file), "");
    }

    const result = spawnSync("bash", ["-e", "-c", script], {
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${directory}:${process.env.PATH}`,
        EVENT_NAME: eventName,
        HEAD_SHA: headSha,
        FAKE_GH_OUTPUT: ghOutput,
        FAKE_GH_EXIT: String(ghExitCode),
        GITHUB_OUTPUT: join(directory, "output"),
        GITHUB_STEP_SUMMARY: join(directory, "summary"),
      },
    });
    assert.equal(result.status, 0, result.stderr);

    return {
      output: await readFile(join(directory, "output"), "utf8"),
      ghCalls: await readFile(join(directory, "gh-calls"), "utf8"),
    };
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

test("manual dispatch always runs the nightly suite without consulting run history", async () => {
  const { output, ghCalls } = await runNightlyGate({
    eventName: "workflow_dispatch",
    headSha: "abc123",
    ghOutput: "abc123",
  });

  assert.equal(output, "run=true\n");
  assert.equal(ghCalls, "");
});

test("a scheduled run skips only when main matches the last scheduled run", async () => {
  const unchanged = await runNightlyGate({
    eventName: "schedule",
    headSha: "abc123",
    ghOutput: "abc123",
  });
  assert.equal(unchanged.output, "run=false\n");
  assert.match(unchanged.ghCalls, /^run list --workflow ios-ui-nightly\.yml --event schedule --branch main --status completed /);

  const changed = await runNightlyGate({ eventName: "schedule", headSha: "def456", ghOutput: "abc123" });
  assert.equal(changed.output, "run=true\n");

  const firstRun = await runNightlyGate({ eventName: "schedule", headSha: "abc123", ghOutput: "" });
  assert.equal(firstRun.output, "run=true\n");

  const apiFailure = await runNightlyGate({
    eventName: "schedule",
    headSha: "abc123",
    ghOutput: "abc123",
    ghExitCode: 1,
  });
  assert.equal(apiFailure.output, "run=true\n");
});

test("failed UI test names fall back to the log when the result bundle is unreadable", async () => {
  const directory = await mkdtemp(join(tmpdir(), "failed-tests-"));
  try {
    const log = join(directory, "BarosUIFull.log");
    await writeFile(
      log,
      [
        "Test Case '-[BarosUITests.BarosUITests testStable]' started (Iteration 1 of 2).",
        "Test Case '-[BarosUITests.BarosUITests testStable]' passed (2.000 seconds).",
        "Test Case '-[BarosUITests.BarosUITests testFlaky]' started (Iteration 1 of 2).",
        "Test Case '-[BarosUITests.BarosUITests testFlaky]' failed (3.000 seconds).",
        "Test Case '-[BarosUITests.BarosUITests testFlaky]' started (Iteration 2 of 2).",
        "Test Case '-[BarosUITests.BarosUITests testFlaky]' passed (3.000 seconds).",
        "Test Case '-[BarosUITests.SupersetUITests testBroken]' started (Iteration 1 of 2).",
        "Test Case '-[BarosUITests.SupersetUITests testBroken]' failed (4.000 seconds).",
        "Test Case '-[BarosUITests.SupersetUITests testBroken]' started (Iteration 2 of 2).",
        "Test Case '-[BarosUITests.SupersetUITests testBroken]' failed (4.000 seconds).",
        "Test Case '-[BarosUITests.BarosUITests testCutOff]' started (Iteration 1 of 2).",
        "##[error]The action 'Run full Baros UI test target' has timed out after 105 minutes.",
        "",
      ].join("\n"),
    );

    const script = new URL("ci_scripts/report_failed_tests.py", repositoryRoot);
    const result = spawnSync(
      "python3",
      ["-I", script.pathname, join(directory, "missing.xcresult"), log],
      { encoding: "utf8", env: { ...process.env, GITHUB_STEP_SUMMARY: "" } },
    );

    assert.equal(result.status, 0, result.stderr);
    assert.equal(
      result.stdout,
      [
        "SupersetUITests/testBroken()",
        "BarosUITests/testCutOff() (still running when the log ended)",
        "",
      ].join("\n"),
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
