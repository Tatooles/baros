#!/usr/bin/env bash
# Runs the CI checks that cover what this branch changed, compared with origin/main.
# Includes uncommitted and untracked files. Hosted BarosTests and BarosUITests need a
# simulator, so this builds them but leaves running them to you (AGENTS.md → Testing).
#
#   scripts/check-changed.sh [--base <ref>] [--skip-build]

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

base=""
skip_build=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --skip-build) skip_build=true; shift ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$base" ]]; then
  git fetch --quiet origin main 2>/dev/null || echo "Couldn't fetch origin/main; comparing with the local copy."
  base="$(git merge-base origin/main HEAD)" || exit 1
fi

changed="$( { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)"
if [[ -z "$changed" ]]; then
  echo "No changes compared with $(git rev-parse --short "$base")."
  exit 0
fi

touches() {
  grep -Eq "$1" <<<"$changed"
}

passed=()
failed=()

run() {
  local name="$1"
  shift
  echo
  echo "==> $name"
  if "$@"; then
    passed+=("$name")
  else
    failed+=("$name")
  fi
}

ensure_node_modules() {
  local dir="$1"
  [[ -d "$dir/node_modules" ]] || pnpm --dir "$dir" install --frozen-lockfile
}

convex_checks() {
  ensure_node_modules . && pnpm run convex:test && pnpm run convex:typecheck
}

support_site_checks() {
  ensure_node_modules SupportSite && pnpm --dir SupportSite run check && pnpm --dir SupportSite test
}

workflow_contracts() {
  ensure_node_modules SupportSite && node --test SupportSite/tests/ci-workflows.test.mjs
}

# arm64 only: ConvexMobile ships no x86_64 simulator slice (#384).
app_build() {
  xcodebuild build-for-testing \
    -project Baros.xcodeproj \
    -scheme Baros \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/check-changed-DerivedData \
    -quiet \
    ARCHS=arm64
}

run "Test hygiene" node scripts/pr-checks.mjs hygiene --base "$base"

if touches '^scripts/'; then
  run "Script tests" node --test scripts/*.test.mjs
fi

if touches '^BarosCore/'; then
  run "BarosCore tests" swift test --package-path BarosCore
fi

app_paths='^(Baros|BarosCore|BarosLiveActivity|BarosTests|BarosUITests|Baros\.xcodeproj)/|^project\.yml$|^convex/auth\.config\.ts$'
if touches "$app_paths"; then
  if [[ "$skip_build" == true ]]; then
    echo
    echo "==> App and test build skipped (--skip-build)"
  else
    run "App and test build" app_build
  fi
fi

if touches '^(convex/|package\.json$|pnpm-lock\.yaml$|vitest\.config\.ts$)'; then
  run "Convex tests and typecheck" convex_checks
fi

support_paths='^SupportSite/|^docs/release/(app-store/|app-store-submission-pack\.md$|listing\.json$|listing-approved\.json$)|^BarosUITests/MarketingScreenshotTests\.swift$'
if touches "$support_paths"; then
  run "SupportSite check and tests" support_site_checks
fi

if touches '^(\.github/workflows/|ci_scripts/)'; then
  run "Workflow contract tests" workflow_contracts
fi

echo
node scripts/pr-checks.mjs summary --base "$base"

if touches '^project\.yml$'; then
  echo "project.yml changed: run xcodegen generate and commit Baros.xcodeproj with it."
fi
if touches '^(Baros|BarosLiveActivity|BarosTests|BarosUITests)/'; then
  echo "Hosted tests aren't run here: run the affected BarosTests and BarosUITests classes on a simulator (AGENTS.md → Testing)."
fi

echo
# The ${x[@]+...} form keeps bash 3.2 (macOS) from treating an empty array as unset.
for name in ${passed[@]+"${passed[@]}"}; do echo "PASS  $name"; done
for name in ${failed[@]+"${failed[@]}"}; do echo "FAIL  $name"; done
[[ -z "${failed[*]-}" ]]
