import { createHash } from "node:crypto";
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = path.resolve(siteRoot, "..");
const listing = JSON.parse(await readFile(path.join(repositoryRoot, "docs/release/listing.json"), "utf8"));
const iconPath = path.join(siteRoot, "public/assets/baros-app-icon.png");
const approvedAssetsPath = path.join(siteRoot, "tests/approved-assets.json");
const approvedListingPath = path.join(repositoryRoot, "docs/release/listing-approved.json");
// Apple's font license keeps SF Pro Display out of the repo.
const font = "SF Pro Display";

const canvas = { width: 1320, height: 2868 };
const screen = { x: 139, y: 600, width: 1042, height: 2264, radius: 138 };

// pnpm -C runs this from SupportSite; resolve paths against where the command was typed.
const [rawDirectory, outputDirectory] = process.argv
  .slice(2)
  .filter((arg) => arg !== "--")
  .map((arg) => path.resolve(process.env.INIT_CWD ?? process.cwd(), arg));
if (!rawDirectory || !outputDirectory) {
  console.error("usage: listing-assets.mjs <raw-dir> <app-store-out-dir>");
  process.exit(2);
}
// An unknown family silently falls back to another font, so compare against one that cannot exist.
async function renders(family) {
  const svg = `<svg width="400" height="80" xmlns="http://www.w3.org/2000/svg"><text x="0" y="60" font-family="${family}" font-size="48" font-weight="760">Baros 1RM</text></svg>`;
  return createHash("md5").update(await sharp(Buffer.from(svg)).png().toBuffer()).digest("hex");
}
if ((await renders(font)) === (await renders("No Such Font Baros"))) {
  console.error(`${font} is not installed; get it from developer.apple.com/fonts, then rerun.`);
  process.exit(1);
}

function escapeXml(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function pngDataUrl(buffer) {
  return `data:image/png;base64,${buffer.toString("base64")}`;
}

function artworkSvg({ screenshotDataUrl, iconDataUrl, headline, glowX, fadeBottom = false }) {
  const headlineLines = headline
    .map((line, index) => `<tspan x="660" y="${250 + index * 88}">${escapeXml(line)}</tspan>`)
    .join("");
  const bottomFade = fadeBottom
    ? `<rect x="${screen.x}" y="2320" width="${screen.width}" height="544" fill="url(#screenFade)" clip-path="url(#screenClip)" />`
    : "";

  return `
    <svg width="${canvas.width}" height="${canvas.height}" viewBox="0 0 ${canvas.width} ${canvas.height}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="background" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#080A0D" />
          <stop offset="0.58" stop-color="#050608" />
          <stop offset="1" stop-color="#020305" />
        </linearGradient>
        <radialGradient id="cobaltGlow" cx="${glowX}" cy="42%" r="64%">
          <stop offset="0" stop-color="#1768E5" stop-opacity="0.28" />
          <stop offset="0.42" stop-color="#1C66C7" stop-opacity="0.12" />
          <stop offset="1" stop-color="#09121D" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="silverGlow" cx="76%" cy="34%" r="54%">
          <stop offset="0" stop-color="#F3EBE7" stop-opacity="0.08" />
          <stop offset="1" stop-color="#F3EBE7" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="screenFade" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#000000" stop-opacity="0" />
          <stop offset="0.2" stop-color="#000000" />
          <stop offset="1" stop-color="#000000" />
        </linearGradient>
        <filter id="phoneShadow" x="-30%" y="-20%" width="160%" height="160%">
          <feDropShadow dx="0" dy="26" stdDeviation="34" flood-color="#000000" flood-opacity="0.72" />
          <feDropShadow dx="0" dy="0" stdDeviation="22" flood-color="#1768E5" flood-opacity="0.12" />
        </filter>
        <clipPath id="screenClip">
          <rect x="${screen.x}" y="${screen.y}" width="${screen.width}" height="${screen.height}" rx="${screen.radius}" />
        </clipPath>
      </defs>

      <rect width="1320" height="2868" fill="url(#background)" />
      <rect width="1320" height="2868" fill="url(#cobaltGlow)" />
      <rect width="1320" height="2868" fill="url(#silverGlow)" />

      <g aria-label="Baros">
        <image href="${iconDataUrl}" x="532" y="60" width="68" height="68" />
        <text x="621" y="110" fill="#F3EBE7" font-family="${font}" font-size="32" font-weight="700" letter-spacing="8">BAROS</text>
      </g>

      <text text-anchor="middle" fill="#F7F7F5" font-family="${font}" font-size="76" font-weight="760" letter-spacing="-2">
        ${headlineLines}
      </text>

      <rect x="116" y="576" width="1088" height="2374" rx="166" fill="#020307" stroke="#2A3440" stroke-width="4" filter="url(#phoneShadow)" />
      <image href="${screenshotDataUrl}" x="${screen.x}" y="${screen.y}" width="${screen.width}" height="${screen.height}" preserveAspectRatio="xMidYMin slice" clip-path="url(#screenClip)" />
      ${bottomFade}
      <rect x="${screen.x}" y="${screen.y}" width="${screen.width}" height="${screen.height}" rx="${screen.radius}" fill="none" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="3" />
    </svg>
  `;
}

await mkdir(outputDirectory, { recursive: true });
for (const name of (await readdir(outputDirectory)).filter((n) => n.endsWith(".png"))) {
  await rm(path.join(outputDirectory, name));
}
const iconDataUrl = pngDataUrl(await readFile(iconPath));
const approvedAssets = JSON.parse(await readFile(approvedAssetsPath, "utf8"));
const approvedListing = { appStore: {} };

for (const [index, shot] of listing.shots.entries()) {
  const source = await readFile(path.join(rawDirectory, `${shot.id}.png`));
  const { width, height } = await sharp(source).metadata();
  if (Math.abs(width / height - screen.width / screen.height) > 0.01) {
    throw new Error(`${shot.id}.png is ${width}x${height}; capture on an iPhone 17 Pro.`);
  }

  const svg = artworkSvg({ screenshotDataUrl: pngDataUrl(source), iconDataUrl, ...shot });
  const fileName = `${String(index + 1).padStart(2, "0")}-${shot.id}.png`;
  const png = await sharp(Buffer.from(svg)).flatten({ background: "#080A0D" }).png({ compressionLevel: 9 }).toBuffer();
  await writeFile(path.join(outputDirectory, fileName), png);
  approvedListing.appStore[fileName] = createHash("md5").update(png).digest("hex");
  console.log(`App Store  ${path.join(outputDirectory, fileName)}`);

  if (shot.site) {
    const jpeg = await sharp(source).flatten({ background: "#000000" }).jpeg({ quality: 86, mozjpeg: true }).toBuffer();
    await writeFile(path.join(siteRoot, "public/assets", shot.site), jpeg);
    approvedAssets[`assets/${shot.site}`] = createHash("sha256").update(jpeg).digest("hex");
    console.log(`baros.fit  public/assets/${shot.site}`);
  }
}
await writeFile(approvedAssetsPath, `${JSON.stringify(approvedAssets, null, 2)}\n`);
await writeFile(approvedListingPath, `${JSON.stringify(approvedListing, null, 2)}\n`);
