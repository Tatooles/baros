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
session gap is 12pt, matching the spacing between session blocks. Record tile styling is retained; source summaries show the original set number
and full workout date, including the year.

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
| [exercise-dark.png](https://github.com/user-attachments/assets/182b10a2-0a18-443e-a3f5-8789882c8dae), [exercise-light.png](https://github.com/user-attachments/assets/6b1d8a43-2cbe-4946-940f-c9e61789fd96) | Three-session fixture, hero, existing record tiles and first blocks |
| [exercise-no-rpe-dark.png](https://github.com/user-attachments/assets/46f38af0-095f-449f-9e6b-444aad5e9a9f), [exercise-no-rpe-light.png](https://github.com/user-attachments/assets/dea5ae7a-2133-4d64-883c-40cf929c5973) | Column alignment without RPE, including a record glyph and a 44pt source-workout target |
| [exercise-three-sessions-dark.png](https://github.com/user-attachments/assets/05597c9e-3bdc-4900-8e83-a2f678cc4b77), [exercise-three-sessions-light.png](https://github.com/user-attachments/assets/ca771fee-4602-4826-93b3-1267b76ed015) | All three session blocks visible together |
| [workout-accessibility3.png](https://github.com/user-attachments/assets/080afdd5-5461-4c07-b305-b0ad4c53c6a7), [exercise-accessibility3.png](https://github.com/user-attachments/assets/795b3db1-dfb6-414e-b0de-6a8ece79f632) | Large-text headers |
| [workout-accessibility3-table.png](https://github.com/user-attachments/assets/2aaf64f3-82f4-457a-b185-63eecdb160bd), [exercise-accessibility3-table.png](https://github.com/user-attachments/assets/92cd39e8-b23e-44b8-b47f-fa9a1f1c5a3d) | Scrolled large-text blocks and set announcements |
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

## Review follow-up (September 19, 2026)

All six open review findings are addressed: record source dates include the year,
source set numbers remain visible, help describes the trophy marker, duplicate
exercise occurrences are separated by space, estimated 1RM retains fractional display precision, and set columns expand for the
formatted values. Tables use the stacked layout when horizontal space is insufficient.

Six targeted UI tests passed in three sequential batches (2, 3, 1) on
iPhone 17e / iOS 26.4, scheme `Baros`. These cover prior-year records, original
numbering with an incomplete-set gap, duplicate occurrences and notes, 1,000 reps,
fractional pounds and converted kilograms at larger text, trophy help, dark/light
and accessibility layouts, and Quick History medium-detent fit and navigation.
No full-suite run or new physical-device install was performed for this follow-up.
Eight Exercise History images above were refreshed as GitHub attachments.

Additional review evidence:

- [review-long-values-pounds.png](https://github.com/user-attachments/assets/d3705035-87c9-4399-9fed-0db2b360d5d1)
- [review-record-sources.png](https://github.com/user-attachments/assets/29f8c1b5-b9ce-4403-b63c-11051299f369)
- [review-trophy-help.png](https://github.com/user-attachments/assets/04194ac6-082b-4531-8d48-478048c0c1e6)

Result bundles (under the workspace result-bundles directory above):

- `test_sim_2026-09-19T19-29-31-419Z_pid26339_48a9f648.xcresult`: 2 passed.
- `test_sim_2026-09-19T19-31-25-144Z_pid26339_f3df4cc0.xcresult`: 3 passed.
- `test_sim_2026-09-19T19-34-58-445Z_pid26339_d6dd27b0.xcresult`: 1 passed.

The late estimated-1RM precision comment was fixed by removing the extra
whole-number rounding before `WorkoutFormatters.number`. The dark/light/accessibility
detail test passed again, asserting `215.83 lbs` rather than `216 lbs`, and the
six affected Exercise History attachments were refreshed. Longer estimates can
move their unit to another line in the existing record tile.

- `test_sim_2026-09-19T19-48-50-506Z_pid26339_5f548efd.xcresult`: 1 passed.


## Equal record tiles and scaled RPE (September 19, 2026)

Side-by-side record tiles now share the height of the taller tile, with equal
widths and top-aligned content. Fractional estimates and longer source summaries
can wrap without leaving mismatched containers. Accessibility sizes retain the
full-width vertical arrangement. RPE annotations and their reserved column width
now scale together with caption text; `@ 10` and `@ 9.5` remain on one line at XXXL.

Five targeted UI tests passed across sequential batches on iPhone 17e / iOS 26.4.1:
dark/light/accessibility detail layouts, medium-detent Quick History, largest
standard-text RPE, sparse/no-estimate states, and long values in pounds/kilograms.
The detail and long-value tests assert equal tile widths, heights and top edges.
The long-value test initially encountered empty History before opening a detail;
an isolated rerun passed both units without changing production or fixture code.

- `test_sim_2026-09-20T00-36-39-090Z_pid38864_ca80633d.xcresult`: 2 passed.
- `test_sim_2026-09-20T00-39-13-285Z_pid38864_829be628.xcresult`: RPE and sparse states passed; long-value fixture navigation failed.
- `test_sim_2026-09-20T00-41-48-355Z_pid38864_76d6b788.xcresult`: isolated long-value test passed.

Four affected Exercise History screenshots above were refreshed as GitHub
attachments. [Largest standard-text RPE screenshot](https://github.com/user-attachments/assets/2d980f26-3b83-4edc-aacb-6a9f4579bac7).
Screenshots remain outside the repository. The same build installed and launched
on Kevin's iPhone 17 / iOS 27.0. Device log:
`build_run_device_2026-09-20T00-42-49-731Z_pid38864_9a3e1fff.log`.
