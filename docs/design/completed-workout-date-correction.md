# Completed workout date correction

Accepted design for [issue #248](https://github.com/Tatooles/baros/issues/248).

## Accepted decisions

- The existing completed-workout editor will offer calendar-date editing only. Start-time editing is outside #248. The current History and Home date displays do not expose a start time.
- Keep the issue's existing scope: edit the same completed workout through Save/Cancel, preserve duration for date-only changes, and leave Active Workouts untouched.
- Preserve existing individual set completion timestamps when changing the workout date. Those timestamps remain records of set completion actions; the corrected workout date controls workout chronology. Export may therefore contain set completion dates different from the corrected workout date. Existing behavior for completing or adding sets in the editor remains unchanged.

## Findings informing the remaining design

- Workout start time determines History order, Home activity, Exercise History recency, and unlinked previous-performance selection. Home's past-workout review date uses the workout end time, falling back to its start time.
- Individual set completion timestamps are exported and synchronized, but do not determine those displays or selections.
- Completing a set in the existing History editor records the actual edit time. A set's completion timestamp can therefore already fall outside the workout's recorded time range.

## Accepted interaction and timing policies

- Replace the read-only date with a Date row beside the existing Duration control. Its native compact picker opens the standard iOS calendar overlay above the editor. Dismissing that overlay leaves the selection in the workout draft; only the outer Save persists changes, and outer Cancel discards them.
- Use the device calendar and time zone captured when the editor opens, keeping that interpretation stable throughout the edit. Preserve the original local time of day on the selected date. Do not add a stored workout time zone or a time-zone selector.
- Across a daylight-saving gap, advance the nonexistent local time by the gap (for example, 2:30 a.m. becomes 3:30 a.m. for a one-hour gap). For a repeated local time, choose its earlier occurrence. Selecting the original calendar date leaves the original timestamp exactly unchanged, including any daylight-saving ambiguity.
- Validation concerns the selected calendar date, not the hidden clock time or calculated end time. Preserve duration even if the end crosses midnight or falls later than the current instant. This avoids rejecting choices based on a time the user cannot see or edit.
- Duration remains editable in the same workout editor. Users can change date, duration, or both before one Save. Capture the original effective duration before changing timing. On a date or duration change, save the selected start and selected duration with end equal to start plus duration. Preserve exact duration seconds when duration is unchanged; preserve record IDs and creation timestamps, and use actual save time for mutation timestamps.
- Retain the issue's no-op, rollback, ownership, sync, export, cache-refresh, and validation requirements. No schema migration or additional product flow is planned.

## Accepted date limit

Allow today and earlier calendar dates, with no arbitrary earliest date. Disable future days in the picker and validate changed dates again at Save. If rejected, retain the draft and explain: "Choose today or an earlier date." An unchanged date must not block unrelated edits to an existing record.

This editor changes an already completed workout. Assigning a future date does not create a planned workout: it keeps the completed status, can mark a future day this week as completed in Home activity, and changes History and performance recency. Planning future workouts would need distinct product semantics outside #248.

## Validation boundaries

The issue's accepted validation scope covers the edit draft and mutation/outbox operation, disk-backed reopening, downstream History/Home/previous-performance projections, export and sync round-trip, and the History editor UI. Calendar/DST, combined date/duration edits, no-op, owner rejection, and rollback checks belong at these boundaries. Run the full unit suite and the existing four-test UI smoke shard without changing its membership.

## Implementation notes

- `CompletedWorkoutEditDraft` captures the device calendar and time zone when the editor opens. It keeps the original instant separately, so returning to the original calendar day uses that exact value instead of reconstructing an ambiguous local time.
- The edit screen uses a native compact `DatePicker` in the Date row. Its standard iOS calendar overlay has the captured calendar's current day as its maximum; the outer Save validates a changed date again and leaves a failed draft visible.
- A timing mutation captures the original effective duration before moving the start. It updates the session's start, duration, and end together, preserving child set completion timestamps and recording only the workout-session update for an owned date-only correction.
- The date resolver preserves the selected day’s calendar components, including leap-month identity. Missing local times advance through the daylight-saving gap, and repeated local times resolve to the first occurrence.
- Draft child references are validated before any mutation or outbox record is created, so a stale editor reference cannot partially apply a date correction.

## Local validation

- The focused completed-workout date suite covers date-only and combined edits, duration preservation including legacy records, no-op and concurrent-update behavior, future-date validation, DST gaps and repeated times, disk reopening, ownership, rollback preflight, outbox behavior, chronology projections, and export/sync push-and-pull timing.
- The completed-workout editor UI test covers the compact picker’s calendar overlay, overlay dismissal, outer Cancel, and combined Date/Duration Save. The established completed-edit UI test and the unchanged four-test smoke shard run alongside it.
