---
name: release
description: Ship the next Baros version — scope, What's New, regression, App Store submission, and the post-release record. Optionally name the build to ship.
disable-model-invocation: true
---

# Release

Takes the version in `project.yml` (`MARKETING_VERSION`) from merged work to **Pending Developer Release** in App Store Connect, hands Kevin the Release button, and after he presses it, records the release. Re-running `/release` resumes wherever the release stands.

`/release` ships from the newest `main`. `/release build <n>` ships the code of App Store Connect build `<n>` instead, so a release never has to wait for `main` to settle.

**Gate** (⛔): stop, show Kevin exactly what the next action will do, and wait for an explicit yes in this conversation. A yes covers that one action. Everything outside a gate the skill does on its own.

Scripts are in `scripts/` beside this file:

- `asc.mjs` — App Store Connect client (`check`, `runs`, `status`, `prepare`, `submit`). Writes print a plan and send only with `--apply`. It has no release command: making a version available to customers is Kevin's press in App Store Connect.
- `release-diff.mjs` — merged PRs, changed areas, and regression signals between two refs.
- `bump-version.sh`, `tag-release.sh` — mechanical edits; each prints what it changed.

Credentials live outside the repo in `~/.appstoreconnect/release.env` (Team key, App Manager role). `node scripts/asc.mjs check` confirms them; a `403 REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED` means Kevin has an agreement to accept in App Store Connect → Business.

## 0. Locate the release

`git fetch --tags origin`, then `node scripts/asc.mjs versions`. The **release version** is the one it reports as active — the newest App Store version whose `"<version> release"` milestone is still open (step 13 closes it last) — or, when none is, `MARKETING_VERSION`. `project.yml` moves to the next version at step 9, before the release is recorded, so it identifies the release only when nothing is in flight. Then `node scripts/asc.mjs status <version>` and resume at:

- no version, `PREPARE_FOR_SUBMISSION`, or `DEVELOPER_REJECTED` → the first Phase A step whose **Done when** fails
- `WAITING_FOR_REVIEW` / `IN_REVIEW` → step 8
- `REJECTED`, `METADATA_REJECTED`, `INVALID_BINARY`, or an `UNRESOLVED_ISSUES` submission → step 8's Rejected branch
- `PENDING_DEVELOPER_RELEASE` → step 9
- `READY_FOR_SALE` → step 9 while `MARKETING_VERSION` still equals the release version (Kevin released before the bump), otherwise the first Phase B step whose **Done when** fails

## Phase A — prepare and submit

### 1. Fix the base

The **base** is the commit whose code this release ships. With `build <n>`, it is that build's commit (`node scripts/asc.mjs runs --build <n>`); otherwise it is `origin/main` now. Every later range — scope, release notes, regression focus — is `v<previous>..<base>`: `node scripts/release-diff.mjs v<previous> <base>`. Work merged after the base belongs to the next release. A resumed run recovers it from App Store Connect: once a build is attached, that build's commit (`status`, then `runs --build <n>`) stands in for the base. Before that, a rerun has no record of the base — confirm it with Kevin (`/release build <n>` again keeps a pinned one).

**Done when** the base SHA is recorded and the diff for that range is in hand.

### 2. Reconcile scope

A milestone lists each change once — its issue, or the PR itself when it has no issue (`docs/agents/issue-tracker.md` → Milestones). List the milestone's issues and PRs together: `gh api --paginate 'repos/Tatooles/baros/issues?milestone=<number>&state=all&per_page=100'`. Then:

- each PR in the base range belongs on the milestone as its closing issue (`gh pr view <n> --json closingIssuesReferences`), or as itself when it closes none — add what is missing;
- each open milestone issue is *shipped* (its fix is in the range → close it) or *deferred* (→ the next open milestone), and anything merged after the base moves to the next milestone too;
- an open bug that should block the release is Kevin's call — raise it.

⛔ The list of closes, moves, and additions.

**Done when** the milestone holds exactly the changes the base range ships, each once, with none open.

### 3. What's New

Follow [WHATS-NEW.md](WHATS-NEW.md): copy for the base range only, sheet, screenshot approval, PR merged to `main`.

**Done when** the What's New PR is merged and `docs/release/app-store-submission-pack.md` on `main` holds this version's App Store text.

### 4. Build the candidate

The **candidate** is the build that ships: the exact binary the regression tests and App Review sees. Its code is the base plus nothing but the What's New merge and release fixes — check with `node scripts/release-diff.mjs <base> <candidate>` before accepting it. Three paths:

- **Kevin named a build that already holds this release's sheet, or the release has no sheet**: the candidate is the base's build, unchanged — the named build, or else the newest `main` build at or before the base.
- **No build named**: the candidate is the newest `main` build containing the What's New merge — `node scripts/asc.mjs runs`. Xcode Cloud only builds `main` when app paths change, so it can trail `main` by docs-only commits; wait for any run still building. When the check shows other PRs merged after the base, ⛔ ask Kevin to either widen the base to that build (rerun steps 1–3 for the added PRs) or take the release-branch path from the original base.
- **Otherwise — a named build without the sheet, or a base that needs fixes `main` cannot supply alone** — the release branch: cut `release/<version>` from the base and cherry-pick what it needs (`git cherry-pick -m 1 <merge>` for the What's New merge and each fix). Resolve any conflict so the code matches what `main` merged, then run the unit tests. ⛔ Push the branch. Xcode Cloud's "Main Branch Build" workflow also builds `release/` branches; the candidate is that run (`node scripts/asc.mjs runs --branch release/<version>`).

Check GitHub's checks on a `main` candidate: `gh api repos/Tatooles/baros/commits/<sha>/check-runs --jq '.check_runs[] | "\(.name) \(.conclusion)"'`. A release branch gets no GitHub Actions run; the regression's unit and UI suites stand in.

**Done when** you have the candidate's commit SHA, build number (`COMPLETE/SUCCEEDED`, `VALID`), and Xcode Cloud run ID, and its checks are green or the release-branch exception applies.

### 5. Regression

Follow [REGRESSION.md](REGRESSION.md) on the candidate commit. A blocker gets a fix PR to `main` (⛔ merge), then back to step 4 — the fixed candidate still holds only the base plus release changes, so a pinned base reaches the fix through the release branch.

**Done when** the regression report shows no blockers.

### 6. Prepare the App Store version

Copy this version's text from the submission pack into a scratch file, byte for byte. Run `node scripts/asc.mjs prepare <version> --build <n> --whats-new <file>`, read the plan, then rerun with `--apply`. This only edits the draft, so it needs no gate.

The API cannot reach the App Privacy answers. When the range adds data collection, a tracking or analytics SDK, or changes `PrivacyInfo.xcprivacy`, ask Kevin to update App Privacy in App Store Connect (or walk the page with him in the in-app browser).

**Done when** `status` shows the candidate build attached, `releaseType: MANUAL`, and What's New identical to the pack.

### 7. ⛔ Submit for review

Show Kevin the `status` output and the regression report. On yes: `node scripts/asc.mjs submit <version>`, check the plan, `--apply`.

**Done when** `status` shows the submission `WAITING_FOR_REVIEW`.

### 8. Await review

Review usually takes a day or two. End the turn: tell Kevin to rerun `/release` when Apple emails. On the rerun:

- **Approved** (`PENDING_DEVELOPER_RELEASE`) → step 9.
- **Rejected** → the reason lives in App Store Connect's App Review messages, outside the API: ask Kevin to paste it, or read it with him in the in-app browser. Metadata-only fixes go straight into App Store Connect. Binary fixes take a fix PR to `main` (⛔ merge), a new candidate (step 4, same base rule), regression on the fix's area, `prepare` with the new build, then the resubmission — `asc.mjs` refuses an `UNRESOLVED_ISSUES` submission, so Kevin resubmits that one from the App Store Connect page.

### 9. Bump the version, then hand off

`main` stays on this version until approval so a rejection can still ship a new build. Now move it on:

1. Next version = the lowest open milestone above this one (`gh api 'repos/Tatooles/baros/milestones?state=open' --jq '.[].title'`).
2. On a branch from `main`, run `scripts/bump-version.sh <next>`. Of the tests it lists, update those asserting the current release or its upgrade path the way commit `2ddae398` (the 1.5 bump) did — the upgrade test now expects an upgrade into an unannounced release to skip What's New. Run the unit tests and the edited UI tests.
3. Open the PR with the `file-pr` skill. ⛔ Merge it once checks are green.

Then tell Kevin: version `<version>` build `<n>` is approved and waiting — **Release This Version** in App Store Connect makes it live, and `/release` afterwards records it.

**Done when** the bump PR is merged and Kevin has the hand-off.

## Phase B — record the release

### 10. Confirm availability

`status` shows `READY_FOR_SALE`. Take the release date from Kevin's word or today's date.

### 11. ⛔ Tags

`scripts/tag-release.sh --version <v> --build <n> --commit <candidate sha> --run <run id> --date <date>`, show the two tags, then rerun with `--push`. A release branch is deleted from origin once both tags verify — the tags keep its commit.

**Done when** the script reports both tags verified on origin and no `release/<version>` branch remains.

### 12. ⛔ GitHub Release

Skip to step 13 when `gh release view v<semver>` already finds it. Draft the body in the shape of `gh release view v1.4.0`: the App Store summary with highlights in bold, the version/date/commit/audit-tag table, the App Store and closed-milestone links, and a changelog from the base range grouped into Features, Reliability and performance, and Fixes and maintenance, each line in user language with its PR numbers. No binaries attached. Show the draft; on yes, `gh release create v<semver> --verify-tag --title "Baros <semver>" --notes-file <file>`.

### 13. ⛔ Close the milestone

Append `Shipped <date>: <release url>` to the milestone's existing description (keep its scope text) and close it: `gh api -X PATCH repos/Tatooles/baros/milestones/<number> -f state=closed -f description=<existing + shipped line>`.

**Done when** the Release is public and the milestone is closed. Report the Release URL, tags, and build to Kevin.
