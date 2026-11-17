# AGENTS.md

- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- Never open a draft pull request unless the user explicitly asks for one; otherwise, open a regular, ready-for-review pull request.
- Merging `convex/` changes to `main` deploys them to production. Before changing a public Convex function or the schema, read README → "Production deploys" for the compatibility rule with installed app builds.

## Pull requests

- UI or visual changes need before/after screenshots in the PR description. For new UI, include screenshots of the new screen or state.
- Changes to motion, timing, gestures, navigation, or other interactions need a short screen recording showing the changed behavior.
- Capture evidence from the running app after the final relevant changes. State the device or simulator and iOS version. Build and test success do not substitute for visual evidence.
- Upload PR evidence directly to GitHub and verify that it renders in the PR. Never commit PR-only screenshots or recordings, including directories such as `.github/pr-assets/`.
- If presentation-related files change without affecting visible UI or interactions, explain why in the PR description under "No visual impact."

## Testing

- Logic lives in the `BarosCore` package. Test it on macOS with `swift test --package-path BarosCore`; that is the default loop for any change outside SwiftUI views and app wiring.
- New logic and its tests go in `BarosCore` when they need only Foundation, SwiftData, or other cross-platform frameworks. Code that imports SwiftUI, UIKit, ActivityKit, StoreKit, Clerk, Sentry, or ConvexMobile stays in `Baros/`; when package code needs it, define a protocol in the package and keep the adapter in the app, as `CurrentOwnerAdapters` and `ConvexClientFactory` do. Mark only what the app uses `public`.
- Name test `UserDefaults` suites `"<TestType>.\(UUID().uuidString)"`. Every `swift test` process on the Mac shares one preferences store, so a fixed suite name collides with other worktrees' runs.
- Reserve a simulator only for hosted `BarosTests` (UI types, app lifecycle, the real bundle and entitlements, launch order), `BarosUITests`, and final PR evidence.

## UI tests

A full `BarosUITests` run takes close to an hour, so the suite covers only behavior that lives in the UI layer.

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
