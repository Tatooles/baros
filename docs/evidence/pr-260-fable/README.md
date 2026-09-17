# History detail hierarchy

Screenshots from the Baros scheme in an iPhone 17e simulator on iOS 26.5.
The deterministic Push Day fixture includes a completed and an uncompleted set,
a workout narrative, an exercise note, RPE, and one set holding both records.
Workout History displays both sets identically; Exercise History retains its
existing completed-set selection and record eligibility.

- `workout-dark.png`, `exercise-dark.png`: standard Dynamic Type, dark appearance.
- `workout-light.png`, `exercise-light.png`: standard Dynamic Type, light appearance.
- `workout-accessibility3.png`, `exercise-accessibility3.png`: accessibility3 headers.
- `workout-accessibility3-table.png`, `exercise-accessibility3-table.png`: scrolled accessibility3 tables.

Captured by `testHistoryDetailLayoutsInBothAppearancesAndAccessibilitySize`.
The test checks set visibility and horizontal bounds, rounded estimated 1RM,
complete set announcements, and both record labels on the shared source set.

Validation for this follow-up: 12 distinct focused History UI tests passed across
focused runs. Coverage includes layout/appearance, accessibility, sparse records,
record source identity, source-workout navigation, both deletion routes, note
editing, kilogram conversion, and Quick History isolation. The final table layout
was recaptured and its nonduplicated accessibility announcements rechecked.

No physical-device validation was performed. The full unit suite was not rerun
locally for this presentation-only follow-up. Runtime layout warnings occurred in
the existing Quick History and completed-note editor flows; those tests passed.
