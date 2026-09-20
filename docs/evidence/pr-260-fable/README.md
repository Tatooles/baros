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
| [exercise-dark.png](https://github.com/user-attachments/assets/13f0b54f-5d1c-4214-b979-9e020d10a1d2), [exercise-light.png](https://github.com/user-attachments/assets/cf5f5416-bae5-4fac-ab7c-503530e03247) | Three-session fixture, hero, existing record tiles and first blocks |
| [exercise-no-rpe-dark.png](https://github.com/user-attachments/assets/46f38af0-095f-449f-9e6b-444aad5e9a9f), [exercise-no-rpe-light.png](https://github.com/user-attachments/assets/dea5ae7a-2133-4d64-883c-40cf929c5973) | Column alignment without RPE, including a record glyph and a 44pt source-workout target |
| [exercise-three-sessions-dark.png](https://github.com/user-attachments/assets/f67ae2a6-dd40-4bd3-ba64-8bf392c9b14b), [exercise-three-sessions-light.png](https://github.com/user-attachments/assets/b5c7b126-fab6-4ba5-9de7-5d41426b4bde) | All three session blocks visible together |
| [workout-accessibility3.png](https://github.com/user-attachments/assets/080afdd5-5461-4c07-b305-b0ad4c53c6a7), [exercise-accessibility3.png](https://github.com/user-attachments/assets/be615ff9-dc85-4106-bf9b-ba630547a4bf) | Large-text headers |
| [workout-accessibility3-table.png](https://github.com/user-attachments/assets/2aaf64f3-82f4-457a-b185-63eecdb160bd), [exercise-accessibility3-table.png](https://github.com/user-attachments/assets/0474193a-999f-4ad1-975e-fe2228e001c3) | Scrolled large-text blocks and set announcements |
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


## Accessibility value wrapping (September 19, 2026)

Stacked set results use a wrapping text run for weight, multiplication sign,
reps and the optional trophy. Values that exceed one line now remain inside
the tinted block, including 10,000 pounds and 1,000 reps at Accessibility XXXL.
Compact column widths and normal-size presentation are unchanged.

Three targeted UI tests passed on iPhone 17e / iOS 26.4.1: maximum and fractional
values across Workout History, Exercise History and Quick History at the largest
accessibility size; long values in pounds/kilograms; and normal Quick History
medium-detent fit. No full-suite run. The new test's initial fractional-value
selector was corrected to include the formatter's thousands separator.

- `test_sim_2026-09-20T04-00-19-834Z_pid83503_04d75aff.xcresult`: existing pounds/kilograms test passed.
- `test_sim_2026-09-20T04-03-27-305Z_pid83503_640b638d.xcresult`: maximum-value and medium-detent tests passed.

Visually inspected GitHub attachments (no image files in the repository):
[Workout History](https://github.com/user-attachments/assets/0be14b11-cd65-4a0d-a5c1-9e56b7c9acd8),
[Exercise History](https://github.com/user-attachments/assets/916729ea-a4bc-428d-95d3-ab776b8fba75),
[Quick History](https://github.com/user-attachments/assets/8f0906f8-5cda-4451-b419-c14a30c51f68).


The subsequent record-source copy review is also addressed: visible sources now
include the selected weight unit and singular/plural rep labels (for example,
`225 lbs × 1 rep`). Equal tile dimensions remain covered by the dark/light and
long-value tests. Both targeted tests passed, including accessibility sizes and
converted kilograms; six Exercise History attachments were refreshed.

- `test_sim_2026-09-20T04-11-33-567Z_pid83503_767276f2.xcresult`: 2 passed.

## Shared column measurement cleanup (September 20, 2026)

Compact set tables now measure weight and rep column widths once per table
construction and share those values with the header and rows. The measurement
formula, formatting and layout are unchanged; stacked tables skip measurement.

Four targeted UI tests passed in two sequential batches on iPhone 17e:
dark/light/accessibility detail layouts, long values in pounds/kilograms,
maximum values at the largest accessibility size, and medium-detent Quick History.

- `test_sim_2026-09-20T05-57-28-955Z_pid51585_a4bbf61f.xcresult`: 2 passed.
- `test_sim_2026-09-20T06-00-43-713Z_pid51585_df736246.xcresult`: 2 passed.
