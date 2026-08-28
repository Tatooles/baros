import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { test } from "node:test";

const distUrl = new URL("../dist/", import.meta.url);
const publicRoutes = ["index.html", "privacy/index.html", "support/index.html"];

async function readBuiltRoute(pathname) {
  return readFile(new URL(pathname, distUrl), "utf8");
}

async function sha256(pathname) {
  const contents = await readFile(new URL(pathname, distUrl));
  return createHash("sha256").update(contents).digest("hex");
}

async function readBuiltCss() {
  const cssFiles = (await readdir(new URL("_astro/", distUrl))).filter((name) => name.endsWith(".css"));
  return (await Promise.all(cssFiles.map((name) => readFile(new URL(`_astro/${name}`, distUrl), "utf8")))).join("\n").toLowerCase();
}

test("every public route uses the production icon in its header and metadata", async () => {
  for (const route of publicRoutes) {
    const html = await readBuiltRoute(route);
    assert.match(html, /<link rel="icon" type="image\/png" href="\/assets\/baros-app-icon\.png">/);
    assert.match(html, /<img[^>]+src="\/assets\/baros-app-icon\.png"/);
  }
});

test("the built site uses the approved brand anchors without the superseded red palette", async () => {
  const css = await readBuiltCss();

  assert.match(css, /#1c66c7/);
  assert.match(css, /#09121d/);
  assert.match(css, /#f3ebe7/);
  assert.doesNotMatch(css, /#b4231f|#b8322d|#ff6b65/);
});

test("every public route advertises automatic light and dark appearance", async () => {
  for (const route of publicRoutes) {
    const html = await readBuiltRoute(route);
    assert.match(html, /<meta name="color-scheme" content="light dark">/);
    assert.match(html, /<meta name="theme-color" content="#f7f5f1" media="\(prefers-color-scheme: light\)">/);
    assert.match(html, /<meta name="theme-color" content="#080a0d" media="\(prefers-color-scheme: dark\)">/);
  }

  const css = await readBuiltCss();

  assert.match(css, /@media\s*\(prefers-color-scheme:dark\)/);
  assert.match(css, /--color-page:#080a0d/);
  assert.match(css, /--color-ink:#f7f7f5/);
  assert.match(css, /--color-link:#f7f7f5/);
  assert.match(css, /--color-accent:#1768e5/);
  assert.doesNotMatch(css, /#4d94ff/);
});

test("public imagery no longer ships superseded icon, preview, or red-app screenshots", async () => {
  const staleAssets = new Map([
    ["assets/baros-app-icon.png", "a1491f0efb74ed3033e072fd6908f9a0621c3891ae31edb2b833002ceac42120"],
    ["assets/baros-social-preview.png", "0e003452107df83ab0e12bd6b432d9afa52f99d353f0cc23610b2f96672f052e"],
    ["assets/baros-active-workout.jpg", "c33c7a2dd2ac59049129baf7b89b1b008be2a768f724472ede64a1a229cec1bb"],
    ["assets/baros-workout-history.jpg", "59581b1c96783fbfc0ed72fcc3fc9d07a870169610dab61b6fbb3f155056038a"],
  ]);

  for (const [asset, staleHash] of staleAssets) {
    assert.notEqual(await sha256(asset), staleHash, `${asset} still matches the superseded public asset`);
  }
});
