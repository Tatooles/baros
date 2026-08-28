# Baros 1.2 App Store assets

This directory is the repository source of truth for the Baros 1.2 iPhone
App Store screenshot set.

## Deliverables

All final screenshots are PNG files at 1320 x 2868 pixels with no alpha
channel. Upload them to the 6.9-inch iPhone display slot in filename order.

| File | Product state | Accessible description |
| --- | --- | --- |
| `01-log-every-set.png` | Active workout | Baros active workout showing two completed Bench Press sets and two completed Barbell Row sets. |
| `02-repeat-workouts.png` | Reuse a past workout | Review Workout screen for Push Day with Bench Press and Barbell Row, ready to start. |
| `03-training-history.png` | Workout history | Baros workout history showing a recent Push Day and an earlier Upper Body Strength workout. |
| `04-every-detail-preserved.png` | Completed workout detail | Completed Push Day with duration, notes, exercises, weights, reps, and completion state. |
| `05-exercise-library.png` | Exercise library | Baros exercise library listing built-in exercises with equipment and muscle group details. |
| `06-private-by-default.png` | Local privacy and optional sync | Baros Settings showing local-only sync status, workout export, privacy policy, support, and local-data controls. |

## Source and generation

The `source` directory contains uncropped 1320 x 2868 screenshots captured
from the current Baros 1.2 app on an iPhone 17 Pro Max simulator. Captures use
dark appearance and a normalized simulator status state; system presentations
may suppress individual status-bar items. Release-build captures are used
wherever debug-only UI would otherwise be visible.

The generated artwork uses the approved marketing export at
`SupportSite/public/assets/baros-app-icon.png`, derived from the canonical
`Baros/AppIcon.icon` production source, plus the approved cobalt, blue-black,
charcoal, and warm-silver identity tokens.

Regenerate the final set from the repository root on macOS. Generation is
intentionally macOS-only so the marketing headlines use the same system
typography as the iOS app:

```sh
pnpm -C SupportSite run assets:app-store
```

Then run the asset contract and support-site checks:

```sh
pnpm -C SupportSite test
```

Before upload, inspect every file at full size and as a store-thumbnail-sized
preview. Confirm the headline remains readable, the phone crop preserves the
primary UI state, colors match the production identity, and no stale or
debug-only UI is visible.
