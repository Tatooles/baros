# Baros Icon Composer handoff

This package converts the approved, centered issue #169 concept into flat,
maintainable vector layers for an Icon Composer design pass. The source PNG
remains the visual authority; the generated Default, Dark, and Mono concept
sheets are color references only and must not be used for geometry.

## Import package

Both assets use the same `1024 x 1024` canvas and must remain at their default
position and scale when imported:

1. `Assets/01-mark.svg` — warm-silver B, bar shaft, and endcaps.
2. `Assets/02-plates.svg` — cobalt plates, placed above the mark layer.

Set the background on the Icon Composer canvas. Do not import the rounded
enclosure, mask, shadow, or raster background from the checkpoint PNG. Icon
Composer owns those effects and the platform-specific enclosure.

`baros-icon-reference.svg` is a composite visual check. It is not an import
layer and should not be added to the Icon Composer document.

## Geometry

- Canvas center: `(512, 512)`.
- Full foreground bounds: `x = 306...712`, `y = 143...877`.
- Foreground bounding-box center: `(509, 510)`.
- The three-point horizontal offset is intentional. The B bowls carry more
  visual mass on the right, so the geometric bounds sit slightly left of the
  canvas center to produce an optically centered mark.
- The mark-to-bowl gap is `16` points at the closest vertical boundary.
- Keep the B/bar geometry identical across Default, Dark, and Mono.

## Production palette

These values are the locked v1 brand baseline. Tune material controls in Icon
Composer before changing a base color; any later color change should update
this table and the app/site tokens together.

| Role | Default | Dark | Mono |
| --- | --- | --- | --- |
| Background top | `#0D1B2A` | `#0A0C10` | system appearance |
| Background bottom | `#08121D` | `#050608` | system appearance |
| Primary mark | `#F3EBE7` | `#F7F7F5` | `#FFFFFF` |
| Plates | `#1C66C7` | `#1768E5` | `#8A8D95` |

### Cross-surface roles

- **Brand cobalt (`#1C66C7`)** — Default icon plates, primary app accent,
  prominent app controls, marketing-site links, and primary calls to action.
- **Dark cobalt (`#1768E5`)** — Dark-icon plate override and dark-surface
  accent where the baseline cobalt loses perceived contrast.
- **Charcoal (`#0D1B2A` and `#08121D`)** — Icon backdrop and branded app/site
  hero or feature surfaces. It does not replace semantic system backgrounds.
- **Warm silver (`#F3EBE7`)** — Default icon mark and display content on
  branded charcoal surfaces. It does not replace semantic system text colors.
- **Neutral white and gray (`#FFFFFF` and `#8A8D95`)** — Mono hierarchy used
  by Icon Composer to derive clear and tinted appearances.

## Icon Composer setup

1. Create a new icon document with shared square platforms and watchOS enabled.
2. Set the canvas background to the Default gradient above.
3. Import `01-mark.svg`, then `02-plates.svg`, without translation or scaling.
4. Keep the plate layer above the mark layer.
5. Configure the Default, Dark, and Mono color overrides from the table.
6. Keep glass, refraction, translucency, highlights, and shadows restrained.
7. Preview Default, Dark, Clear Light, Clear Dark, Tinted Light, and Tinted
   Dark at Home Screen, Settings, and notification sizes.
8. Confirm the B reads before the barbell at every preview size.
9. Save the resulting `.icon` document into `Baros/` only after the design is
   approved; do not replace the shipping icon from this handoff package alone.

## Production checks

- The B/bar gap remains tight and does not widen under glass refraction.
- Plates remain secondary and do not overpower the letter at small sizes.
- No source layer contains a baked rounded-square mask or background.
- Clear and tinted appearances preserve recognizable B/bar geometry.
- Circular watchOS previews retain safe space around the endcaps and plates.

## Pre-Composer validation

The flat composite was rendered directly from the two import SVGs and checked
at `120 x 120` and `60 x 60` pixels:

- normalized vector bounds match the approved PNG within one point;
- the vector vertical foreground center matches the PNG after normalization;
- the vector horizontal foreground center is approximately four points left
  of the PNG, within the intended optical offset;
- at both preview sizes the B reads before the plate stack and the 16-point
  mark-to-bowl gap remains visible.

| 120 px | 60 px |
| --- | --- |
| ![120 px flat vector preview](previews/baros-icon-reference-120.png) | ![60 px flat vector preview](previews/baros-icon-reference-60.png) |

These previews validate only the flat vector handoff. Home Screen, Settings,
notification, circular watchOS, Clear, and Tinted checks remain required after
the layers are assembled in Icon Composer.
