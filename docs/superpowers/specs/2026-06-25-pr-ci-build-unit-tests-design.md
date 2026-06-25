# PR CI Build and Unit Tests Design

## Context

GitHub issue 74 adds the first blocking GitHub Actions baseline for LiftingLog pull requests. The app needs a required CI signal that proves the iOS app still builds, the unit test target passes, and the Convex backend tests/typecheck remain healthy.

The shared `LiftingLog` Xcode scheme currently includes both `LiftingLogTests` and `LiftingLogUITests`. Prior UI test validation found the full UI suite too unstable and slow for an initial blocking PR gate, so this workflow must use the `LiftingLogUnitTests` scheme to run only `LiftingLogTests`.

The repo already documents the canonical local unit-test command in `README.md`, and `package.json` exposes stable local Convex scripts:

- `pnpm run convex:test`
- `pnpm run convex:typecheck`

Local verification during design showed the Convex suite passes with 39 Vitest tests and `convex typecheck` passes without live deployment access.

## Goals

- Add a GitHub Actions workflow for pull requests and pushes to `main`.
- Provide two clear required checks: one for iOS build/unit tests and one for Convex checks.
- Run the `LiftingLogTests` unit target without invoking `LiftingLogUITests`.
- Make iOS failures diagnosable from the Actions log first, then from a downloadable `.xcresult` artifact when needed.
- Keep the workflow suitable for branch protection.

## Non-Goals

- Do not add the full UI test suite to the required PR gate.
- Do not add live Convex deployment smoke tests or require Convex deployment secrets.
- Do not configure GitHub branch protection inside this issue unless handled separately through repository settings or API.
- Do not change app behavior or test implementation as part of the CI workflow design.

## Recommended Approach

Create one workflow with two independent jobs:

1. `ios-unit-tests`
2. `convex-checks`

Both jobs should be required by branch protection after the workflow lands. Keeping them separate makes failures easier to interpret: iOS failures stay tied to Xcode output and result bundles, while Convex failures stay tied to Vitest or TypeScript output.

## Workflow Triggers

The workflow should run on:

- `pull_request`, so every opened PR and every new push to an open PR branch gets fresh validation.
- `push` to `main`, so the main branch keeps a known-good baseline after merges.

The `push` trigger does not need to run for every feature branch because the pull request trigger already covers active PR branches.

## iOS Unit Test Job

The `ios-unit-tests` job should run on a hosted macOS runner with Xcode and iOS 26 simulator support.

The job should:

- Check out the repository.
- Select or rely on an Xcode installation that supports the repo's iOS 26 deployment target.
- Resolve Swift packages as part of the `xcodebuild test` flow or with an explicit package-resolution step.
- Run `xcodebuild test` for the `LiftingLogUnitTests` scheme.
- Use a stable simulator destination matching the hosted image's available iOS 26 simulator runtime.
- Write DerivedData and the result bundle under `${{ runner.temp }}`.

The command should follow this shape:

```sh
xcodebuild test \
  -project LiftingLog.xcodeproj \
  -scheme LiftingLogUnitTests \
  -destination "${IOS_TEST_DESTINATION}" \
  -derivedDataPath "${RUNNER_TEMP}/LiftingLogDerivedData" \
  -resultBundlePath "${RUNNER_TEMP}/LiftingLogTests.xcresult"
```

The workflow should define `IOS_TEST_DESTINATION` as the exact simulator name and OS available on the chosen GitHub Actions runner image. The implementation plan should confirm that value before finalizing the workflow.

## iOS Failure Output

When `ios-unit-tests` fails, the developer should first inspect the failed check's normal GitHub Actions log. That log should include the `xcodebuild` output directly.

If the log is not enough, the workflow should upload the `.xcresult` bundle as a failure-only artifact named clearly, such as `LiftingLogTests-xcresult`. On the GitHub Actions workflow run page, it will appear in the Artifacts section. Downloading that artifact and opening the result bundle in Xcode should provide the richer local test report.

Successful runs should not upload the result bundle, keeping normal CI runs clean.

## Convex Checks Job

The `convex-checks` job should run independently from the iOS job on Ubuntu.

The job should:

- Check out the repository.
- Install the pnpm version declared by `packageManager`.
- Install dependencies with `pnpm install --frozen-lockfile`.
- Run `pnpm run convex:test`.
- Run `pnpm run convex:typecheck`.

These checks use local code and in-memory Convex test support. They should not require a Convex deployment token, Clerk secret, or networked deployment state beyond normal dependency installation.

## Branch Protection

After the workflow lands and runs successfully at least once, branch protection should require:

- `ios-unit-tests`
- `convex-checks`

The PR body should call out these exact check names so repository settings can be updated without ambiguity.

## Error Handling

The workflow should fail fast within each job, but one job should not hide the other job's result. Independent jobs let GitHub show whether the failure is iOS-only, Convex-only, or both.

The iOS artifact upload step should run with a failure condition so the `.xcresult` is preserved even when `xcodebuild test` exits nonzero.

## Testing and Verification

Before opening the PR:

- Run the local iOS unit-test command with `-only-testing:LiftingLogTests` and confirm it does not run `LiftingLogUITests`.
- Run `pnpm run convex:test`.
- Run `pnpm run convex:typecheck`.
- Review the generated workflow syntax for valid triggers, job names, and artifact upload conditions.

After opening the PR:

- Confirm GitHub Actions runs both jobs.
- Confirm a new push to the PR branch reruns the `pull_request` workflow.
- If possible, confirm a deliberately failed iOS run uploads a downloadable `.xcresult` artifact before relying on it for diagnostics.
