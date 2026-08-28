import { readFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "../..");
const assetRoot = path.join(repositoryRoot, "docs/release/app-store/1.2");
const sourceDirectory = path.join(assetRoot, "source");
const outputDirectory = path.join(assetRoot, "screenshots");
const iconPath = path.join(
  repositoryRoot,
  "SupportSite/public/assets/baros-app-icon.png",
);

const canvas = { width: 1320, height: 2868 };
const screen = { x: 139, y: 600, width: 1042, height: 2264, radius: 138 };

if (process.platform !== "darwin") {
  throw new Error(
    "App Store screenshot generation requires macOS so the artwork uses the same system typography as Baros.",
  );
}

const screenshots = [
  {
    source: "01-active-workout.png",
    output: "01-log-every-set.png",
    headline: ["Log every set", "without the clutter"],
    glowX: "22%",
  },
  {
    source: "02-repeat-workout.png",
    output: "02-repeat-workouts.png",
    headline: ["Repeat your favorite", "workouts in seconds"],
    glowX: "78%",
  },
  {
    source: "03-history.png",
    output: "03-training-history.png",
    headline: ["See your training history", "at a glance"],
    glowX: "26%",
  },
  {
    source: "04-completed-detail.png",
    output: "04-every-detail-preserved.png",
    headline: ["Every workout, set,", "and note preserved"],
    glowX: "76%",
  },
  {
    source: "05-exercise-library.png",
    output: "05-exercise-library.png",
    headline: ["Your exercise library,", "built in and editable"],
    glowX: "28%",
  },
  {
    source: "06-settings.png",
    output: "06-private-by-default.png",
    headline: ["Private by default.", "Sync when you want."],
    glowX: "74%",
    fadeBottom: true,
  },
];

function escapeXml(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function pngDataUrl(buffer) {
  return `data:image/png;base64,${buffer.toString("base64")}`;
}

function artworkSvg({
  screenshotDataUrl,
  iconDataUrl,
  headline,
  glowX,
  zoom = 1,
  fadeBottom = false,
}) {
  const screenshotWidth = screen.width * zoom;
  const screenshotHeight = screen.height * zoom;
  const screenshotX = screen.x - (screenshotWidth - screen.width) / 2;
  const headlineLines = headline
    .map(
      (line, index) =>
        `<tspan x="660" y="${250 + index * 88}">${escapeXml(line)}</tspan>`,
    )
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
        <text x="621" y="110" fill="#F3EBE7" font-family="-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif" font-size="32" font-weight="700" letter-spacing="8">BAROS</text>
      </g>

      <text text-anchor="middle" fill="#F7F7F5" font-family="-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif" font-size="76" font-weight="760" letter-spacing="-2">
        ${headlineLines}
      </text>

      <rect x="116" y="576" width="1088" height="2374" rx="166" fill="#020307" stroke="#2A3440" stroke-width="4" filter="url(#phoneShadow)" />
      <image href="${screenshotDataUrl}" x="${screenshotX}" y="${screen.y}" width="${screenshotWidth}" height="${screenshotHeight}" preserveAspectRatio="xMidYMin slice" clip-path="url(#screenClip)" />
      ${bottomFade}
      <rect x="${screen.x}" y="${screen.y}" width="${screen.width}" height="${screen.height}" rx="${screen.radius}" fill="none" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="3" />
    </svg>
  `;
}

await mkdir(outputDirectory, { recursive: true });
const iconDataUrl = pngDataUrl(await readFile(iconPath));

for (const screenshot of screenshots) {
  const sourceBuffer = await readFile(path.join(sourceDirectory, screenshot.source));
  const sourceMetadata = await sharp(sourceBuffer).metadata();
  if (
    sourceMetadata.width !== canvas.width ||
    sourceMetadata.height !== canvas.height
  ) {
    throw new Error(
      `${screenshot.source} must be ${canvas.width}x${canvas.height}; received ${sourceMetadata.width}x${sourceMetadata.height}`,
    );
  }

  const svg = artworkSvg({
    screenshotDataUrl: pngDataUrl(sourceBuffer),
    iconDataUrl,
    headline: screenshot.headline,
    glowX: screenshot.glowX,
    zoom: screenshot.zoom,
    fadeBottom: screenshot.fadeBottom,
  });
  const outputPath = path.join(outputDirectory, screenshot.output);
  await sharp(Buffer.from(svg))
    .flatten({ background: "#080A0D" })
    .png({ compressionLevel: 9 })
    .toFile(outputPath);
  process.stdout.write(`Generated ${path.relative(repositoryRoot, outputPath)}\n`);
}
