# Baros visual identity

This document is the canonical cross-surface source of truth for the Baros
visual identity established by GitHub issues
[#169](https://github.com/Tatooles/baros/issues/169) and
[#170](https://github.com/Tatooles/baros/issues/170). It defines identity
roles and usage boundaries, not a comprehensive component design system.

## Character

Baros should feel strong, controlled, and precise. Its visual hierarchy uses
negative space and restrained surfaces so cobalt can communicate interaction
without making every element compete for attention.

The palette is intentionally small:

- deep cobalt identifies the brand and active interaction;
- black, charcoal, and quiet neutrals establish surface depth;
- warm silver belongs to explicit branded surfaces;
- system semantic colors retain their established meanings.

Gray is not inherently undesirable. A neutral is valid when it has one clear
job, such as identifying an editable field. The failure mode to avoid is a
stack of similar gray containers whose depth and purpose are ambiguous.

## Color catalog

The catalog separates protected brand anchors from contextual application
tokens. Views consume the semantic application roles; they do not select a raw
hex value directly.

### Protected brand anchors

| Token | Default or light | Dark | Usage |
| --- | --- | --- | --- |
| `brandCobalt` | `#1C66C7` | `#1768E5` | Canonical cobalt family, icon plates, and solid accent fill |
| `brandBlueBlack` | `#09121D` | `#080A0D` | Icon backgrounds and selective branded surfaces, not the general app canvas |
| `brandForeground` | `#F3EBE7` | `#F7F7F5` | Icon mark and selected display content on branded charcoal or blue-black |
| `brandMonoForeground` | `#FFFFFF` | `#FFFFFF` | Icon Composer Mono primary hierarchy |
| `brandMonoSecondary` | `#8A8D95` | `#8A8D95` | Icon Composer Mono secondary hierarchy |

### Application accent roles

| Token | Light | Dark | Usage |
| --- | --- | --- | --- |
| `brandAccentFill` | `#1C66C7` | `#1768E5` | Solid primary controls, progress fills, completion marks, and sufficiently large state symbols |
| `brandAccentForeground` | `#1C66C7` | `#2478F2` | Small inline action text and symbols on light or dark app surfaces |
| `onBrandAccent` | `#FFFFFF` | `#FFFFFF` | Text and symbols on `brandAccentFill` |
| `brandAccentMuted` | `#1C66C7` at 12% | `#1768E5` at 16% | Soft selected backgrounds, compact badges, and secondary brand actions |
| `brandFocus` | `#1C66C7` | `#1768E5` | Focus rings and non-text focus indicators; opacity may be reduced when the resulting boundary still reaches the applicable contrast bar |
| `brandAccentGradient` | `#1C66C7` to `#1768E5` | `#1C66C7` to `#1768E5` | Existing high-emphasis branded moments only; white content remains readable across both endpoints |
| `brandAccentGlow` | `#1C66C7` at 24% | `#1768E5` at 28% | Restrained decoration behind an existing high-emphasis branded control, never a structure or status signal |

`#2478F2` is a dark foreground/accessibility resolution of the cobalt family,
not another primary brand color. It is not used in the production icon,
marketing palette, or solid control fills. This distinction follows the
evidence captured in the
[#170 color-variant research](brand/issue-170/color-variant-research.md).

### Application surfaces and structure

| Token | Light | Dark | Usage |
| --- | --- | --- | --- |
| `appCanvas` | `#F7F6F3` | `#000000` | App-owned full-screen content background |
| `groupedSurface` | `#FFFFFF` or the equivalent adaptive system grouped surface | `secondarySystemBackground` | Ordinary bounded groups |
| `focusSurfaceTop` | `#FFFFFF` | `#0A0C10` | Top of a selective focused or hero surface |
| `focusSurfaceBottom` | `#FAFAFA` | `#050608` | Bottom of a selective focused or hero surface |
| `fieldSurface` | `#ECECF0` | `#2C2C2E` | Actual editable regions |
| `subtleBorder` | `#09121D` at 9% | `#FFFFFF` at 11% | Necessary card borders and dividers only |
| `platformGlass` | Native material | Native material | System-owned glass and material-adjacent chrome, without navy or cobalt tinting |

### System semantic roles

| Token | Platform mapping | Usage |
| --- | --- | --- |
| `textPrimary` | `label` | Ordinary primary text and symbols |
| `textSecondary` | `secondaryLabel` | Supporting content |
| `textTertiary` | `tertiaryLabel` | De-emphasized metadata that still meets its applicable contrast bar |
| `destructive` | `systemRed` | Destructive actions and error meaning |
| `success` | `systemGreen` | Successful state |
| `systemSeparator` | `separator` | System-owned list and presentation boundaries |

System semantic roles intentionally have no fixed cross-appearance hex value.
The platform owns their appearance and accessibility resolution. Brand colors
must not override status meaning.

## App surface hierarchy

Light and dark appearances express the same semantic depth without being
literal inversions.

| Semantic role | Light appearance | Dark appearance | Boundary |
| --- | --- | --- | --- |
| Root canvas | Warm neutral `#F7F6F3` | True black `#000000` | App-owned full-screen content background |
| Ordinary grouped surface | Elevated white `#FFFFFF` or an equivalent system semantic surface | Neutral system near-black, typically `secondarySystemBackground` | Ordinary bounded groups that need separation from the canvas |
| Focus surface | Elevated white with restrained neutral separation | Branded charcoal `#0A0C10` to `#050608` | Selective hero or focused content, such as the active exercise boundary; never the default for every card |
| Editable field | Cool neutral `#ECECF0` | Neutral gray `#2C2C2E` | The actual editable region, not its surrounding section |
| Border or divider | Blue-black at about 9% opacity | White at about 11% opacity | Only when spacing and surface contrast do not establish the boundary |
| Glass-adjacent chrome | Native platform material | Native platform material | Preserve system material behavior; do not tint glass navy or cobalt |

App-owned custom colors need light, dark, and increased-contrast variants when
the standard pair does not remain sufficiently distinct. System-owned sheets,
menus, popovers, and navigation presentations remain adaptive rather than
being forced onto the branded canvas.

## Cobalt roles

Use cobalt for:

- the primary call to action;
- app tint and links;
- selected navigation or segmented state;
- keyboard focus and input focus treatment;
- active progress and completion;
- compact badges that communicate active state;
- a restrained muted fill behind a secondary brand action.

A solid cobalt fill is reserved for the highest-emphasis action or state in a
group. Secondary actions, such as Add Exercise, use a soft cobalt fill with
cobalt content. A cobalt gradient may appear in a genuinely prominent branded
moment, but it is not the default treatment for rows, cards, fields, or icons.
Small inline cobalt content uses `brandAccentForeground`; solid controls and
filled state indicators use `brandAccentFill` with `onBrandAccent` content.

Do not use cobalt for:

- the app canvas or ordinary grouped surfaces;
- resting editable fields;
- body text or general metadata;
- disabled state;
- destructive, error, warning, or success meaning;
- decorative borders around every container.

## Warm-silver boundary

Warm silver is not a replacement for semantic system text. Use it for the icon
mark and selective display content on explicit charcoal or blue-black branded
surfaces. Ordinary screen titles, body copy, metadata, placeholders, input
text, and system controls continue to use semantic label colors. Content on a
solid cobalt control uses white.

## Containment rule

Use one visible containment boundary per conceptual unit. A nested surface is
justified only when the child has a distinct interaction, focus, scrolling,
selection, or system-presentation role.

An editable field inside an exercise group is justified because the field is
the interaction target. An additional decorative card around a heading and
that field is not. Prefer spacing, alignment, and a restrained divider over
another rounded rectangle.

For issue #170, Workout Notes is a heading plus one neutral editor directly on
the canvas; it does not have an additional outer card. Exercise Notes behavior,
its progressive disclosure, set-grid treatment, and the Weight/Reps interaction
model belong to issue #179 and are not changed by this rule in #170.

## Typography

Baros continues to use the system typeface, Dynamic Type, and existing semantic
SwiftUI text styles. Issue #170 does not introduce a new type scale, display
font, or comprehensive typography system. Weight, size, tracking, and casing
may continue to establish the existing information hierarchy, but color must
not be the only differentiator.

## Icon rules

[`Baros/AppIcon.icon`](../../Baros/AppIcon.icon) is the production source of
truth. Do not duplicate its SVG layers or rebuild the icon in an asset catalog.
Icon Composer owns the mask, enclosure, material, lighting, and platform
appearance.

Default, Dark, and Mono use identical, optically centered geometry. The
foreground bounds and optical offset remain as documented in the
[#169 production handoff](brand/issue-169/README.md). App-wide color changes
must not alter the icon package or substitute a generated appearance sheet.

## Accessibility and review

- Check custom foreground/background pairs against their actual composited
  background, including material surfaces.
- Ordinary text, icons, and controls must reach at least `4.5:1` contrast.
- Use the `3:1` exception only where Apple's documented large or bold text
  guidance, or an appropriate non-text state boundary, applies.
- Strive for `7:1` contrast for small custom text where practical.
- Do not rely on cobalt, red, or green as the sole indicator of selection,
  completion, failure, or success. Pair color with text, shape, placement, or a
  symbol.
- Verify standard and increased contrast in both appearances.
- Verify Reduce Transparency separately and together with Increase Contrast.
- Use a grayscale or Differentiate Without Color pass to find color-only state.
- Perform a representative enlarged Dynamic Type pass for clipping and lost
  hierarchy.

## Cross-surface boundary

The icon, app, website, and marketing share cobalt, blue-black, charcoal, and
warm silver as identity anchors. They do not share one universal surface
implementation.

- The iOS app prioritizes semantic system behavior, accessibility settings,
  native material, and status-color meaning.
- The website may use branded charcoal or blue-black more broadly for heroes
  and feature surfaces, while preserving the same cobalt and warm-silver roles.
- Marketing may compose the palette more freely, but must preserve the icon
  geometry and must not redefine semantic app states.
- Mono is an Icon Composer appearance role, not an alternate application theme.
