# Issue #170 implementation and verification brief

Implement GitHub issue
[#170](https://github.com/Tatooles/baros/issues/170) as a bounded shared-color
and surface-role pass. The canonical identity contract is
[`docs/design/visual-identity.md`](../../visual-identity.md).

## Outcome

Replace the current red brand accent and ambiguous gray layering with the
approved balanced cobalt identity. Preserve app behavior and interaction while
making surface depth intentional in light and dark appearances.

## In scope

1. Refine the existing shared `AppTheme` roles so views request semantic
   canvas, grouped, focus, field, border, accent, status, and text roles rather
   than choosing screen-specific colors.
2. Implement the cataloged accent roles: canonical cobalt for fills and
   `#4D94FF` only as the accessible dark foreground for small inline cobalt
   content.
3. Apply the approved light and dark canvas, grouped, focus, field, border, and
   glass-adjacent hierarchy through shared roles and existing shared
   components.
4. Replace only brand-accent red usage. Preserve destructive/error red and
   success green.
5. Update the app Accent Color asset to the approved cobalt role.
6. Remove the redundant outer `SurfaceCard` from Active Workout's Workout Notes
   while keeping its heading, editor, focus, draft, persistence, and
   reference-note behavior.
7. Verify that the app target and relevant configurations continue to use the
   production `Baros/AppIcon.icon` package established by #169.
8. Visually review every surface named by the live issue acceptance criteria.

Existing shared component APIs should remain stable unless one small semantic
style seam is necessary to distinguish an ordinary grouped surface from a
selective focus surface. Do not build a comprehensive component system for this
issue.

## Explicitly out of scope

- Exercise Notes progressive disclosure or an Add exercise note action.
- Broader exercise-card or set-grid redesign.
- Combining or restructuring Weight and Reps.
- Workout/Home lifecycle work from #174.
- Bottom navigation work from #47.
- Live Activities or Dynamic Island work from #28.
- Rest timers.
- A new typography scale, typeface, or component-system redesign.
- New product behavior discovered during visual or accessibility review unless
  #170 directly causes the regression.

Issue #179 owns the excluded Exercise Notes and broader Active Workout density
work. The refined grid concept in this directory remains directional evidence,
not a pixel-perfect #170 specification.

## Implementation sequence

1. Fetch and rebase the branch onto the then-current `origin/main` before app
   implementation begins.
2. Audit `AppTheme`, the Accent Color asset, shared surfaces, and direct color
   literals. Classify each use as brand accent, semantic status, text, surface,
   border, or system-owned material before changing it.
3. Establish the semantic token values and update shared consumers first.
4. Migrate remaining in-scope brand-accent uses without per-screen hex values.
5. Flatten only the Active Workout Notes outer containment. Retain the existing
   completed-workout History editor containment until a holistic History
   surface update.
6. Regenerate the Xcode project and confirm any changed files or tests are
   discovered.
7. Run focused verification, the full relevant suite, builds, and the visual
   matrix below.

This is primarily a coloring and shared-token pass. Refactoring is justified
only where the current token name or shared surface prevents the approved role
from being expressed consistently.

## Behavior that must remain unchanged

- Starting, editing, completing, and discarding an Active Workout.
- Weight and Reps validation, focus order, keyboard movement, completion, and
  persistence.
- Exercise Notes editing, visibility, focus, draft commit, and persistence.
- Workout Notes editing, focus, draft commit, reference notes, and persistence.
- Navigation, sheets, menus, swipe actions, loading, empty, recovery, and auth
  behavior.
- Current Owner and synchronization behavior.
- Destructive/error and success semantics.

## Visual review matrix

Capture standard light and dark appearances for:

- Start Workout;
- Active Workout;
- History workouts and exercises;
- Exercises;
- Profile and Settings;
- authentication and signed-out recovery;
- onboarding;
- representative empty and loading states.

Across that set, include representative focused input, selection, active
progress, completion, destructive/error, and success states. Dark appearance is
the primary design review, but light appearance must remain coherent rather
than functioning as a fallback.

## Accessibility checks

- Measure ordinary custom foreground/background pairs at `4.5:1` or higher
  against the actual composited background.
- Use `3:1` only for applicable large/bold text exceptions or appropriate
  non-text state boundaries; aim toward `7:1` for small custom text.
- Test the standard tokens in light and dark for #170.
- Defer app-wide Increased Contrast and combined Reduce Transparency coverage,
  including dedicated custom-color variants, to the accessibility audit in
  #140.
- Confirm selected, completed, destructive/error, and success states remain
  understandable in grayscale or with Differentiate Without Color.
- Perform one representative enlarged Dynamic Type pass.
- Check appearance transitions for bright flashes or unreadable intermediate
  states.

Accessibility review validates the color work. It does not authorize unrelated
feature or layout changes; record those as follow-up work unless #170 created
the problem.

## Engineering verification

- Run `xcodegen generate` and inspect the resulting project diff.
- Run focused tests for any behavior-adjacent seam changed by the Workout Notes
  wrapper removal.
- Run the full relevant test suite once the implementation is stable.
- Build and launch the app in standard light and dark appearances.
- Do not introduce a screenshot-testing framework solely for this issue.
- Perform a physical-device check of the installed production icon and one
  representative light and dark app surface.

## Completion gate

Issue #170 is complete when the live acceptance criteria are satisfied, the
canonical roles are used consistently, semantic status colors are preserved,
the review matrix has evidence, the app builds and tests pass, and no excluded
interaction or component redesign has entered the change set.
