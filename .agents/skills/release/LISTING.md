# Listing

The **listing** is what someone sees before installing Baros: the App Store description, promotional text, keywords, and screenshots, and the app screens on baros.fit. `docs/release/listing.json` is its single source of truth. Both outputs are generated from it and from the app's own screens, so the listing always shows the build that ships.

The pipeline:

- `MarketingScreenshotTests` (a UI test that runs only through the capture script) drives the app to each shot's screen on data from `MarketingScreenshotSeeder` (`--uitest-seed-marketing`): a year of push, pull, legs, and full-body training counted back from today, with templates and supersets.
- `scripts/capture-screens.sh` runs those tests with a 9:41 status bar and writes `<shot>.png` per shot.
- `pnpm -C SupportSite listing-assets` frames the captures into the App Store set (1320×2868, for the 6.9" slot) and records each image's MD5 in `docs/release/listing-approved.json`. It also writes the baros.fit JPEGs and their hashes in `SupportSite/tests/approved-assets.json`. It needs SF Pro Display installed and stops without it.
- `node scripts/asc.mjs listing <version>` compares App Store Connect with `listing.json`. With `--screenshots <dir> --apply` it uploads only the approved images, in order.
- `SupportSite/tests/listing.test.mjs` checks on every PR that the text fits Apple's limits, every shot has a capture test, and the approved MD5s cover the shot list.

Work in `.build/listing/<version>/` (gitignored, and it outlives the session): `raw/` for captures, `app-store/` for the framed set.

## 1. Decide what changes

Start right after step 1 fixes the base; the capture runs in the background while scope and What's New proceed. From the base range's `release-diff.mjs` output and this release's What's New copy:

- **Text**: every What's New highlight appears in the description, and the promotional text names this release's headline features (`New in Baros <version>: …`). Keywords change only on Kevin's request.
- **Shots**: a headline feature with no shot gets one, replacing the weakest when the set already holds 10. A headline is two lines that say only what the screen shows, with `glowX` alternating sides. A new shot needs a test in `MarketingScreenshotTests` that calls `capture("<id>")`, plus seed data if its screen needs it.
- **Recapture** whenever the range touches app UI (`Baros/Features`, `Baros/Shared`, `Baros/App`) or the logic behind it (`BarosCore/Sources`), the seeder, the capture tests, or the shots in `listing.json`. Otherwise the current approved set stands.

**Done when** `listing.json` names every headline feature and you know whether to recapture.

## 2. Capture and generate

Capture the code that ships. When `git diff --stat <base> origin/main -- Baros BarosCore/Sources ':!BarosCore/Sources/BarosCore/App/AppReleaseCatalog.swift'` is empty (version bumps only touch the catalog), capture on `main`. Otherwise (a pinned build or a patch behind newer UI), capture in a scratch worktree at the base with the capture tooling cherry-picked onto it: `git log --format='%h %s' <base>..origin/main -- BarosCore/Sources/BarosCore/Persistence/MarketingScreenshotSeeder.swift Baros/Core/Persistence/MarketingScreenshotSeeder.swift BarosUITests/MarketingScreenshotTests.swift` lists the capture commits the base lacks. Skip "refactor: move non-UI logic into the BarosCore package" (#385): it moves the whole app, not just the seeder, and on a base from before it the seeder lives at `Baros/Core/Persistence/`. A release fix that changes UI after approval means recapturing the affected shots and approving them again.

Follow the simulator rules in `AGENTS.md` with the iPhone 17 Pro pool device; the script refuses any other. Release the device when the run ends.

```sh
scripts/capture-screens.sh <iPhone 17 Pro UUID> .build/listing/<version>/raw
pnpm -C SupportSite install
pnpm -C SupportSite listing-assets .build/listing/<version>/raw .build/listing/<version>/app-store
```

Inspect every framed image at full size and at thumbnail size. Each screen should be in the state its headline claims (a rest timer running, a superset round checked), the data should look like a real lifter's, nothing should clip under the frame, and no debug-only UI should show. Fix a bad shot in its test or the seeder and rerun. Never edit an image by hand: `asc.mjs` uploads only files whose MD5 the generator recorded.

**Done when** every shot passes that inspection and `pnpm -C SupportSite test` passes.

## 3. ⛔ Approval

Show Kevin every framed image inline in order, the baros.fit images, and the text changes. `node scripts/asc.mjs listing <live version>` prints the App Store side next to `listing.json`. Repeat steps 1–2 until he approves.

## 4. Two PRs

Open both with the `file-pr` skill. Keep the App Store images out of the repo; they go to App Store Connect.

- **Listing PR**: `listing.json`, `listing-approved.json`, and any test or seed changes. Merge it once checks are green. Step 6 uploads from `main`.
- **Site PR**: the baros.fit JPEGs and `SupportSite/tests/approved-assets.json`, with before/after images per `AGENTS.md`. Its description says to merge when `<version>` is live. Step 9 merges it with the release, so baros.fit changes when the App Store does.

**Done when** the listing PR is merged and the site PR is open with green checks.

## Between releases

Promotional text is the one field a live version accepts. To change it, merge the new text into `listing.json` and run `node scripts/asc.mjs listing <live version> --apply`, which leaves everything else alone. Every other field waits for the next version.
