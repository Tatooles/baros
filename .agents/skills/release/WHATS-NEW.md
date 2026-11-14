# What's New

One set of copy, two outputs: the in-app sheet (`Baros/App/WhatsNewVersion<major>_<minor>View.swift`) and the App Store "What's New in This Version" text in `docs/release/app-store-submission-pack.md`. The sheet's highlights are the App Store text's bullets, same words.

## 1. ⛔ Copy

From the base range's `release-diff.mjs` output and the milestone's closed issues — never a feature merged after the base — write, in the voice of the earlier entries in the submission pack:

- an intro sentence naming the headline changes;
- 2–4 **highlights** — new, visible features — each a short title, one-sentence detail, and an SF Symbol;
- "Also in this update" bullets for smaller visible changes, in user language (no internal type names, PR jargon, or test-only changes); "Performance improvements" only when the diff has some.

Show Kevin the App Store text and the highlight list with their symbols. A fixes-only release may skip the sheet — that is Kevin's choice here; the catalog entry then stays `whatsNewSheet: nil` and only the App Store text is written.

## 2. Build the sheet

On a branch from `main`, follow `git show --stat 1aa83132` (the 1.4 sheet) — it touches every file a new sheet needs:

- a new view copied from the newest `WhatsNewVersion*View.swift`, title `What's new in Baros <version>`;
- the `WhatsNewSheetID` case and the catalog entry in `AppReleaseCatalog.swift`, plus the `WhatsNewSheet` switch;
- `xcodegen generate` to add the file to the project;
- the tests that pin the newest sheet (`AppReleaseCatalogTests`, `FirstRunExperienceStoreTests`, `LaunchExperienceCoordinatorTests`, and the upgrade test in `BarosUITests`);
- the version's section at the top of "Release Notes" in the submission pack.

Run the unit tests and the edited UI tests.

## 3. ⛔ Screenshot approval

Use the simulator rules in `AGENTS.md` (pool device by UUID, the environment's device tools). Launch the Debug build with `--uitest-in-memory-store --uitest-force-signed-out-auth --uitest-skip-first-run-experience`, open the Settings tab, and tap `SettingsWhatsNewButton`. Capture:

1. light appearance;
2. dark — Settings → App Appearance → Dark, then reopen the sheet;
3. large text — relaunch with `--uitest-accessibility-dynamic-type` added.

Check them yourself first: every symbol renders, nothing clips or truncates, the Continue button is reachable. Then show all three inline in the reply as images and ask Kevin to approve or name changes. Repeat steps 1–3 until he approves.

## 4. ⛔ Merge

Open the PR with the `file-pr` skill; the approved screenshots are its visual evidence (uploaded to GitHub per `AGENTS.md`, never committed). Merge on Kevin's yes once checks are green.
