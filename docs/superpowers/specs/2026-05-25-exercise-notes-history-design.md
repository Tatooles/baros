# Exercise Notes In History Design

## Context

Exercise notes entered during an active workout are stored on `LoggedExercise.notes` and are copied when starting from a past workout. Workout-level notes already appear in workout history, but exercise-level notes are not displayed in workout history detail or exercise history detail. For the initial release, this makes exercise notes feel swallowed even though the data exists.

## Goal

Display exercise notes read-only in history for the initial release. Historical workout editing is out of scope and should be handled as a future feature.

## Approved Approach

Use targeted read-only rendering. Add a small reusable note display component in the history feature and place it where the logged exercise already appears.

In `WorkoutHistoryDetailView`, each exercise card displays its note below that exercise's set list.

In `ExerciseHistoryDetailView`, each session group for the selected exercise displays the matching logged exercise note below the completed set list.

This was chosen over a combined notes block or a collapsed note indicator because it keeps each note attached to the exercise it describes, works in both history surfaces, and avoids new interaction behavior before release.

## UI Behavior

Exercise notes are immutable text in history for this release.

Only non-empty notes display. The empty check trims whitespace and newlines, but the displayed note keeps the user's original internal line breaks.

The note block appears after the set rows and uses the existing dark surface styling so it reads as supporting detail, not a new editable field. Workout-level notes remain separate from exercise-level notes.

## Architecture And Data Flow

`LoggedExercise.notes` remains the source of truth. No SwiftData schema or persistence changes are needed.

The history feature should include a focused read-only component, for example `ExerciseNoteBlock`, that takes a note string, determines whether it has displayable content, and renders nothing when the note is empty after trimming.

`WorkoutHistoryDetailView` can pass each `loggedExercise.notes` directly to the component.

`ExerciseHistoryDetailView` can use the `loggedExercise` already carried by each `ExerciseHistorySetEntry`. Because each `ExerciseHistorySessionGroup` is built for one selected exercise within one session, the note can come from the group's matching logged exercise and appear below that group's set rows.

History summary and grouping behavior should remain unchanged.

## Edge Cases

Whitespace-only exercise notes do not render.

Multi-line notes render with line breaks preserved.

Exercise history continues to show completed sets only. If the matching logged exercise has a note, the note appears below those completed set rows.

Workout-level notes remain unchanged and are not merged with exercise notes.

Starting from a past workout can continue copying exercise notes as it does today.

## Testing

Add focused automated coverage for the display rules and data path:

- A completed logged exercise with notes remains associated with its exercise history group.
- Whitespace-only notes are treated as absent by the display helper or component.
- Multi-line note text is passed through for display with internal line breaks intact.

Manual verification should complete a workout with both a workout note and at least one exercise note, then confirm the exercise note appears in workout history detail and exercise history detail while history remains read-only.
