import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { parse } from "yaml";

const repositoryRoot = process.env.CI_WORKFLOW_ROOT
  ? pathToFileURL(`${process.env.CI_WORKFLOW_ROOT}/`)
  : new URL("../../", import.meta.url);
const appPaths = [
  ".github/workflows/app-ci.yml",
  "Baros/**",
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

  requireFailClosedGate(workflow.jobs["ios-unit-tests"]);
  requireFailClosedGate(workflow.jobs["ios-ui-smoke"]);
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
  assert.doesNotMatch(testRun, /-parallel-testing-enabled YES|-parallel-testing-worker-count/);
  assert.ok(job.steps[testIndex]["timeout-minutes"] < job["timeout-minutes"]);

  // Retry behavior must match the smoke gate.
  const smokeRun = smoke.steps.find((step) => step.run?.includes("xcodebuild test")).run;
  for (const flag of ["-retry-tests-on-failure", "-test-iterations 2"]) {
    assert.ok(smokeRun.includes(flag) && testRun.includes(flag), `both jobs must pass ${flag}`);
  }
  assert.match(job.steps[testIndex + 1].run, /ci_scripts\/report_retried_tests\.py/);

  const countStep = stepNamed(job.steps, "Report executed UI test count");
  assert.match(countStep.run, /xcresulttool get test-results summary/);
  assert.match(countStep.run, /totalTestCount/);

  const failedStep = job.steps.find((step) => step.id === "failed");
  assert.match(failedStep.run, /ci_scripts\/report_failed_tests\.py/);
  assert.equal(job.outputs["failed-tests"], "${{ steps.failed.outputs.names }}");

  for (const step of [job.steps[testIndex + 1], countStep, failedStep]) {
    assert.equal(step.if, "${{ !cancelled() }}", `${step.name} must also run after test failures`);
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

  assert.deepEqual(Object.keys(workflow.jobs).sort(), ["ios-ui-full", "track-nightly-result"]);
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
