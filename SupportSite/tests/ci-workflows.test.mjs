import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const repositoryRoot = new URL("../../", import.meta.url);

async function readWorkflow(name) {
  return readFile(new URL(`.github/workflows/${name}`, repositoryRoot), "utf8");
}

function jobBlock(workflow, jobName, nextJobName) {
  const start = workflow.indexOf(`  ${jobName}:`);
  assert.notEqual(start, -1, `${jobName} must exist`);

  const end = nextJobName === undefined
    ? workflow.length
    : workflow.indexOf(`  ${nextJobName}:`, start + 1);
  assert.notEqual(end, -1, `${nextJobName} must follow ${jobName}`);

  return workflow.slice(start, end);
}

test("required iOS gates fail closed when app-change classification fails", async () => {
  const workflow = await readWorkflow("pr-ci.yml");
  const requiredJobs = [
    jobBlock(workflow, "ios-unit-tests", "ios-ui-smoke"),
    jobBlock(workflow, "ios-ui-smoke"),
  ];

  for (const job of requiredJobs) {
    assert.match(job, /needs\.app-changes\.result != 'success'/);
    assert.match(job, /runs-on:.*ubuntu-latest/);
    assert.match(job, /Require successful app change classification/);
  }
});

test("submission-pack changes trigger Support Site CI for pull requests and main pushes", async () => {
  const workflow = await readWorkflow("support-site-ci.yml");
  const submissionPackPath = '"docs/release/app-store-submission-pack.md"';

  assert.equal(workflow.split(submissionPackPath).length - 1, 2);
});
