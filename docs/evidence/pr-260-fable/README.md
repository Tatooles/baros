# History detail blocks and accent pills

Captured September 18, 2026 from `Baros.xcodeproj`, scheme `Baros`, on the
**iPhone 17e / iOS 26.4** simulator. All 16 images are unmodified screenshots
from targeted UI tests and were visually inspected.

Exercise sections and session groups use flat `AppTheme.groupedSurface` blocks,
20pt continuous corners, 16pt inner padding, and 12pt spacing between blocks.
Only set rows have subtle hairlines. Each block has an accent set-count pill;
exercise names and dates remain primary text. The workout hero, stats and
italic workout note remain unboxed. The pill is informational in Workout
History and joins the chevron as the source-workout button in Exercise History
and Quick History.

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
| `exercise-three-sessions-dark.png`, `exercise-three-sessions-light.png` | All three session blocks visible together |
| `workout-accessibility3.png`, `exercise-accessibility3.png` | Large-text headers |
| `workout-accessibility3-table.png`, `exercise-accessibility3-table.png` | Scrolled large-text blocks and set announcements |
| `workout-mixed-notes-dark.png` | Two-exercise fixture with only the second exercise noted; no boundary hairline |
| `quick-history-medium-dark.png`, `quick-history-medium-light.png` | Initial medium detent, without scrolling or expanding: heading, first block header and first set row fully visible |
| `quick-history-compact-heading-accessibility3.png` | Large-text Quick History heading and first block header |

## Validation

12 targeted History UI tests passed in three sequential batches (2, 4 and 6),
with parallel testing disabled. `git diff --check` passed.

The screenshot tests also check complete set announcements, an informational
Workout History pill, three Exercise History source buttons, and source-workout
navigation and return from Quick History in both appearances. The six-exercise
scroll test checks all six count pills and the three attached notes. The Quick
History accessibility test uses `UICTContentSizeCategoryAccessibilityXL` so text
size reaches the presented sheet, then scrolls to verify the note.

No full-suite run or physical-device validation was performed. Two existing
Quick History keyboard flows still report `Invalid frame dimension (negative
or non-finite)` while passing. No production model, sync, completion-state or
record-eligibility code changed.

Result bundles are under
`~/Library/Developer/XcodeBuildMCP/workspaces/codex-ios-app-62beddaa6b92/result-bundles/`:

- `test_sim_2026-09-19T00-18-07-173Z_pid95875_28a085b4.xcresult`: 2 passed; dark/light/accessibility detail layouts and medium-detent Quick History with source navigation.
- `test_sim_2026-09-19T00-21-33-389Z_pid95875_371b01f3.xcresult`: 4 passed; six-block scroll, mixed notes, large-text Quick History, truncation footer and Full History route.
- `test_sim_2026-09-19T00-23-44-223Z_pid95875_98598701.xcresult`: 6 passed; set announcements, record sources, Quick History record exclusion, exact source-workout navigation and matching-title/date identity.
