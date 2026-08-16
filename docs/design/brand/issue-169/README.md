# Baros production icon handoff

This document records the approved outcome of GitHub issue
[#169](https://github.com/Tatooles/baros/issues/169). The production source of
truth is [`Baros/AppIcon.icon`](../../../../Baros/AppIcon.icon); do not copy the
SVG layers into a second handoff package.

## Mark

- An uppercase Latin `B` reads first, with a slim vertical barbell integrated
  as its left stem.
- Two thin, moderately extended plates sit at each end of the stem.
- The tight stem-to-bowl gap keeps the mark cohesive and the plates secondary.
- The foreground is optically centered: its `1024 x 1024` canvas bounds are
  `x = 306...712`, `y = 143...877`, with a bounding-box center of `(509, 510)`.
  The slight left offset compensates for the visual mass of the bowls.
- Default, Dark, and Mono appearances use identical geometry.

## Production palette

These values are the locked v1 baseline. App-wide adoption belongs to
[#170](https://github.com/Tatooles/baros/issues/170).

| Role | Default | Dark | Mono |
| --- | --- | --- | --- |
| Background | `#09121D` | `#080A0D` | system appearance |
| Primary mark | `#F3EBE7` | `#F7F7F5` | `#FFFFFF` |
| Plates | `#1C66C7` | `#1768E5` | `#8A8D95` |

### Cross-surface roles

- **Brand cobalt (`#1C66C7`)** — Default icon plates and the baseline app/site
  brand accent.
- **Dark cobalt (`#1768E5`)** — Dark-icon plates and dark-surface accent where
  the baseline cobalt loses perceived contrast.
- **Blue-black (`#09121D`)** — Default icon background and selective branded
  app/site surfaces; it does not replace semantic system backgrounds.
- **Near-black (`#080A0D`)** — Dark icon background.
- **Warm silver (`#F3EBE7`)** — Default icon mark and display content on
  branded blue-black surfaces; it does not replace semantic system text.
- **White and gray (`#FFFFFF`, `#8A8D95`)** — Mono hierarchy used by Icon
  Composer for tinted appearances.

Brand colors do not replace semantic status colors: destructive/error remains
red and success remains green.

## Production package

The Icon Composer document contains two transparent, full-canvas SVG layers:

1. `01-mark.svg` — B, bar shaft, and endcaps.
2. `02-plates.svg` — plates, rendered above the mark.

The canvas uses solid appearance-specific backgrounds. Icon Composer owns the
platform mask, material, lighting, and enclosure; the SVGs contain no baked
background or rounded-square mask. Shared square platforms and watchOS circles
are enabled.

## Validation

- The vector geometry and appearance values were validated directly from the
  saved `.icon` package.
- Xcode compiled the package into the app asset catalog in an arm64 Simulator
  build and a signed Debug device build.
- The compiled `120 x 120` icon preserved the B-first reading and optical
  centering.
- The signed Debug build was installed and launched on an iPhone 17, where the
  final icon was approved at real Home Screen size.
- Superseded concept layers are not present in the production package.

Promote these stable decisions into `docs/design/visual-identity.md` as part of
#170 rather than expanding this issue-specific handoff into a component design
system.
