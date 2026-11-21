# AGENTS.md

- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- Never open a draft pull request unless the user explicitly asks for one; otherwise, open a regular, ready-for-review pull request.
- Merging `convex/` changes to `main` deploys them to production. Before changing a public Convex function or the schema, read README → "Production deploys" for the compatibility rule with installed app builds.

## Pull requests

- Write the description in the layout of `.github/pull_request_template.md`. `gh pr create --body-file` skips the template, so start from that file.
- UI or visual changes need before/after screenshots in the PR description. For new UI, include screenshots of the new screen or state.
- Changes to motion, timing, gestures, navigation, or other interactions need a short screen recording showing the changed behavior.
- Capture evidence from the running app after the final relevant changes. State the device or simulator and iOS version. Build and test success do not substitute for visual evidence.
- Upload PR evidence directly to GitHub and verify that it renders in the PR. Never commit PR-only screenshots or recordings, including directories such as `.github/pr-assets/`.
- If presentation-related files change without affecting visible UI or interactions, explain why in the PR description under "No visual impact."
- The merged PR is the record. Plans, QA notes, and evidence go in the PR or its issue; only durable decisions go in the repo, in `docs/adr/`.

## PR risk

CI labels each PR by what it touches, not how much (`HIGH_RISK_AREAS` in `scripts/pr-checks.mjs`):

- **`risk:high`** changes code in an area where a mistake can lose a user's workouts or reaches production on merge: stored data models (any `@Model`, and the enums they store by raw value), sync, code that edits saved data (the mutation services and any app file that queues uploads), sign-out, local-data reset, account deletion, or workout recovery (including the UI that starts them), or anything the Convex deploy ships or installs (`convex/` sources other than tests, simulator files, and type declarations; `package.json`, `pnpm-lock.yaml`, `convex-ci.yml`).
- **`risk:low`** changes only docs, tests, or comments in Swift files, and removes no tests.
- **`risk:medium`** is everything else.

A Swift file whose code is unchanged once comments are removed doesn't count, so a large comment cleanup can be low and a one-line merge change is high. Comment edits in other languages still count. A `risk:high` PR shows this proof under Tests, for each area the label's PR comment names:

- **Stored data models:** new fields are optional or defaulted, and a `BarosCore` test opens a store written with the shipped models and checks every row survives the migration.
- **Sync, or edits to saved data:** a test that fails without the change for each behavior it changes, and the existing sync tests pass.
- **Sign-out, local-data reset, account deletion, or workout recovery:** run that flow's `BarosUITests` on a pool simulator with `-only-testing:BarosUITests/<Class>/<test>`, and name the tests. Don't run the whole suite for this; the nightly run covers it on `main`.
- **Convex:** a "Production deploy compatibility" section that says how installed builds keep working (README → "Production deploys").

## Testing

- Before you push, run `scripts/check-changed.sh`. It runs the CI checks for the paths the branch changed, builds the app and test targets, checks test hygiene, and prints the PR's risk. Hosted `BarosTests` and `BarosUITests` need a simulator, so run the affected ones yourself; CI's `ios-unit-tests` runs all of `BarosTests`.
- Tests wait on events, not time. A new sleep in a test target needs `// allow-sleep: <why>` at the end of its line or as a comment on the line directly above. A new skip names its tracking issue (`#403`) or carries `// allow-skip: <why>` in the same places. CI's `test-hygiene` check enforces both on added lines; it catches the common calls, and the rule covers every way of waiting on time.
- Logic lives in the `BarosCore` package. Test it on macOS with `swift test --package-path BarosCore`; that is the default loop for any change outside SwiftUI views and app wiring.
- New logic and its tests go in `BarosCore` when they need only Foundation, SwiftData, or other cross-platform frameworks. Code that imports SwiftUI, UIKit, ActivityKit, StoreKit, Clerk, Sentry, or ConvexMobile stays in `Baros/`; when package code needs it, define a protocol in the package and keep the adapter in the app, as `CurrentOwnerAdapters` and `ConvexClientFactory` do. Mark only what the app uses `public`.
- Name test `UserDefaults` suites `"<TestType>.\(UUID().uuidString)"`. Every `swift test` process on the Mac shares one preferences store, so a fixed suite name collides with other worktrees' runs.
- Reserve a simulator only for hosted `BarosTests` (UI types, app lifecycle, the real bundle and entitlements, launch order), `BarosUITests`, and final PR evidence.

## UI tests

A full `BarosUITests` run takes about two hours in CI, so the suite covers only behavior that lives in the UI layer.

- Cover a bug fix or feature with a unit test by default: in `BarosCore/Tests` for package logic, or `BarosTests/` for app-layer code (see Testing). That includes values, formatting, sorting, sync and auth decisions, and save-failure handling.
- Add or extend a UI test only for:
  - layout or Dynamic Type;
  - keyboard and focus;
  - gestures and hit targets;
  - navigation, sheets, and presentation;
  - persistence across relaunch or backgrounding;
  - the end-to-end data-safety flows: sign-out, local-data reset, account deletion, and active-workout recovery.
- Add assertions to an existing flow test that already passes through the screen before writing a new test.
- Build on the shared helpers in `BarosUITests/BarosUITests.swift`: launch with `makeApp`, seed state with `--uitest-*` launch arguments (`UITestFixtureSeeder`), and wait with `waitToExist`, `waitToDisappear`, or `waitUntil`, not sleeps. XCTest's own waiters add about 1 s per call; the `waitUntil` doc comment explains why, and names the one case where `waitForExistence` still fits.
- The four `ios-ui-smoke` tests and CI's `totalTestCount == 4` check change only on purpose, with the README "CI" section and `.github/workflows/app-ci.yml` updated in the same PR.

## Review guidelines

- Treat as P0 any change that can lose or overwrite a user's logged workouts: sync merges, SwiftData model changes, sign-out, local-data reset, and account deletion.
- Flag a PR that carries more risk than its `risk:` label, such as a change to code that sync or a data-safety flow calls from outside the paths the label checks.
- Flag a change to a public Convex function's arguments or return shape, or to `convex/schema.ts`, that installed builds can't handle (README → "Production deploys").
- Flag logic tested through `BarosUITests` or hosted `BarosTests` that `BarosCore` could test, and new UI tests outside the list in "UI tests".
- Flag new tests that repeat a case an existing test covers, or check what the types already guarantee.
- Flag each new `allow-sleep:` or `allow-skip:` whose reason doesn't hold up.
- Flag a visible UI change without before/after screenshots, and a "No visual impact" section the diff contradicts.

## Simulator storage

- Reuse existing simulators. Never create or clone a device per issue, session, or worktree, or download/install runtimes unless the user explicitly requests that provisioning work.
- On Kevin's Mac, use the device UUIDs in `~/.claude/simulator-pool.json`: the two regular iOS devices are for normal QA; other listed versions are for explicit compatibility checks. At most two devices may run or be reserved at once, with one device per session. If both slots are busy, wait instead of creating another device.
- Check existing ownership before installing, launching, testing, or changing a simulator. Where the machine-local Claude guard is installed, inspect reservations with `python3 ~/.claude/hooks/simulator-storage-guard.py status`; Claude's hook reserves automatically. Other agents must coordinate ownership and respect those reservations rather than assume a device is free.
- In T3 Code, use `device_list` and `device_open` to select the device and expose it in the Device panel. Use the returned `agent-device` command for app launches, interaction, screenshots, and recordings, and `device_screenshot` to inspect the screen. Follow the device tools' ownership and error guidance. Do not bypass them with `simctl`, `idb`, or `adb` for those actions; build, install, log, and test-runner commands remain available.
- Set XcodeBuildMCP session defaults with an explicit simulator UUID; device names repeat across runtimes. Keep project paths and build outputs scoped to the current worktree, and do not commit machine-specific session defaults. Run simulator tests with `-parallel-testing-enabled NO` and `-maximum-concurrent-test-simulator-destinations 1` to prevent test-worker clones.
- When finished, release only resources owned by your session through the mechanism that reserved them. For a Claude guard reservation, `python3 ~/.claude/hooks/simulator-storage-guard.py release <session_id>` shuts down and releases the owned device; Claude's SessionEnd hook does the same. Do not shut down another session's device, erase devices, or delete their app data.

<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

<!-- convex-ai-end -->

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `Tatooles/baros`; external PRs are not a triage surface. For issues, milestones, and linking PRs to issues, see `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Use a single-context domain docs layout. See `docs/agents/domain.md`.
