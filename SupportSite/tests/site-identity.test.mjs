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
  assert.match(css, /--color-accent-foreground:#f7f7f5/);
  assert.doesNotMatch(css, /#4d94ff/);
});

test("public imagery matches the approved production assets", async () => {
  const approvedAssets = new Map([
    ["assets/baros-app-icon.png", "f6af1bd16254cef7f060a92c2fd12a0132bd97b6716d66ae0a9fd1aad238ce38"],
    ["assets/baros-social-preview.png", "e72cbeb9045c2ffca1342affc7122acb01490bbebfd3e3cdbf2b0d7279fe2069"],
    ["assets/baros-active-workout.jpg", "7731c5d42ec11034bde2f61d2488f5b5e4ef799c07ceb57a6b922f93eda157f2"],
    ["assets/baros-workout-history.jpg", "701b04f17e9b396886dfc676dc4a9bd2b20afade004848d60166707568be1636"],
  ]);

  for (const [asset, approvedHash] of approvedAssets) {
    assert.equal(await sha256(asset), approvedHash, `${asset} does not match the approved public asset`);
  }
});
