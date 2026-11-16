#!/usr/bin/env bash
# Captures the raw marketing screens with MarketingScreenshotTests.
#
#   capture-screens.sh <simulator-udid> <out-dir>
#
# Use the iPhone 17 Pro pool device (1206x2622 captures, which baros.fit serves as-is).
# The simulator is set to dark appearance with a 9:41 status bar for the run, then
# restored. Writes <out-dir>/<shot>.png for every shot in docs/release/listing.json.
set -euo pipefail

udid="${1:?usage: capture-screens.sh <simulator-udid> <out-dir>}"
out="${2:?usage: capture-screens.sh <simulator-udid> <out-dir>}"
root="$(git rev-parse --show-toplevel)"
derived="$root/.build/marketing-capture"
result="$derived/MarketingCapture.xcresult"
mkdir -p "$out"
rm -rf "$result" "$derived/attachments"

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" >/dev/null
previous_appearance="$(xcrun simctl ui "$udid" appearance)"
restore() {
  xcrun simctl status_bar "$udid" clear || true
  xcrun simctl ui "$udid" appearance "$previous_appearance" || true
}
trap restore EXIT
xcrun simctl ui "$udid" appearance dark
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

TEST_RUNNER_BAROS_MARKETING_CAPTURE=1 xcodebuild test \
  -project "$root/Baros.xcodeproj" -scheme Baros \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$derived" -resultBundlePath "$result" \
  -only-testing:BarosUITests/MarketingScreenshotTests \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -quiet

xcrun xcresulttool export attachments --path "$result" --output-path "$derived/attachments" >/dev/null
node --input-type=module - "$derived/attachments" "$out" "$root/docs/release/listing.json" <<'EOF'
import { copyFileSync, readFileSync } from "node:fs";
const [dir, out, listingPath] = process.argv.slice(2);
const manifest = JSON.parse(readFileSync(`${dir}/manifest.json`, "utf8"));
const found = new Map();
for (const test of manifest) {
  for (const a of test.attachments ?? []) {
    const name = a.suggestedHumanReadableName ?? "";
    const match = name.match(/^marketing-([a-z-]+?)(_\d+)?(_[0-9A-F-]+)?\.png$/i);
    if (match) found.set(match[1], a.exportedFileName);
  }
}
const shots = JSON.parse(readFileSync(listingPath, "utf8")).shots.map((s) => s.id);
const missing = shots.filter((id) => !found.has(id));
for (const id of shots.filter((id) => found.has(id))) {
  copyFileSync(`${dir}/${found.get(id)}`, `${out}/${id}.png`);
  console.log(`captured ${out}/${id}.png`);
}
if (missing.length) {
  console.error(`missing captures: ${missing.join(", ")}`);
  process.exit(1);
}
EOF
