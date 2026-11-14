# Baros

Native SwiftUI workout tracker for iPhone with a SwiftData-backed offline workout log.

## Requirements

- Xcode 26+
- iOS Simulator runtime
- XcodeGen

## Commands

- Generate project: `xcodegen generate`
- Run logic tests (macOS, no simulator): `swift test --package-path BarosCore`
- Build simulator app: `xcodebuild build -project Baros.xcodeproj -scheme Baros -destination generic/platform=iOS\ Simulator -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- Run full XCTest suite: `xcodebuild test -project Baros.xcodeproj -scheme Baros -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- Run hosted unit tests only: `xcodebuild test -project Baros.xcodeproj -scheme BarosUnitTests -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- Run UI tests only: `xcodebuild test -project Baros.xcodeproj -scheme Baros -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -only-testing:BarosUITests -derivedDataPath /private/tmp/codex-ios-app-derived-data`

## Testing

Non-UI logic (models, persistence, sync, formatting, export, ownership, and the
workout engine) lives in the local Swift package `BarosCore/`, which builds for
iOS 26 and macOS 26. Its tests in `BarosCore/Tests/BarosCoreTests` run on macOS
with `swift test --package-path BarosCore` in seconds and need no simulator, so
use that loop for logic changes.

`BarosTests` stays hosted in `Baros.app` for the tests that need the app or UI
frameworks: SwiftUI and UIKit types, app lifecycle, the real app bundle and its
Info.plist, entitlements, Sentry adapters, Live Activities, and launch order.
Use the simulator for those, for `BarosUITests`, and for final evidence.

`BarosCore` must not import SwiftUI, UIKit, ActivityKit, StoreKit, Clerk,
Sentry, or ConvexMobile. When package code needs one of them, the package
declares a protocol or closure and the app supplies the adapter.

## CI

Pull requests classify changed paths before selecting the relevant GitHub
Actions checks. Pushes to `main` use the same path boundaries. The checks are:

- `baros-core-tests`: runs `swift test --package-path BarosCore` on macOS, with no simulator. It does not retry failed tests: without a simulator, a failure is almost always real.
- `ios-unit-tests`: builds the `BarosUnitTests` scheme and runs the hosted `BarosTests`.
- `ios-ui-smoke`: runs four deterministic UI tests covering completed workout logging, workout/tab navigation, a settings-triggered sync request, and signed-out local-data reset.
- `convex-checks`: runs Convex Vitest coverage and Convex typecheck.
- `support-site-checks`: builds, checks, and tests the Astro support site, including any tracked release-asset contracts.

The three app jobs report as skipped on support-site-only or unrelated pull
requests, which preserves their required-check results without reserving a
macOS runner. Changes to `convex/auth.config.ts` are app-relevant because the
Swift unit suite validates that file's Clerk audience and OIDC contract.

The UI smoke job intentionally selects only the four tests below instead of making the full `BarosUITests` target part of the required PR gate. Each selected test uses the UI suite's deterministic reset and in-memory launch helper. If an app job fails, first inspect the GitHub Actions log. A failed iOS job also uploads its `.xcresult` bundle and test log for local Xcode inspection; a failed `baros-core-tests` job uploads its `swift test` log.

Run the exact UI smoke shard locally with:

```sh
rm -rf /private/tmp/BarosUISmoke.xcresult
xcodebuild test \
  -project Baros.xcodeproj \
  -scheme Baros \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:BarosUITests/BarosUITests/testLogWorkoutSmoke \
  -only-testing:BarosUITests/BarosUITests/testTabNavigationAndFinishSheetSmoke \
  -only-testing:BarosUITests/BarosUITests/testSettingsEditRequestsSyncInUITestMode \
  -only-testing:BarosUITests/BarosUITests/testDeleteLocalDataReturnsToSettingsAfterReset \
  -derivedDataPath /private/tmp/baros-ui-smoke-derived-data \
  -resultBundlePath /private/tmp/BarosUISmoke.xcresult
```

The command must execute exactly 4 tests with no failures. CI reads the result bundle and fails the smoke gate unless `totalTestCount` is exactly 4, so a stale selector cannot silently reduce coverage.

The canonical local UI-suite command is the `Run UI tests only` command above. Keep the full UI target out of the required PR gate until issue #63 establishes repeated full-suite stability.

Before adding a UI test, read the UI-test policy in `AGENTS.md` → "UI tests"; most changes need only a unit test.

### Nightly full UI suite

`.github/workflows/ios-ui-nightly.yml` runs the whole `BarosUITests` target (`-only-testing:BarosUITests`) every night at 09:23 UTC on `main`, unless `main` hasn't changed since the last scheduled run (see below). It has no `pull_request` or `push` trigger, so it is never a PR check. Its `ios-ui-full` job uses the smoke job's Xcode 26.5 / iOS 26.5 simulator setup, runs on one simulator with parallel testing disabled, has a 120-minute timeout, and retries a failing test once, like the smoke gate. The run log and step summary list:

- the executed, passed, failed, and skipped test counts from the `.xcresult`
- tests that passed only on retry, from `ci_scripts/report_retried_tests.py`
- tests that still failed, from `ci_scripts/report_failed_tests.py`

A failed run uploads its `.xcresult` and log as the `BarosUIFull-xcresult` artifact.

Before any macOS job, a cheap `nightly-change-detection` job on `ubuntu-latest` compares `main`'s HEAD SHA with the head SHA of the last completed scheduled run of this workflow (cancelled runs are ignored). If they match, the scheduled run skips `ios-ui-full` and never reserves a macOS runner, and the tracking issue is left as it is. A manual `workflow_dispatch` always runs the suite. If the run history can't be read, the gate runs the suite rather than skipping it.

Runs on `main` keep one tracking issue, **Nightly full UI suite is failing**, in sync. A failed run opens the issue, or comments on it if it is already open, with the run link and the failed test names. The next passing run closes it. Runs on other branches leave the issue alone.

Trigger a run manually from the Actions tab (**iOS UI Nightly** → **Run workflow**), or with:

```sh
gh workflow run ios-ui-nightly.yml --ref main
```

Use `--ref <branch>` to test a branch. GitHub only dispatches workflows whose file already exists on `main`.

Repeated green nightly runs are the evidence issue #63 needs before a 15–20 test tier is promoted into the PR gate. If the suite outgrows the timeout, shard it across 2–3 jobs by test class. Most tests are currently in the `BarosUITests` class, so that class would have to be split first for the shards to be balanced.

Local equivalents:

```sh
swift test --package-path BarosCore
xcodebuild test -project Baros.xcodeproj -scheme BarosUnitTests -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.5 -derivedDataPath /private/tmp/codex-ios-app-derived-data
pnpm install --frozen-lockfile
pnpm run convex:test
pnpm run convex:typecheck
```

## Convex Setup

Convex auth requires the Clerk JWT issuer domain to be configured on each Convex deployment. For the current development Clerk instance, set:

```sh
pnpm exec convex env set CLERK_JWT_ISSUER_DOMAIN 'https://glad-krill-22.clerk.accounts.dev'
```

Then push the backend functions to the development deployment:

```sh
pnpm exec convex dev --once
```

Do not rely on a backend fallback for this value. Staging and production deployments should set their own Clerk issuer domain before deploying Convex functions.

### Production Convex reference

Release builds point at the production Convex deployment:

```sh
https://sensible-reindeer-16.convex.cloud
```

Use this section when preparing an App Store release candidate or troubleshooting production auth/sync. Routine app changes do not require running the full production smoke every time.

The production Clerk JWT template is configured for Convex:

- JWT issuer: `https://clerk.baros.fit`
- JWT audience: `convex`

Verify the production Convex deployment uses the matching issuer domain:

```sh
pnpm exec convex env --prod get CLERK_JWT_ISSUER_DOMAIN
```

#### Production deploys

Every push to `main` that touches the backend deploys to production. The `deploy` job in `.github/workflows/convex-ci.yml` runs only after `convex-checks` passes. It never runs on pull requests. It reads `CONVEX_DEPLOY_KEY` from the `convex-production` GitHub environment. That environment is separate from Vercel's `Production` environment, which belongs to the support site. Check the Actions tab to see what shipped and when.

Merging to `main` is deploying, so every backend change must keep working with every app build still installed. Users update the App Store build late, or never. Remove a public function, or tighten its arguments or return shape, only after no supported build calls it. Schema changes must accept the data already in production. Convex rejects a deploy whose schema doesn't match existing documents, and the run fails without shipping.

Deploy by hand only as a fallback, for example when the Action is broken or production needs a redeploy without a new commit. Deploy from an up-to-date `main` so production still matches it:

```sh
pnpm exec convex deploy
pnpm exec convex function-spec --prod
```

#### Production smoke

For RC validation or production auth/sync troubleshooting, run a focused production smoke:

1. Sign in with the production Clerk account flow from a Release or TestFlight build.
2. Confirm Settings shows Sync Status: Up to date.
3. Exercise the release smoke flow that needs Convex auth, such as account deletion.
4. If a direct `authSmoke:me` check is needed, run it from a Debug build temporarily pointed at the production Clerk and Convex values because Developer Diagnostics is Debug-only.

Record smoke-test evidence on the relevant release issue when the check is part of release validation.

## Agent / MCP Workflow

This repo includes `.xcodebuildmcp/config.yaml` for agents that use XcodeBuildMCP.

Install XcodeBuildMCP locally and install its MCP server skill:

```sh
xcodebuildmcp init --client agents --skill mcp
```

Then run project setup as needed:

```sh
xcodebuildmcp setup
```

Keep physical device IDs and machine-specific simulator UUIDs in local session defaults. Do not commit them to the repo config.
