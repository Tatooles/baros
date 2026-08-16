# Brand coherence and contextual cobalt variants

## Question

Does using a brighter cobalt for small foreground content in Dark Mode weaken
brand consistency, or is it a normal design-system technique?

## Conclusion

Using a contextual variant is the established approach. Mature design systems
preserve identity through a recognizable color family, stable semantic roles,
and consistent usage rules; they do not require one literal hex value to serve
every light, dark, fill, foreground, interaction, and accessibility context.

The useful distinction is:

- a **brand anchor** defines the recognizable family and protected brand assets;
- **UI semantic variants** are related values selected for a specific role,
  appearance, state, or contrast requirement.

Changing the protected logo or icon color arbitrarily would be brand drift.
Mapping a stable UI role to a nearby cobalt tone when its context requires more
contrast is controlled adaptation.

## Official guidance

### Apple

Apple's current Dark Mode guidance says dark interfaces use brighter foreground
colors and that custom colors should provide bright and dim variants rather than
remain hard-coded. Apple also supports high-contrast variants in asset catalogs
and requires testing across appearance and accessibility settings. In other
words, the platform explicitly treats one named custom color as a semantic
object that can resolve to different values by context.

Sources: [Human Interface Guidelines: Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode),
[Supporting Dark Mode in your interface](https://developer.apple.com/documentation/uikit/supporting-dark-mode-in-your-interface)

### GitHub Primer

Primer separates raw base colors from functional and component tokens. Raw
colors should not be used directly; functional tokens represent roles such as
foreground, background, border, and accent, and their values change across
light, dark, high-contrast, and color-vision themes. The same token therefore
preserves meaning and consistency while its rendered value adapts.

Sources: [Primer: Color usage](https://primer.style/product/getting-started/foundations/color-usage/),
[Primer Primitives](https://github.com/primer/primitives)

### Material Design 3

Material treats a brand or logo color as a source from which related tonal
palettes and semantic color roles are derived. Its official theming guidance
notes that a supplied logo color may not be sufficiently contrasting when used
directly in UI, then recommends related colors that remain both cohesive and
accessible. Primary, surface, and semantic roles—not a universal swatch—are
what components consume.

Sources: [Material 3 accessible brand theming](https://developer.android.com/codelabs/m3-design-theming),
[Material Design 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)

### IBM Carbon

Carbon is an especially direct comparison: IBM retains its core blue family as
the primary action identity across products while using role-based tokens whose
values change between light and dark themes. Carbon states that token names and
roles remain the same across themes while the assigned values change, producing
unified, recognizable consistency.

Sources: [Carbon: Color](https://carbondesignsystem.com/elements/color/overview/),
[Carbon: Themes](https://carbondesignsystem.com/elements/themes/overview/)

## Baros implication

Keep `#1768E5` as the canonical dark cobalt anchor and solid accent fill. Keep
white content on that fill. Define `#4D94FF` as a narrowly scoped dark
foreground/accessibility variant for small inline cobalt text and symbols on
dark app surfaces.

This is a tonal adjustment within the same cobalt family, not a second primary:
the two colors have nearly identical HSL hue angles (`216.4°` and `216.1°`).
The adjustment changes lightness enough to solve the actual foreground problem:

| Pair | Contrast |
| --- | ---: |
| `#1768E5` on `#000000` | `4.15:1` |
| `#1768E5` on `#0A0C10` | `3.87:1` |
| `#4D94FF` on `#000000` | `7.00:1` |
| `#4D94FF` on `#0A0C10` | `6.52:1` |
| `#4D94FF` on `#1C1C1E` | `5.67:1` |
| `#4D94FF` over the 16% muted cobalt badge on `#1C1C1E` | `4.93:1` |
| `#4D94FF` on `#2C2C2E` | `4.64:1` |
| `#FFFFFF` on `#1768E5` | `5.06:1` |

Recommended semantic contract:

- `brandAccentFill`: `#1C66C7` in light appearance and `#1768E5` in dark;
- `brandAccentForeground`: `#1C66C7` in light appearance and `#4D94FF` in dark;
- production icon and protected brand geometry/colors remain unchanged;
- `#4D94FF` is documented as a contextual UI value, not marketed as another
  primary brand color and not substituted into solid cobalt controls.

This keeps Baros visually homogeneous while avoiding the less professional
outcome of forcing one hex into a role where it fails the accepted contrast bar.
