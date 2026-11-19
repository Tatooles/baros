#!/usr/bin/env bash
# Create the two annotated tags that record a shipped release, and optionally push them.
#
#   tag-release.sh --version 1.5 --build 170 --commit <sha> --run <xcode-cloud-run-id> --date 2026-11-20 [--push]
#
# Tags (matching earlier releases):
#   v<semver>                     "Baros <semver>; App Store build <build>"
#   app-store-<version>-build-<n> "App Store Baros <version> build <n>; Xcode Cloud run <id>; released <date>"
#
# Existing tags are never moved: a tag already at the commit is reused, a tag elsewhere is an error.
set -euo pipefail

version="" build="" commit="" run="" date="" push=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --build) build="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;;
    --run) run="$2"; shift 2 ;;
    --date) date="$2"; shift 2 ;;
    --push) push=true; shift ;;
    *) echo "error: unknown argument $1" >&2; exit 2 ;;
  esac
done
for v in version build commit run date; do
  [[ -n "${!v}" ]] || { echo "error: --$v is required" >&2; exit 2; }
done
[[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "error: --date must be YYYY-MM-DD" >&2; exit 2; }

commit="$(git rev-parse --verify "${commit}^{commit}")"
semver="$version"
[[ "$semver" =~ ^[0-9]+\.[0-9]+$ ]] && semver="${semver}.0"

make_tag() {
  local name="$1" message="$2" existing
  if existing="$(git rev-parse -q --verify "refs/tags/${name}^{commit}")"; then
    [[ "$existing" == "$commit" ]] || { echo "error: $name already points at $existing, not $commit" >&2; exit 1; }
    echo "exists: $name -> $commit"
  else
    git tag -a "$name" -m "$message" "$commit"
    echo "created: $name -> $commit"
  fi
}

semantic="v${semver}"
audit="app-store-${version}-build-${build}"
make_tag "$semantic" "Baros ${semver}; App Store build ${build}"
make_tag "$audit" "App Store Baros ${version} build ${build}; Xcode Cloud run ${run}; released ${date}"

$push || { echo "Not pushed (rerun with --push)."; exit 0; }

git push origin "refs/tags/${semantic}" "refs/tags/${audit}"
for name in "$semantic" "$audit"; do
  remote="$(git ls-remote --tags origin "refs/tags/${name}^{}" | cut -f1)"
  [[ "$remote" == "$commit" ]] || { echo "error: remote $name resolves to '${remote}', expected $commit" >&2; exit 1; }
  echo "verified on origin: $name -> $commit"
done
