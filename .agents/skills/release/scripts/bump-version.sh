#!/usr/bin/env bash
# Bump MARKETING_VERSION to the next release and register it in the release catalog.
#
#   bump-version.sh <next-version>      e.g. bump-version.sh 1.6
#
# Edits project.yml, Baros.xcodeproj/project.pbxproj, and AppReleaseCatalog.swift.
# Tests are not touched; it lists the ones mentioning the old version for review.
set -euo pipefail

next="${1:?usage: bump-version.sh <next-version>}"
[[ "$next" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "error: '$next' is not a version like 1.6" >&2; exit 1; }

root="$(git rev-parse --show-toplevel)"
cd "$root"
catalog="Baros/App/AppReleaseCatalog.swift"
pbxproj="Baros.xcodeproj/project.pbxproj"

current="$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*([0-9.]+).*/\1/p' project.yml)"
[[ -n "$current" ]] || { echo "error: MARKETING_VERSION not found in project.yml" >&2; exit 1; }
[[ "$current" != "$next" ]] || { echo "error: already at $next" >&2; exit 1; }

sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION:[[:space:]]*)${current//./\\.}$/\1${next}/" project.yml
sed -i '' -E "s/MARKETING_VERSION = ${current//./\\.};/MARKETING_VERSION = ${next};/" "$pbxproj"

if ! grep -q "version: \"$next\"" "$catalog"; then
  last="$(grep -n 'AppReleaseDefinition(version: "' "$catalog" | tail -1 | cut -d: -f1)"
  indent="$(sed -n "${last}p" "$catalog" | sed -E 's/^([[:space:]]*).*/\1/')"
  sed -i '' "${last}a\\
${indent}AppReleaseDefinition(version: \"${next}\", whatsNewSheet: nil),
" "$catalog"
fi

yml_count="$(grep -c -E "^[[:space:]]*MARKETING_VERSION:[[:space:]]*${next//./\\.}$" project.yml || true)"
pbx_count="$(grep -c "MARKETING_VERSION = ${next};" "$pbxproj" || true)"
stale_count="$(grep -c "MARKETING_VERSION = ${current};" "$pbxproj" || true)"
if [[ "$yml_count" != 1 || "$pbx_count" -lt 1 || "$stale_count" != 0 ]]; then
  echo "error: bump incomplete (project.yml=$yml_count, pbxproj=$pbx_count, stale pbxproj=$stale_count)" >&2
  exit 1
fi

echo "Bumped $current -> $next (project.yml, $pbx_count pbxproj entries, catalog)."
echo "Tests mentioning $current or the upgrade path (change only those asserting the current release):"
git grep -n -E "\"${current//./\\.}\"|Baros ${current//./\\.}|lastProcessedAppVersion|lastSeenWhatsNewVersion" -- BarosTests BarosUITests || echo "  none"
