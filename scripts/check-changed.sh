#!/usr/bin/env bash
# Runs the CI checks that cover what this branch changed since it left origin/main.
# Includes uncommitted and untracked files. Hosted BarosTests and BarosUITests need a
# simulator, so this builds them but leaves running them to you (AGENTS.md → Testing).
#
#   scripts/check-changed.sh [--base <ref>] [--skip-build]
#
# The build goes in .build/check-changed-DerivedData, which is git-ignored and removed with the
# worktree; set DERIVED_DATA to build somewhere else.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

base_ref="origin/main"
skip_build=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) base_ref="${2:?--base needs a ref}"; shift 2 ;;
    --skip-build) skip_build=true; shift ;;
    -h|--help) sed -n '2,9p' scripts/check-changed.sh | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "$base_ref" == "origin/main" ]]; then
  git fetch --quiet origin main 2>/dev/null || echo "Couldn't fetch origin/main; comparing with the local copy."
fi
if ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null; then
  echo "Not a commit: $base_ref" >&2
  exit 2
fi
# The merge base, so commits that landed on the base after this branch started don't count.
base="$(git merge-base "$base_ref" HEAD)" || exit 2

# -z prints paths raw; without it Git quotes non-ASCII names and the path rules miss them.
# --no-renames keeps a moved file's old path, so moving one out of BarosCore/ still tests it.
if ! tracked="$(git diff --name-only --no-renames -z "$base" | tr '\0' '\n')"; then
  echo "git diff failed against $base" >&2
  exit 2
fi
if ! untracked="$(git ls-files --others --exclude-standard -z | tr '\0' '\n')"; then
  echo "git ls-files failed" >&2
  exit 2
fi
changed="$(printf '%s\n%s\n' "$tracked" "$untracked" | sed '/^$/d' | sort -u)"
if [[ -z "$changed" ]]; then
  echo "No changes since $(git rev-parse --short "$base")."
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

convex_checks() {
  pnpm install --frozen-lockfile && pnpm run convex:test && pnpm run convex:typecheck
}

support_site_checks() {
  pnpm --dir SupportSite install --frozen-lockfile &&
    pnpm --dir SupportSite run check &&
    pnpm --dir SupportSite test
}

workflow_contracts() {
  pnpm --dir SupportSite install --frozen-lockfile &&
    node --test SupportSite/tests/ci-workflows.test.mjs
}

# arm64 only: ConvexMobile ships no x86_64 simulator slice (#384).
app_build() {
  xcodebuild build-for-testing \
    -project Baros.xcodeproj \
    -scheme Baros \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${DERIVED_DATA:-.build/check-changed-DerivedData}" \
    -quiet \
    ARCHS=arm64
}

# Keep these in step with the path filters in .github/workflows; ci-workflows.test.mjs checks them.
app_paths='^(Baros|BarosCore|BarosLiveActivity|BarosTests|BarosUITests|Baros\.xcodeproj|LiftingLog\.xcodeproj|ci_scripts)/|^(project\.yml|convex/auth\.config\.ts|convex/syncSim/merge-vectors\.json|\.github/workflows/app-ci\.yml)$'
convex_paths='^convex/|^(package\.json|pnpm-lock\.yaml|vitest\.config\.ts|\.github/workflows/convex-ci\.yml)$'
support_paths='^SupportSite/|^docs/release/app-store/|^(docs/release/app-store-submission-pack\.md|docs/release/listing\.json|docs/release/listing-approved\.json|BarosUITests/MarketingScreenshotTests\.swift|\.github/workflows/support-site-ci\.yml)$'
workflow_paths='^(\.github/workflows|ci_scripts)/|^scripts/check-changed\.sh$'

run "Test hygiene" node scripts/pr-checks.mjs hygiene --base "$base"

if touches '^scripts/|^\.github/workflows/pr-checks\.yml$'; then
  run "Script tests" node --test scripts/*.test.mjs
fi

# CI runs the BarosCore tests for any app change, not only BarosCore/ ones.
if touches "$app_paths"; then
  run "BarosCore tests" swift test --package-path BarosCore
  if [[ "$skip_build" == true ]]; then
    echo
    echo "==> App and test build skipped (--skip-build)"
  else
    run "App and test build" app_build
  fi
fi

if touches "$convex_paths"; then
  run "Convex tests and typecheck" convex_checks
fi

if touches "$support_paths"; then
  run "SupportSite check and tests" support_site_checks
fi

if touches "$workflow_paths"; then
  run "Workflow contract tests" workflow_contracts
fi

echo
echo "Risk floor: $(node scripts/pr-checks.mjs risk --base "$base") (see AGENTS.md → \"PR risk\")"

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
