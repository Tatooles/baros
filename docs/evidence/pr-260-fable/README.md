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

Screenshots are hosted as [PR #260 attachments](https://github.com/Tatooles/baros/pull/260),
not stored in the repository. The links below open the original images.

## Fixtures and screenshots

`--uitest-seed-history-blocks` is a DEBUG-only fixture: a six-exercise Full Body
workout with 17 displayed sets, three exercise notes and three unnoted exercises,
plus two older Bench Press workouts. Bench Press includes one completed and one
uncompleted set to keep the presentation/eligibility distinction covered.

| Attachments | Evidence |
| --- | --- |
| [workout-dark.png](https://github.com/user-attachments/assets/2a8a6b22-e091-4bbb-801e-3a9a1acd3212), [workout-light.png](https://github.com/user-attachments/assets/a1a5efc8-ef12-4903-90e5-647a9f4706d6) | Six-exercise fixture, unboxed hero and first blocks |
| [workout-six-exercises-block-3-dark.png](https://github.com/user-attachments/assets/aede2341-eb82-4d62-a33e-f3fddcf72c4d), [workout-six-exercises-block-6-dark.png](https://github.com/user-attachments/assets/15542134-12a1-480a-aa1a-5af75b71ebf1) | Further down the six-exercise workout, with and without notes |
| [exercise-dark.png](https://github.com/user-attachments/assets/b3ece9f7-230c-4f97-87b1-8cac061173ea), [exercise-light.png](https://github.com/user-attachments/assets/bf08dcc5-ad75-4863-9037-805005f03d4f) | Three-session fixture, hero, existing record tiles and first blocks |
| [exercise-no-rpe-dark.png](https://github.com/user-attachments/assets/fa90d6d8-c626-4256-99c3-dcf787837fc9), [exercise-no-rpe-light.png](https://github.com/user-attachments/assets/ed4b5960-9035-4417-81c1-4afb9c1e8ef5) | Column alignment without RPE, including a record glyph and a 44pt source-workout target |
| [exercise-three-sessions-dark.png](https://github.com/user-attachments/assets/f73e1bf2-61f6-4c10-a400-1983bc38b779), [exercise-three-sessions-light.png](https://github.com/user-attachments/assets/2f858340-d134-42b1-b946-f38ce2f46eda) | All three session blocks visible together |
| [workout-accessibility3.png](https://github.com/user-attachments/assets/080afdd5-5461-4c07-b305-b0ad4c53c6a7), [exercise-accessibility3.png](https://github.com/user-attachments/assets/2609d569-48df-4bba-921b-029c25dc2db9) | Large-text headers |
| [workout-accessibility3-table.png](https://github.com/user-attachments/assets/2aaf64f3-82f4-457a-b185-63eecdb160bd), [exercise-accessibility3-table.png](https://github.com/user-attachments/assets/abf25049-3722-451b-aadd-6947314b2298) | Scrolled large-text blocks and set announcements |
| [workout-mixed-notes-dark.png](https://github.com/user-attachments/assets/8e02efda-42c6-4bf3-9966-ca6041cf76ac) | Two-exercise fixture with only the second exercise noted; no boundary hairline |
| [quick-history-medium-dark.png](https://github.com/user-attachments/assets/56c8f88d-bf49-4ccc-9ec1-564c5887c5b6), [quick-history-medium-light.png](https://github.com/user-attachments/assets/b8ac0db1-e41e-44bb-b617-b20cadda8375) | Initial medium detent, without scrolling or expanding: heading, first block header and first set row fully visible |
| [quick-history-compact-heading-accessibility3.png](https://github.com/user-attachments/assets/ef200001-887c-4af8-9cd1-745c3fcc58fe) | Large-text Quick History heading and first block header |

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
