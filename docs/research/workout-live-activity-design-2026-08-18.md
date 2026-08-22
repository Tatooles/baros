# Workout Live Activity design

Decision date: 2026-08-18

## Decision

Baros adds one automatically managed **Workout Live Activity** for the currently visible **Active Workout**. It is a disposable, local projection for workout continuity: it shows the committed workout name, running elapsed time, and completed/total set progress, and its only action is **Return to Workout**.

The Workout Live Activity is not a second workout engine. ActivityKit failure, user dismissal, or system expiration never blocks or changes the Active Workout.

This is a bounded 1.2 feature. It does not add a rest timer, current-exercise tracking, state-changing controls, alerts, remote Live Activity updates, a Baros setting, or bespoke Apple Watch behavior.

## User promise

During a workout, someone can glance at the Lock Screen or Dynamic Island to answer three questions without reopening Baros:

1. Which workout is active?
2. How long has it been running?
3. How many sets are complete?

Selecting any Workout Live Activity presentation returns to the matching Active Workout.

## Authoritative content

The presentation contains only state Baros already owns authoritatively:

| Content | Source and behavior |
| --- | --- |
| Workout name | The committed Active Workout title. A new blank workout uses **Workout**; a workout created from history uses its copied title. Draft typing does not update the activity until title commit. |
| Elapsed time | Derived from the Active Workout's start date. Use a system-driven running timer with seconds rather than publishing a new activity update every second. |
| Set progress | Completed visible sets divided by all visible sets, matching the Active Workout header. Reversing a completed set moves the count backward quietly. |

Completing every set fills the progress ring but does not finish the workout. Baros has no authoritative current-exercise or paused-workout state, so neither appears.

Workout names, elapsed time, and set counts are not treated as sensitive workout content for this feature. Baros does not add its own redaction layer; system Lock Screen visibility settings still apply. Exercise names, notes, weight, repetitions, and other workout details remain excluded.

## Lock Screen presentation

Use the accepted **Split Metrics** layout:

- Top row: cobalt-backed Baros mark and one-line workout name.
- Left column: visually primary running elapsed time with an **ELAPSED TIME** caption.
- Right column: circular cobalt progress dial containing the completed/total value and **SETS** caption.
- Whole surface: one **Return to Workout** action, with no visible button or chevron.

State adaptations preserve the two-column geometry:

- With no sets, the right metric slot says **No sets yet** instead of collapsing the layout.
- At full progress, the ring is fully cobalt and continues to show the completed/total value; it does not show a checkmark or completed-workout state.
- Long workout names stay on one line and truncate visually while remaining complete in the accessibility value.
- At larger text sizes, remove secondary captions before changing the columns or shrinking the primary values.

### Signature treatment

The Lock Screen card uses Baros's blue-black, cobalt, and warm-silver visual language:

- A strong continuous cobalt inset border and controlled surrounding bloom create the recognizable silhouette.
- A broad, softly feathered horizontal-diagonal cobalt slash crosses the otherwise calm central negative space.
- Do not add a separate interior radial bloom, pulse, animated glow, glass effect, or state-dependent background.
- Keep the treatment static when set progress changes, including reversals and completion.

The bright in-bounds edge is the guaranteed signature. Any bloom outside the system-owned Live Activity bounds is best-effort because the system may clip it. Always-On keeps the same composition under system-reduced luminance.

Use the existing Baros semantic brand roles rather than introducing a second palette: `brandAccentFill`, `brandAccentForeground`, `brandAccentGlow`, the blue-black dark surfaces, and warm-silver foregrounds. Final implementation must verify contrast in normal and reduced-luminance states.

## Dynamic Island presentation

Dynamic Island keeps the system-owned black background. The Lock Screen's literal background and slash do not carry into the Island.

- Use a cobalt `keylineTint`—the thin colored outline around the Island—plus luminous cobalt brand and progress elements.
- Compact presentation shows the cobalt-backed Baros mark and running timer.
- Minimal presentation shows the same cobalt-backed Baros mark; the timer disappears rather than changing the brand treatment.
- Expanded presentation preserves the workout-name, elapsed-time, and circular set-progress hierarchy. Secondary captions may disappear when space is tight.

Do not attempt to replace the Island's black surface with a gradient. Apple permits custom Lock Screen backgrounds but keeps Dynamic Island presentations on an opaque black background; `keylineTint` is the native perimeter treatment. [Apple Human Interface Guidelines: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities) and [Apple: Dynamic Island](https://developer.apple.com/documentation/widgetkit/dynamicisland)

## Lifecycle

The Active Workout remains the source of truth throughout this lifecycle:

| Event | Workout Live Activity behavior | Active Workout behavior |
| --- | --- | --- |
| A new or copied Active Workout saves successfully | Request one activity automatically | Continue normally even if the request fails |
| Title commit or set-progress change | Publish a local content update | Persist through the existing workout path |
| App backgrounds or goes offline | Keep running from its start date | Remain locally editable |
| Temporary same-owner revalidation | Keep visible | Remain visible and editable |
| App relaunches | Reconcile by Active Workout identifier | Present the Active Workout with Home underneath per #47/#174 |
| User dismisses the activity | Suppress recreation for the rest of that workout | Keep active |
| System expires the activity | Do not recreate it for that workout | Keep active |
| Workout finishes or is discarded | End and remove immediately | Follow the existing terminal path |
| Confirmed sign-out or Current Owner change makes the workout invisible | End and remove immediately | Leave terminal disposition to #188 |

Baros accepts ActivityKit's system lifetime instead of inventing a separate stale-workout deadline. A failure to request or update the Workout Live Activity never rolls back a workout mutation. A bounded retry may occur after a meaningful recovery event, but never through polling and never after dismissal or expiration.

## Reconciliation and identity

Use the Active Workout's stable identifier as the Workout Live Activity identity and deep-link payload.

On launch or foreground reconciliation:

1. Find the Active Workout visible to the Current Owner.
2. Keep at most one matching Workout Live Activity.
3. End duplicate, stale, or owner-invisible activities.
4. Reconnect to a valid matching activity instead of creating another.
5. Respect dismissal and expiration suppression for that workout.

This feature enforces privacy at the presentation boundary: a Workout Live Activity must disappear as soon as its Active Workout is no longer visible to the Current Owner. Issue #188 still owns the device-wide single-Active-Workout invariant and the underlying workout disposition across sign-out and account change.

## Re-entry navigation

The activity URL identifies a candidate Active Workout, but the app must validate it against the currently visible Active Workout before presentation.

- Warm launch: present the Active Workout above the currently selected tab.
- Cold launch: present the Active Workout with Home underneath.
- Invalid, stale, or owner-invisible identifier: do not present a workout; fall back to Home.

This preserves the accepted navigation contract in [Active Workout navigation design](./active-workout-navigation-design-2026-08-17.md) and [ADR-0002](../adr/0002-present-active-workout-as-a-minimizable-session.md).

## Accessibility

- Expose the whole activity as one **Return to Workout** action.
- Include the full workout name, elapsed time, and completed/total set progress in its accessibility value.
- Do not announce periodic elapsed-time updates or quiet set-progress changes automatically.
- Treat the glow, slash, ring track, and other styling as decorative.
- Preserve the information hierarchy under larger text rather than shrinking primary values below legible sizes.

## Delivery boundaries

The 1.2 implementation includes the ActivityKit/WidgetKit target and capability foundation, local lifecycle coordination, update/reconciliation logic, validated re-entry routing, all Lock Screen and Dynamic Island families, accessibility, reduced-luminance behavior, and deterministic tests around lifecycle decisions.

Deferred work includes:

- Current-exercise modeling or manual selection.
- Rest timers and their controls.
- Finish, discard, pause, resume, advance, or set-completion controls outside Baros.
- Alerts, notification sounds, and haptics.
- Activity push tokens, APNs, or server-driven updates.
- A Baros Live Activity setting; use the system setting.
- Custom Apple Watch or other bespoke system-surface experiences.
- Reviving an activity after user dismissal or system expiration.
- Deciding how an owner-invisible Active Workout itself is finished or discarded; #188 owns that policy.

## Rejected alternatives

- **Current exercise:** Baros does not model an authoritative current exercise, so displaying one would be guesswork.
- **Rest timer:** It is a separate product capability and is not required for workout continuity.
- **State-changing controls:** Re-entry keeps the first version simple and prevents the system projection from becoming a second workout editor.
- **Remote updates:** Active Workouts are local-first and intentionally do not sync while active; local ActivityKit updates are sufficient.
- **Post-workout summary:** The activity ends with the workout instead of changing into a second completion surface.
- **Custom privacy redaction:** The accepted fields are not sensitive, and system Lock Screen controls already govern visibility.
- **Literal Lock Screen styling in Dynamic Island:** The Island's black surface is system-owned; cobalt keyline and foreground elements provide the related native treatment.
