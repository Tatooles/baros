import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const screenshotDirectory = path.resolve(
  testDirectory,
  "../../docs/release/app-store/1.2/screenshots",
);
const expectedScreenshots = [
  ["01-log-every-set.png", "09ff4cb0439362b3865b9f32baf08c33d56e5eb5d04b74764eb02287de66d374"],
  ["02-repeat-workouts.png", "72f93cfd71043bb1ccd169b433d4d6d3dba88e00341f2a498660050f022ff4c2"],
  ["03-training-history.png", "eaa340fcf8394216900bf84b56f6f65fb1e376b3dd153048ae773b544fd2a4b2"],
  ["04-every-detail-preserved.png", "56e5bffc822d0bffde8e64b7b4993e56acbf96ed9360c817c8a4a751ed2ba775"],
  ["05-exercise-library.png", "ab5e5a5b2a2df035baca067134331a701ddae1077294a64dc57baf7102f8f0ec"],
  ["06-private-by-default.png", "0cbf4544d2f734828fc5490da27f5b7f7c4d024e2546ff37b04d23d28c3472d6"],
];

test("the Baros 1.2 App Store set is complete and upload-ready", async () => {
  const expectedFilenames = expectedScreenshots.map(([filename]) => filename);
  assert.deepEqual(
    (await readdir(screenshotDirectory)).sort(),
    [...expectedFilenames].sort(),
    "the screenshot directory must contain exactly the reviewed six-file set",
  );

  for (const [filename, expectedSha256] of expectedScreenshots) {
    const screenshotPath = path.join(screenshotDirectory, filename);
    await access(screenshotPath);
    const contents = await readFile(screenshotPath);
    const metadata = await sharp(screenshotPath).metadata();

    assert.equal(metadata.format, "png", `${filename} must be a PNG`);
    assert.equal(metadata.width, 1320, `${filename} must be 1320 pixels wide`);
    assert.equal(metadata.height, 2868, `${filename} must be 2868 pixels tall`);
    assert.equal(metadata.hasAlpha, false, `${filename} must not contain alpha`);
    assert.equal(
      createHash("sha256").update(contents).digest("hex"),
      expectedSha256,
      `${filename} must match its reviewed generated artwork`,
    );
  }
});
