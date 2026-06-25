# PR CI Build and Unit Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add blocking-ready GitHub Actions checks for iOS build/unit tests and Convex backend validation.

**Architecture:** Create one workflow with two independent jobs: `ios-unit-tests` on `macos-26`, and `convex-checks` on `ubuntu-latest`. Document the same local commands in `README.md` so the PR body and branch protection setup can point to stable check names and diagnostics behavior.

**Tech Stack:** GitHub Actions, Xcode 26.5, iOS Simulator 26.5, XCTest, pnpm 10.26.1, Vitest, Convex CLI/typecheck.

---

## File Structure

- Create `.github/workflows/pr-ci.yml`: Defines the pull request and `main` push workflow with `ios-unit-tests` and `convex-checks`.
- Modify `README.md`: Adds a short CI section with required check names, local equivalents, and the `.xcresult` artifact behavior.

## Task 1: Add GitHub Actions CI Workflow

**Files:**
- Create: `.github/workflows/pr-ci.yml`

- [ ] **Step 1: Confirm the workflow directory is ready**

Run:

```bash
mkdir -p .github/workflows
test ! -e .github/workflows/pr-ci.yml
```

Expected: command exits `0`, confirming this is a new workflow file.

- [ ] **Step 2: Create the workflow**

Create `.github/workflows/pr-ci.yml` with this exact content:

```yaml
name: PR CI

on:
  pull_request:
  push:
    branches:
      - main

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ios-unit-tests:
    name: ios-unit-tests
    runs-on: macos-26
    timeout-minutes: 30
    env:
      IOS_TEST_DESTINATION: platform=iOS Simulator,name=iPhone 17,OS=26.5
      IOS_DERIVED_DATA_PATH: ${{ runner.temp }}/LiftingLogDerivedData
      IOS_RESULT_BUNDLE_PATH: ${{ runner.temp }}/LiftingLogTests.xcresult
      IOS_TEST_LOG_PATH: ${{ runner.temp }}/LiftingLogTests.log

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Select Xcode 26.5
        run: sudo xcode-select -s /Applications/Xcode_26.5.app

      - name: Show Xcode and simulator environment
        run: |
          xcodebuild -version
          xcrun simctl list devices available | grep -E "iPhone 17" || true

      - name: Resolve Swift packages
        run: |
          xcodebuild -resolvePackageDependencies \
            -project LiftingLog.xcodeproj \
            -scheme LiftingLog \
            -derivedDataPath "${IOS_DERIVED_DATA_PATH}"

      - name: Run LiftingLog unit tests
        run: |
          set -o pipefail
          xcodebuild test \
            -project LiftingLog.xcodeproj \
            -scheme LiftingLogUnitTests \
            -destination "${IOS_TEST_DESTINATION}" \
            -derivedDataPath "${IOS_DERIVED_DATA_PATH}" \
            -resultBundlePath "${IOS_RESULT_BUNDLE_PATH}" \
            2>&1 | tee "${IOS_TEST_LOG_PATH}"

      - name: Upload iOS failure diagnostics
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: LiftingLogTests-xcresult
          path: |
            ${{ env.IOS_RESULT_BUNDLE_PATH }}
            ${{ env.IOS_TEST_LOG_PATH }}
          if-no-files-found: warn
          retention-days: 14

  convex-checks:
    name: convex-checks
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Set up pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 10.26.1
          run_install: false

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: pnpm

      - name: Install Node dependencies
        run: pnpm install --frozen-lockfile

      - name: Run Convex tests
        run: pnpm run convex:test

      - name: Run Convex typecheck
        run: pnpm run convex:typecheck
```

- [ ] **Step 3: Validate YAML syntax**

Run:

```bash
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/pr-ci.yml'); puts 'workflow yaml parses'"
```

Expected output:

```text
workflow yaml parses
```

- [ ] **Step 4: Review the workflow diff**

Run:

```bash
git diff -- .github/workflows/pr-ci.yml
```

Expected:

- The workflow has exactly two jobs named `ios-unit-tests` and `convex-checks`.
- The iOS command uses the `LiftingLogUnitTests` scheme.
- The workflow does not contain `LiftingLogUITests`.
- The artifact upload step uses `if: failure()`.

- [ ] **Step 5: Commit the workflow**

Run:

```bash
git add .github/workflows/pr-ci.yml
git commit -m "Add blocking PR CI workflow"
```

Expected: commit succeeds.

## Task 2: Document CI Checks and Local Commands

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Insert a CI section after the Commands list**

Modify `README.md` so the section after the existing command list looks like this:

```markdown
## CI

Pull requests and pushes to `main` run two GitHub Actions checks:

- `ios-unit-tests`: builds the `LiftingLogUnitTests` scheme and runs `LiftingLogTests`.
- `convex-checks`: runs Convex Vitest coverage and Convex typecheck.

The iOS job intentionally excludes `LiftingLogUITests` from the required PR gate. If `ios-unit-tests` fails, first inspect the GitHub Actions log. The failed workflow run also uploads a `LiftingLogTests-xcresult` artifact containing the `.xcresult` bundle and test log for local Xcode inspection.

Local equivalents:

```sh
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLogUnitTests -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.5 -derivedDataPath /private/tmp/codex-ios-app-derived-data
pnpm install --frozen-lockfile
pnpm run convex:test
pnpm run convex:typecheck
```

## Convex Setup
```

Keep the existing `## Convex Setup` heading and content immediately after the new CI section.

- [ ] **Step 2: Confirm README headings**

Run:

```bash
rg -n "^## (Commands|CI|Convex Setup)" README.md
```

Expected output includes:

```text
9:## Commands
18:## CI
35:## Convex Setup
```

Line numbers may shift by a few lines if surrounding content changes, but the heading order must be `Commands`, `CI`, `Convex Setup`.

- [ ] **Step 3: Confirm README names match workflow names**

Run:

```bash
rg -n "ios-unit-tests|convex-checks|LiftingLogTests-xcresult|LiftingLogUITests" README.md .github/workflows/pr-ci.yml
```

Expected:

- `ios-unit-tests` appears in both files.
- `convex-checks` appears in both files.
- `LiftingLogTests-xcresult` appears in both files.
- `LiftingLogUITests` does not appear in `.github/workflows/pr-ci.yml`.
- `LiftingLogUITests` still appears in the README's local UI-test command and in the CI sentence explaining that UI tests are excluded.

- [ ] **Step 4: Commit README documentation**

Run:

```bash
git add README.md
git commit -m "Document PR CI checks"
```

Expected: commit succeeds.

## Task 3: Verify Local Commands and Final Diff

**Files:**
- No planned file edits. If verification exposes a workflow or documentation mistake, fix the relevant file and commit the fix with a focused message.

- [ ] **Step 1: Validate workflow YAML after all edits**

Run:

```bash
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/pr-ci.yml'); puts 'workflow yaml parses'"
```

Expected output:

```text
workflow yaml parses
```

- [ ] **Step 2: Run Convex tests**

Run:

```bash
pnpm run convex:test
```

Expected output includes:

```text
Test Files  1 passed (1)
Tests  39 passed (39)
```

- [ ] **Step 3: Run Convex typecheck**

Run:

```bash
pnpm run convex:typecheck
```

Expected output includes:

```text
Typecheck passed
```

- [ ] **Step 4: Run the local iOS unit-test target only**

Run:

```bash
RESULT_BUNDLE="/private/tmp/LiftingLogTests-issue74-$(date +%Y%m%d%H%M%S).xcresult"
xcodebuild test \
  -project LiftingLog.xcodeproj \
  -scheme LiftingLogUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /private/tmp/codex-ios-app-derived-data \
  -resultBundlePath "${RESULT_BUNDLE}"
```

Expected:

- The command exits `0`.
- Output includes `Test Suite 'LiftingLogTests.xctest' passed`.
- Output does not include `LiftingLogUITests.xctest`.

- [ ] **Step 5: Inspect final status and log**

Run:

```bash
git status --short
git log --oneline -5
```

Expected:

- `git status --short` is empty.
- Recent history includes:
  - `Add PR CI design spec`
  - `Add blocking PR CI workflow`
  - `Document PR CI checks`

- [ ] **Step 6: Prepare PR notes**

Use this in the PR body:

```markdown
## Summary

- Add a `PR CI` GitHub Actions workflow for pull requests and pushes to `main`.
- Add required-check candidates `ios-unit-tests` and `convex-checks`.
- Upload `LiftingLogTests-xcresult` diagnostics when the iOS unit-test job fails.
- Document the local CI equivalents in `README.md`.

## Verification

- `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/pr-ci.yml'); puts 'workflow yaml parses'"`
- `pnpm run convex:test`
- `pnpm run convex:typecheck`
- `RESULT_BUNDLE="/private/tmp/LiftingLogTests-issue74-$(date +%Y%m%d%H%M%S).xcresult" && xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLogUnitTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/codex-ios-app-derived-data -resultBundlePath "${RESULT_BUNDLE}"`

## Branch Protection Follow-up

After this workflow runs successfully on GitHub, require these checks before merge:

- `ios-unit-tests`
- `convex-checks`
```
