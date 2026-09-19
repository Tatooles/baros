# History detail blocks and accent pills

Captured September 19, 2026 from `Baros.xcodeproj`, scheme `Baros`, on the
**iPhone 17e / iOS 26.4** simulator. All 18 images are unmodified screenshots
from targeted UI tests and were visually inspected.

Exercise sections and session groups use flat `AppTheme.groupedSurface` blocks,
20pt continuous corners, 16pt inner padding, and 12pt spacing between blocks.
Only set rows have subtle hairlines. Each block has an accent set-count pill;
exercise names and dates remain primary text. The workout hero, stats and
italic workout note remain unboxed. The pill is informational in Workout
History and joins the chevron as the source-workout button in Exercise History
and Quick History.

The table header and values share weight, multiplication-sign, reps and
annotation columns so the labels align with the numbers both with and without
RPE. Session-header controls retain a 44pt touch target aligned at the top;
centering that target no longer adds space above the date. The records-to-first-
session gap is 12pt, matching the spacing between session blocks. Record tiles
are unchanged.

## Fixtures and screenshots

`--uitest-seed-history-blocks` is a DEBUG-only fixture: a six-exercise Full Body
workout with 17 displayed sets, three exercise notes and three unnoted exercises,
plus two older Bench Press workouts. Bench Press includes one completed and one
uncompleted set to keep the presentation/eligibility distinction covered.

| Files | Evidence |
| --- | --- |
| `workout-dark.png`, `workout-light.png` | Six-exercise fixture, unboxed hero and first blocks |
| `workout-six-exercises-block-3-dark.png`, `workout-six-exercises-block-6-dark.png` | Further down the six-exercise workout, with and without notes |
| `exercise-dark.png`, `exercise-light.png` | Three-session fixture, hero, existing record tiles and first blocks |
| `exercise-no-rpe-dark.png`, `exercise-no-rpe-light.png` | Column alignment without RPE, including a record glyph and a 44pt source-workout target |
| `exercise-three-sessions-dark.png`, `exercise-three-sessions-light.png` | All three session blocks visible together |
| `workout-accessibility3.png`, `exercise-accessibility3.png` | Large-text headers |
| `workout-accessibility3-table.png`, `exercise-accessibility3-table.png` | Scrolled large-text blocks and set announcements |
| `workout-mixed-notes-dark.png` | Two-exercise fixture with only the second exercise noted; no boundary hairline |
| `quick-history-medium-dark.png`, `quick-history-medium-light.png` | Initial medium detent, without scrolling or expanding: heading, first block header and first set row fully visible |
| `quick-history-compact-heading-accessibility3.png` | Large-text Quick History heading and first block header |

## Validation

The alignment/spacing follow-up passed 6 targeted UI tests in two sequential
batches of 3, with parallel testing disabled. These refresh all screenshots and
cover standard/large text, dark/light, with/without RPE, mixed notes, source
navigation, the 44pt source button target, and Quick History medium-detent fit.
The preceding block-grouping change passed 12 targeted tests in three batches.
`git diff --check` passed.

The screenshot tests also check complete set announcements, an informational
Workout History pill, three Exercise History source buttons, and source-workout
navigation and return from Quick History in both appearances. The six-exercise
scroll test checks all six count pills and the three attached notes. The Quick
History accessibility test uses `UICTContentSizeCategoryAccessibilityXL` so text
size reaches the presented sheet, then scrolls to verify the note.

No full-suite run was performed. The follow-up built, installed and launched
on Kevin's iPhone 17 / iOS 27.0; simulator screenshot inspection is separate
from the user's on-device visual acceptance. The existing large-text Quick
History keyboard flow still reports `Invalid frame dimension (negative or
non-finite)` while passing. No production model, sync, completion-state or
record-eligibility code changed.

Result bundles are under
`~/Library/Developer/XcodeBuildMCP/workspaces/codex-ios-app-62beddaa6b92/result-bundles/`:

- `test_sim_2026-09-19T00-18-07-173Z_pid95875_28a085b4.xcresult`: 2 passed; dark/light/accessibility detail layouts and medium-detent Quick History with source navigation.
- `test_sim_2026-09-19T00-21-33-389Z_pid95875_371b01f3.xcresult`: 4 passed; six-block scroll, mixed notes, large-text Quick History, truncation footer and Full History route.
- `test_sim_2026-09-19T00-23-44-223Z_pid95875_98598701.xcresult`: 6 passed; set announcements, record sources, Quick History record exclusion, exact source-workout navigation and matching-title/date identity.

Alignment/spacing follow-up:

- `test_sim_2026-09-19T17-13-21-250Z_pid41251_8402f07d.xcresult`: 3 passed; detail appearances/accessibility, medium-detent Quick History, and no-RPE tables with record indicators.
- `test_sim_2026-09-19T17-16-53-590Z_pid41251_cd874af9.xcresult`: 3 passed; six-exercise scrolling, mixed notes and large-text Quick History.

Device build/install/launch log:
`~/Library/Developer/XcodeBuildMCP/workspaces/codex-ios-app-62beddaa6b92/logs/build_run_device_2026-09-19T17-18-33-100Z_pid41251_7a60922d.log`.
