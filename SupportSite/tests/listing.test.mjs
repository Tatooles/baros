import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

// docs/release/listing.json drives the App Store listing and baros.fit's app screens.
// These checks catch, on every PR, what would otherwise surface mid-release.
const repo = new URL("../../", import.meta.url);
const read = async (path) => readFile(new URL(path, repo), "utf8");
const listing = JSON.parse(await read("docs/release/listing.json"));
const approved = JSON.parse(await read("docs/release/listing-approved.json"));
const approvedAssets = JSON.parse(await read("SupportSite/tests/approved-assets.json"));
const captureTests = await read("BarosUITests/MarketingScreenshotTests.swift");

test("listing text fits App Store Connect limits", () => {
  assert.ok(listing.description.length <= 4000, `description is ${listing.description.length} characters`);
  assert.ok(listing.promotionalText.length <= 170, `promotional text is ${listing.promotionalText.length} characters`);
  assert.ok(listing.keywords.length <= 100, `keywords are ${listing.keywords.length} characters`);
});

test("every shot has a two-line headline that fits the frame", () => {
  assert.ok(listing.shots.length >= 1 && listing.shots.length <= 10, "the 6.9-inch slot holds 1 to 10 screenshots");
  assert.equal(new Set(listing.shots.map((s) => s.id)).size, listing.shots.length, "shot ids are unique");
  for (const shot of listing.shots) {
    assert.equal(shot.headline.length, 2, `${shot.id} headline has two lines`);
    for (const line of shot.headline) assert.ok(line.length <= 24, `${shot.id}: "${line}" is over 24 characters`);
  }
});

test("each shot is captured by exactly one MarketingScreenshotTests test", () => {
  const captured = [...captureTests.matchAll(/capture\("([a-z-]+)"\)/g)].map((m) => m[1]);
  assert.deepEqual([...captured].sort(), listing.shots.map((s) => s.id).sort());
});

test("the approved App Store images match the shot list", () => {
  const expected = listing.shots.map((s, i) => `${String(i + 1).padStart(2, "0")}-${s.id}.png`);
  assert.deepEqual(Object.keys(approved.appStore), expected, "rerun listing-assets after changing shots");
});

test("every baros.fit shot has an approved hash", () => {
  for (const shot of listing.shots.filter((s) => s.site)) {
    assert.match(approvedAssets[`assets/${shot.site}`] ?? "", /^[0-9a-f]{64}$/, `${shot.site} has no approved hash`);
  }
});
