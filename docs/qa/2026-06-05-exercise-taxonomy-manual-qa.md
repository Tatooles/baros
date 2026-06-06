# Exercise Taxonomy Manual QA

Date: 2026-06-05
Build target: iOS Simulator, `LiftingLog`
Launch mode: `--uitest-in-memory-store`

## Scope

Manual QA for issue 40 implementation:

- Exercise creation/editing uses controlled equipment and primary muscle group values.
- Exercise library allows same exercise name with different equipment, but rejects exact name + equipment duplicates.
- Exercise picker, active workout cards, workout history, and exercise history surface equipment + primary muscle metadata as secondary text.
- Active workout history for an exercise resolves by specific exercise identity/name + equipment, not by name alone.
- Existing set editing behavior still allows clearing completed weight/RPE values.

## Results

| ID | Scenario | Expected Result | Status | Notes |
| --- | --- | --- | --- | --- |
| QA-01 | Launch app with isolated store and open exercise library | Seeded exercises are visible; rows show name as primary text and equipment + primary muscle as secondary metadata. | Pass | Verified simulator launch plus exercise picker/library metadata assertions such as `Bench Press, Barbell • Chest`. |
| QA-02 | Create `Manual QA Press` with Barbell + Chest | Exercise saves and appears as `Manual QA Press` with `Barbell • Chest`. | Pass | Executed with equivalent test value `Variant Press`; verified Barbell + Chest metadata. |
| QA-03 | Create another `Manual QA Press` with Dumbbell + Chest | Second exercise saves; library can show both Barbell and Dumbbell variants. | Pass | Executed with equivalent test value `Variant Press`; verified Barbell and Dumbbell rows coexist. |
| QA-04 | Attempt exact duplicate `Manual QA Press` with Barbell + Chest | Save is rejected with duplicate name + equipment validation. | Pass | Verified exact name + equipment duplicate validation message. |
| QA-05 | Add Barbell variant to a workout and complete a set | Active workout card/picker surfaces `Barbell • Chest`; workout can be saved. | Pass | Logged a Barbell `Variant Bench` workout and verified workout save path. |
| QA-06 | Add Dumbbell variant to a later active workout and open its quick history | Quick history for Dumbbell variant does not show the Barbell workout history. | Pass | Verified Dumbbell quick history excludes the prior Barbell workout title. |
| QA-07 | Exercise history after both variants are logged | Exercise history has separate Barbell and Dumbbell entries; each detail shows only matching variant sessions. | Pass | Verified separate `Variant Bench, Barbell • Chest` and `Variant Bench, Dumbbell • Chest` history entries. |
| QA-08 | Clear completed RPE in a saved-workout flow | Saved exercise history set summary omits `@ 8` after clearing RPE. | Pass | Verified edited saved set summary becomes `185 x 5`. |

## Execution Notes

- Launched the app in the iOS Simulator with XcodeBuildMCP `build_run_sim` using `--uitest-in-memory-store`.
- XcodeBuildMCP screenshot confirmed the app was on the expected Start Workout screen. Semantic UI snapshot did not expose tappable element refs, so coordinate-based manual navigation was not available in this simulator session.
- Executed the manual QA scenarios through focused simulator XCUITest flows that drive the same user workflows.
- XcodeBuildMCP `test_sim` reached the 120 second tool timeout before returning final results, so the same focused suite was rerun with `xcodebuild` against the configured `iPhone 17` simulator.
- Focused suite command:

  ```sh
  xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogUITests/LiftingLogUITests/testExerciseLibraryAllowsSameNameWithDifferentEquipmentAndRejectsExactDuplicate -only-testing:LiftingLogUITests/LiftingLogUITests/testActiveWorkoutHistorySeparatesSameNameDifferentEquipment -only-testing:LiftingLogUITests/LiftingLogUITests/testCompletedWorkoutCanBeOpenedFromWorkoutAndExerciseHistory -only-testing:LiftingLogUITests/LiftingLogUITests/testClearingCompletedRPERemovesLoggedRPE -derivedDataPath /private/tmp/codex-ios-app-derived-data-qa
  ```

- Result: `Test Suite 'Selected tests' passed`; 4 tests executed, 0 failures, 250.679 seconds.
- Result bundle: `/tmp/codex-ios-app-derived-data-qa/Logs/Test/Test-LiftingLog-2026.06.05_10-56-55--0500.xcresult`.
