# Listing

The **listing** is what someone sees before installing Baros: the App Store description, promotional text, keywords, and screenshots, and the app screens on baros.fit. `docs/release/listing.json` is its single source of truth. Both outputs are generated from it and from the app's own screens, so the listing always shows the build that ships.

The pipeline:

- `MarketingScreenshotTests` (UI test, skipped unless the capture script runs it) drives the app to each shot's screen, on data from `MarketingScreenshotSeeder` (`--uitest-seed-marketing`: a year of push/pull/legs/upper training, with templates and supersets).
- `scripts/capture-screens.sh` runs those tests on a dark, 9:41 simulator and writes `<shot>.png` per shot.
- `pnpm -C SupportSite listing-assets` frames them into the App Store set (1320×2868, headline and BAROS mark, for the 6.9" slot) and writes the baros.fit JPEGs plus their hashes in `SupportSite/tests/site-identity.test.mjs`.
- `node scripts/asc.mjs listing <version>` compares App Store Connect with `listing.json`; `--screenshots <dir> --apply` makes it match.

## 1. Decide what changes

From the base range's `release-diff.mjs` output and this release's What's New copy:

- **Text** — every What's New highlight appears in the description, and the promotional text names this release's headline features (`New in Baros <version>: …`, 170 characters at most). Keywords change only on Kevin's request.
- **Shots** — a headline feature with no shot gets one, replacing the weakest when the set already holds 10. A shot's `headline` is two lines of about 24 characters, says only what the screen shows, and alternates `glowX` sides with its neighbours. A new shot needs a test in `MarketingScreenshotTests` attaching `marketing-<id>`, and seed data when the screen needs it.
- **Recapture** whenever the range touches app UI (`Baros/Features`, `Baros/Shared`, `Baros/App`). A range with none keeps the current images.

**Done when** `listing.json` on a branch from the base names every headline feature, and you know whether to recapture.

## 2. Capture and generate

Follow the simulator rules in `AGENTS.md`, using the iPhone 17 Pro pool device (its 1206×2622 captures are the size baros.fit serves). Release it when the run ends.

```sh
scripts/capture-screens.sh <iPhone 17 Pro UUID> <scratch>/raw
pnpm -C SupportSite install
pnpm -C SupportSite listing-assets <scratch>/raw <scratch>/app-store
```

Inspect every framed image at full size and at thumbnail size: the screen is in the state its headline claims (a rest timer running, a superset round checked), the data looks like a real lifter's, nothing clips under the frame, and no debug-only UI shows. Fix a bad shot in its test or the seeder and rerun; never edit an image by hand.

**Done when** every shot passes that inspection and `pnpm -C SupportSite test` passes.

## 3. ⛔ Approval

Show Kevin every framed image inline in order, the baros.fit images, and the text changes. `node scripts/asc.mjs listing <live version>` prints the App Store side next to `listing.json`. Repeat steps 1–2 until he approves.

## 4. Listing PR

Open the PR with the `file-pr` skill: `listing.json`, the site images and hashes, and any new tests or seed data. Its description says to merge when `<version>` is live, and carries the baros.fit before/after images per `AGENTS.md`. The App Store images go to App Store Connect, never into the repo.

**Done when** the PR is open with green checks. Step 6 uploads the listing from this branch, and step 9 merges it with the release so baros.fit changes the moment the App Store does.

## Between releases

Promotional text is the one field a live version accepts. To change it, edit `listing.json` on a PR and run `node scripts/asc.mjs listing <live version> --apply`, which leaves everything else alone. Every other field waits for the next version.
