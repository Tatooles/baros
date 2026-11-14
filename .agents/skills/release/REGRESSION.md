# Release regression

Two layers on the candidate commit: a **baseline** every release runs, and a **focus** chosen from this release's diff. All of it runs on the simulator; Kevin's device time is reserved for the one case the simulator cannot see (the device check below).

Setup: `git switch --detach <candidate sha>` in this worktree, and follow the simulator rules in `AGENTS.md` — a pool device by UUID, `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`, per-worktree DerivedData, and release the device when the pass ends. Test commands are in `README.md` → Commands.

## Baseline

1. **Unit suite** — the `BarosUnitTests` scheme; every test passes.
2. **Full UI suite** — `-only-testing:BarosUITests`. Record discovered and executed counts against README's current count. Rerun each failure alone up to twice: green on rerun is a **flake** (noted, a blocker only inside a focus area); red every time is a **blocker**.
3. **Release build** — build the `Release` configuration for the simulator, launch it signed out, and confirm it reaches Home. This catches configuration-only breakage that Debug tests miss.

## Focus

From the base range's `release-diff.mjs` output, name the 2–5 areas this release put most at risk: the largest user-facing changes first, then anything that can lose or corrupt data — persistence, sync, account transitions, the active workout. For each, list the PRs behind it.

For each area, drive the flows on the simulator with the device tools, the way a lifter would, from each PR's described behavior out to its edges: empty and long content, backgrounding and relaunch mid-flow, larger text (`--uitest-accessibility-dynamic-type`), dark appearance, and its interaction with the release's other changes. Use the UI-test seed arguments (`git grep -ho -- '--uitest-seed-[a-z-]*' Baros | sort -u`) to reach states quickly. Capture a screenshot per area. Where an area has no UI-test coverage (grep `BarosUITests` for its accessibility identifiers), record the gap for a follow-up issue.

The diff's **signals** add mandatory focus:

- **Upgrade test** (persisted model or schema changed): on one simulator, build the previous release tag (`git switch --detach v<previous>`), launch once with `--uitest-reset-persistent-store`, then relaunch without it and create real data that touches the changed models — a completed workout with notes and several sets, plus whatever the changed models hold. Switch back to the candidate, build, install over it, launch, and confirm every record survived intact and remains editable.
- **Backend contract** (Convex schema or functions changed): make sync a focus area, and confirm `convex-checks` passed on the merges that touched `convex/`.
- **Dependencies** (Swift packages changed): exercise the features that use the updated packages.

## Device check

Only when `release-diff.mjs` reports **YES** for *Device check*: signing, entitlements, capabilities, and the privacy manifest are verified only by a device-installed App Store–signed build. Ask Kevin to install the candidate build from TestFlight, launch it, sign in, and log one set — about two minutes. Otherwise skip it and say so in the report.

## Report

**Done when** this report exists and every line in it is filled:

- baseline: unit and UI counts (discovered / passed / flaky / failed), Release build result;
- each focus area: PRs, flows exercised, result, screenshot;
- each signal: what was run and the result;
- device check: run or skipped, and why;
- coverage gaps and flakes worth an issue.

Any blocker stops the release at step 5.
