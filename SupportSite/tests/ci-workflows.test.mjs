import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { parse } from "yaml";

const repositoryRoot = process.env.CI_WORKFLOW_ROOT
  ? pathToFileURL(`${process.env.CI_WORKFLOW_ROOT}/`)
  : new URL("../../", import.meta.url);
const appPaths = [
  ".github/workflows/pr-ci.yml",
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
const supportSitePaths = [
  ".github/workflows/support-site-ci.yml",
  "SupportSite/**",
  "docs/release/app-store/**",
  "docs/release/app-store-submission-pack.md",
];
const requiredGateCondition = [
  "${{ !cancelled() && (needs.app-changes.result != 'success'",
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

test("required iOS gates fail closed when app-change classification fails", async () => {
  const workflow = await readWorkflow("pr-ci.yml");

  requireFailClosedGate(workflow.jobs["ios-unit-tests"]);
  requireFailClosedGate(workflow.jobs["ios-ui-smoke"]);
});

test("app classification uses the correct comparison for pull requests and pushes", async () => {
  const workflow = await readWorkflow("pr-ci.yml");
  const classifier = workflow.jobs["app-changes"].steps.find((step) => step.id === "detect");

  assert.match(classifier.run, /diff_range="\$\{BASE_SHA\}\.\.\.\$\{HEAD_SHA\}"/);
  assert.match(classifier.run, /diff_range="\$\{BASE_SHA\}\.\.\$\{HEAD_SHA\}"/);
});

test("push triggers and pull-request classification cover the same app paths", async () => {
  const workflow = await readWorkflow("pr-ci.yml");
  const classifier = workflow.jobs["app-changes"].steps.find((step) => step.id === "detect");

  assert.deepEqual(workflow.on.push.paths, appPaths);
  assert.deepEqual(classifierPaths(classifier.run), appPaths);
});

test("the lightweight classifier always runs the workflow contract tests", async () => {
  const workflow = await readWorkflow("pr-ci.yml");
  const contractStep = workflow.jobs["app-changes"].steps.find(
    (step) => step.name === "Validate CI workflow contracts",
  );

  assert.deepEqual(contractStep, {
    name: "Validate CI workflow contracts",
    run: "node --test SupportSite/tests/ci-workflows.test.mjs",
  });
});

test("Support Site CI watches the complete release surface on pull requests and pushes", async () => {
  const workflow = await readWorkflow("support-site-ci.yml");

  assert.deepEqual(workflow.on.pull_request.paths, supportSitePaths);
  assert.deepEqual(workflow.on.push.paths, supportSitePaths);
});
