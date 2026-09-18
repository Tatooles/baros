# History detail polish

Captured from `Baros.xcodeproj`, scheme `Baros`, on an iPhone 17e simulator
running iOS 26.4. All eight existing images were refreshed for the shared
set-table changes; two new images cover the follow-up acceptance checks.

- `workout-dark.png`, `exercise-dark.png`: standard Dynamic Type, dark appearance.
- `workout-light.png`, `exercise-light.png`: standard Dynamic Type, light appearance.
- `workout-accessibility3.png`, `exercise-accessibility3.png`: accessibility3 headers.
- `workout-accessibility3-table.png`, `exercise-accessibility3-table.png`: scrolled accessibility3 tables.
- `workout-mixed-notes-dark.png`: two exercises; only the second has a note.
  The first table has a hairline between its two rows, no trailing hairline,
  and exactly one boundary hairline before the second exercise. The second
  exercise's single set ends without a hairline, followed by its attached note.
- `quick-history-medium-dark.png`: initial medium detent, without scrolling or
  expanding. The unchanged compact heading, first group's date and first set
  are fully visible with comfortable spacing; the note also fits. Detents and
  sheet spacing did not need adjustment. No record glyph is displayed.

The original Push Day fixture includes a completed and an uncompleted set,
a workout narrative, an exercise note, RPE, and one set holding both records.
Workout History still displays both sets; Exercise History retains its existing
completed-set selection and record eligibility. The mixed-notes fixture adds a
second exercise through a DEBUG-only UI-test option.

The eight detail images come from
`testHistoryDetailLayoutsInBothAppearancesAndAccessibilitySize`.
The new acceptance images come from
`testWorkoutHistoryWithOnlySecondExerciseNotedEndsSectionsCleanly` and
`testQuickHistoryMediumDetentShowsHeadingDateAndFirstJournalSet`.
Decorative dividers remain accessibility-hidden, so the mixed-notes test checks
fixture content and attaches a screenshot for visual verification of hairlines.

Quick History tests now check dated journal groups, complete shared-table set
announcements, attached notes at accessibility3, the unchanged truncation footer
and Full History route, and the absence of record computation/source navigation.
The obsolete card presentation enum and card-only rendering have been removed;
a compact-heading option preserves Quick History's existing heading.

Validation: 12 distinct targeted History UI tests passed in four sequential
batches (1, 3, 3, and 5), with parallel testing disabled. No full-suite run or
physical-device validation was performed. Two Quick History tests emitted an
`Invalid frame dimension (negative or non-finite)` runtime warning while passing;
the previous evidence also documented layout warnings in these flows.

Result bundles are under
`~/Library/Developer/XcodeBuildMCP/workspaces/codex-ios-app-62beddaa6b92/result-bundles/`:

- `test_sim_2026-09-18T03-15-25-198Z_pid13024_81579ddc.xcresult`: journal structure and set announcements.
- `test_sim_2026-09-18T03-17-14-721Z_pid13024_8f4d9413.xcresult`: all ten screenshots, mixed notes, medium detent.
- `test_sim_2026-09-18T03-19-25-748Z_pid13024_84fb4ce9.xcresult`: Quick History notes, footer, and records exclusion.
- `test_sim_2026-09-18T03-21-46-623Z_pid13024_a9209435.xcresult`: kilograms, Workout History announcements, records, accessibility, and sparse cases.

PR review follow-up (2026-09-18): record source announcements now use `1 rep`
and plural `reps` appropriately; the records UI test checks both complete source
phrases. Compact Quick History heading metadata retains its single-line limit,
while full detail and journal entry metadata can wrap.

`quick-history-compact-heading-accessibility3.png` shows the Quick History
heading at accessibility3. This test now uses the valid UIKit launch value
`UICTContentSizeCategoryAccessibilityXL` so the size reaches the presented sheet;
the shell-only accessibility flag did not do that. The test also scrolls to and
checks the attached note. All three focused review checks passed (record sources,
Quick History notes, and the standard-size medium detent); the corrected large-text
test also passed its separate rerun. The previously documented frame warning
still appears in the Quick History keyboard flow.

Review result bundles in the directory above:

- `test_sim_2026-09-18T23-15-35-064Z_pid39553_7c916001.xcresult`: three focused checks.
- `test_sim_2026-09-18T23-18-18-726Z_pid39553_e9b78536.xcresult`: corrected accessibility3 sheet check and screenshot.
