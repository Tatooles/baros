# Local Release Baseline Audit

## Summary

- Branch: `3-audit-and-stabilize-local-release-baseline`
- Scope: Local/offline Phase 0 baseline for workout creation, editing, finishing, history, settings, SwiftData persistence, and tests.
- Result: Pass with follow-ups. No Phase 0 blocker fixes were required.

## Automated Verification

| Check | Tool | Result | Notes |
| --- | --- | --- | --- |
| Full test suite | XcodeBuildMCP `test_sim` | Pass | `SUCCEEDED`; 49 passed, 0 failed, 0 skipped; duration `70392ms`; project `LiftingLog.xcodeproj`, scheme `LiftingLog`, simulator `iPhone 16`; build log `/Users/kevintatooles/Library/Developer/XcodeBuildMCP/workspaces/codex-ios-app-62beddaa6b92/logs/test_sim_2026-05-24T19-31-39-786Z_pid34880_f0098b0b.log`; result bundle `/Users/kevintatooles/Library/Developer/XcodeBuildMCP/workspaces/codex-ios-app-62beddaa6b92/result-bundles/test_sim_2026-05-24T19-31-39-787Z_pid34880_b61cbdcc.xcresult`. |
| Final full suite | XcodeBuildMCP `test_sim` | Pass | `SUCCEEDED`; 49 passed, 0 failed, 0 skipped; duration `60596ms`; build log `/Users/kevintatooles/Library/Developer/XcodeBuildMCP/workspaces/codex-ios-app-62beddaa6b92/logs/test_sim_2026-05-24T20-07-05-231Z_pid34880_d4abda02.log`; result bundle `/Users/kevintatooles/Library/Developer/XcodeBuildMCP/workspaces/codex-ios-app-62beddaa6b92/result-bundles/test_sim_2026-05-24T20-07-05-231Z_pid34880_d6155aaa.xcresult`. |
| Unit tests | XcodeBuildMCP `test_sim -only-testing:LiftingLogTests` | Not run | Full suite passed, so isolated unit rerun was not needed. |
| UI tests | XcodeBuildMCP `test_sim -only-testing:LiftingLogUITests` | Not run | Full suite passed, so isolated UI rerun was not needed. |

## Coverage Map

| Domain | Existing automated coverage | Missing release-critical coverage |
| --- | --- | --- |
| Workout creation | `testStartingBlankCreatesOneActiveSessionWithBlankSource`, `testStartingBlankTwiceReturnsExistingActiveSession`, `testStartingFromPastCopiesExerciseOrderAndIncompleteSets`, `testStartingFromPastWorkoutDoesNotMutateOriginalPastWorkout`, `testStartBlankWorkoutFlow` | No direct UI coverage for starting from a past workout; manual audit covered the repeat-workout flow. |
| Active workout editing | `testAddingExerciseAppendsOrderIndexAndFirstSet`, `testAddingSetCopiesPreviousValuesAndStartsIncomplete`, `testRemovingSetReindexesRemainingSets`, `testCompletingSetUpdatesMetrics`, `testUpdatingWorkoutTitleAllowsEmptyDraftWhileEditing`, `testFinalizingWorkoutTitleAppliesDefaultForBlankDraft`, `testFocusOrderTraversesWholeWorkout`, `testAdjacentFocusTraversesExerciseNotesBetweenExercises`, `testFocusOrderSkipsFieldsForCollapsedExercises`, `testAdjacentFocusReturnsPreviousAndNextTargets`, `testDecimalWorkoutInputPreservesTrailingSeparatorWhileEditing`, `testDecimalWorkoutInputUsesFormattedModelValueAfterEditingEnds`, `testNumberParserAcceptsLocaleDecimalSeparator`, `testNumberFormatterPreservesConvertedWeightPrecision`, `testAddingExerciseAndSetMovesFocusAndKeyboardCanBeDismissed`, `testAddingExerciseScrollsNewExerciseToTop` | No direct UI coverage for editing reps, RPE, notes, collapsing or expanding exercises, deleting exercises from an active workout, or save-error UI paths; these are non-blocking follow-up coverage gaps unless a manual failure appears. |
| Finish/discard/delete | `testFinishingMovesSessionOutOfActiveStateAndIntoHistory`, `testDiscardedSessionsDoNotAppearInCompletedHistoryFetches`, `testFinishedWorkoutAppearsInCompletedHistoryFetch`, `testDeletedCompletedWorkoutNoLongerAppears`, `testTabNavigationAndFinishSheetSmoke` | Finish sheet UI smoke covers opening and Keep Going only; manual audit covered saving, discarding, and deleting through the UI. |
| History | `testFinishedWorkoutAppearsInCompletedHistoryFetch`, `testDeletedCompletedWorkoutNoLongerAppears`, `testExerciseHistoryCountsCompletedSetsOnly`, `testExerciseHistorySummaryUsesSnapshotNameAfterExerciseRename`, `testExerciseHistoryGroupsCompletedSetsByWorkoutSession`, `testExerciseHistoryGroupingMatchesSnapshotNameWhenExerciseIDIsMissing`, `testExerciseHistoryGroupsSortTitleAscendingWhenStartedAtMatches`, `testStartingFromPastWorkoutDoesNotMutateOriginalPastWorkout`, `testDateFormatterIncludesWeekdayMonthAndDay`, `testDurationFormatterUsesHourStyleWhenNeeded`, `testDurationFormatterUsesMinuteStyleForShorterValues` | No direct UI coverage for completed workout detail, exercise history drill-down, empty history state, or visible history deletion; manual audit covered these flows. |
| Exercise library | `testSeedServiceInsertsExpectedExercises`, `testSeedServiceIsIdempotent`, `testCreatingExerciseSavesAndFetchesByID`, `testCustomExerciseCanBeCreatedEditedAndArchived`, `testSeededExerciseWithHistoryArchivesInsteadOfHardDeleting`, `testAddingExerciseAndSetMovesFocusAndKeyboardCanBeDismissed`, `testAddingExerciseScrollsNewExerciseToTop` | No direct UI coverage for exercise create, edit, duplicate-name validation, archive/remove, searching, or picker hiding; manual audit covered library create, edit, duplicate-name validation, and removal from the active library list. |
| Settings | `testSettingsSingletonExistsAfterSeed`, `testUpdatingWeightUnitPersists`, `testUpdatingWeightUnitConvertsExistingLoggedWeights`, `testSeedDoesNotOverwriteUserEditedSettings`, `testSettingsSingletonIsCreatedExactlyOnce`, `testMeasurementUnitProvidesUppercaseWorkoutFieldPlaceholder`, `testTabNavigationAndFinishSheetSmoke` | No direct UI coverage for changing settings from Profile/Settings screens; manual audit covered unit change and rest timer change in-session. |
| SwiftData persistence | `testCreatingExerciseSavesAndFetchesByID`, `testWorkoutSessionPersistsLoggedExerciseAndSetRelationships`, `testCompletedSetVolumeRequiresWeightRepsAndCompletion`, `testHealthDataLinkStoresFutureProviderWithoutFrameworkImport`, `testWorkoutTemplateCanBeCreatedWithoutDrivingUI`, `testCustomExerciseCanBeCreatedEditedAndArchived`, `testSeededExerciseWithHistoryArchivesInsteadOfHardDeleting`, plus in-memory persistence coverage in engine, history, settings, and seed tests | No direct migration or disk-backed relaunch coverage; normal simulator launch observed pre-existing disk-backed simulator state, but deterministic fresh manual verification used the in-memory UI-test store. |
| UI smoke flows | `testStartBlankWorkoutFlow`, `testTabNavigationAndFinishSheetSmoke`, `testAddingExerciseAndSetMovesFocusAndKeyboardCanBeDismissed`, `testAddingExerciseScrollsNewExerciseToTop` | UI smoke coverage does not automate a full create, add data, finish, and verify history loop; manual audit covered that end-to-end path. |

## Manual Verification

| Workflow | Result | Notes |
| --- | --- | --- |
| Fresh launch and seed data | Pass with caveat | Normal launch resumed pre-existing disk-backed simulator state with an active workout, so it did not provide a no-active-workout baseline. Deterministic fresh baseline used `--uitest-in-memory-store`; Start Workout showed `No Past Workouts`, and seeded exercises such as Back Squat and Bench Press were visible. |
| Blank workout creation and finish | Pass | Started a blank workout, added Bench Press, entered `185 x 5 @ 8`, marked the first set complete, added a second set, confirmed values copied as `185 x 5 @ 8` and remained incomplete, then saved. Finish sheet showed `1/2` sets and volume `925`; saving returned to Start with a past-workout card. |
| History detail and exercise history | Pass | Workouts history showed the saved workout with 1 exercise and 2 sets. Detail showed duration about `00:45`, 1 exercise, 1 completed set, volume `925`, Bench Press Set 1 `185 x 5 Done`, and Set 2 `185 x 5 Open`. Exercise history showed Bench Press `x1` and detail `185 x 5 @ 8`. |
| Past-workout reuse | Pass | Selecting the past workout created a new active workout with Bench Press and two copied sets, both incomplete. Changing the copied first set to `200` did not mutate the original completed workout. Discard confirmation appeared and discard kept the copy out of completed history. |
| Settings and unit conversion | Pass with caveat | Profile initially showed 1 workout, 20 active exercises, and `LBS`. Changing Pounds to Kilograms updated Profile to `KG` and `Kilograms`; history UI displayed the prior `185` lb set as `83.914588` kg and volume as `419.572942`. Rest timer changed from `90 seconds` to `105 seconds` in-session; relaunch persistence was not manually checked. |
| Exercise library create/edit/remove | Pass with caveat | Seeded exercises were visible. Created custom `Audit Row`, edited it to `Audit Chest Supported Row`, attempted duplicate active creation and saw `An active exercise with that name already exists.`, then removed the custom exercise and confirmed it disappeared from the active library list. Search-after-removal and picker hiding after removal were not separately checked. |
| Completed workout delete | Pass | After user confirmation, deleted the completed workout from history detail. Workouts history showed `No Workouts Yet`; Exercises history showed `No Exercise History`, confirming related completed-set history no longer contributed. |

## Blocker Review

| Finding | Blocker? | Rationale | Action |
| --- | --- | --- | --- |
| Normal launch resumed an existing active workout in the disk-backed simulator store. | No | This observed pre-existing simulator state, not data loss or a broken workflow. It only prevented a clean no-active-workout manual baseline on the existing simulator. | Relaunched with `--uitest-in-memory-store` for deterministic manual verification; record as an evidence caveat. |
| Manual fresh baseline used the in-memory UI-test store. | No | In-memory launch is valid for deterministic UI workflow verification, but it does not prove disk-backed relaunch persistence. Automated SwiftData tests cover model persistence in memory, and disk-backed relaunch can be added as a future hardening check. | Record as a follow-up coverage gap, not a blocker. |
| Rest timer persistence was verified only within the current app session. | No | The setting changed from 90 to 105 seconds and remained visible in-session. The plan only required in-session persistence for this manual step. | Record relaunch verification as non-blocking follow-up. |
| Removed custom exercise was confirmed hidden from the active library list but not separately from the add-exercise picker. | No | Library removal worked and no release-critical workout data was lost. Picker hiding is useful coverage but not a blocker based on observed behavior. | Record as non-blocking follow-up. |
| Automated UI coverage lacks a full create-add-finish-history test. | No | Manual verification covered the end-to-end flow successfully, and existing unit/UI tests cover important pieces. | Record as a follow-up test coverage gap. |
| Unit conversion displayed high-precision values such as `83.914588` kg and `419.572942` volume. | No | Values were converted consistently and did not corrupt data, but the visible precision is rough for release-quality display. | Record as a non-blocking formatting follow-up. |

## Fixes Made

- No blocker fixes were required.

## Follow-Up Notes

- Add UI coverage for the full local loop: start blank workout, add set data, finish, and verify history.
- Add UI coverage for starting from a past workout.
- Add UI coverage for Settings changes from Profile, including unit switching and rest timer changes.
- Add UI coverage for Exercise Library create, edit, duplicate-name validation, remove/archive, search, and picker hiding.
- Consider a disk-backed simulator relaunch check before TestFlight hardening to distinguish in-memory workflow confidence from on-disk persistence confidence.
- Round or otherwise polish converted weight and volume display so unit changes do not expose excessive decimal precision.
