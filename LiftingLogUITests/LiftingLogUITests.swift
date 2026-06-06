import XCTest

final class LiftingLogUITests: XCTestCase {
    @MainActor
    func testStartBlankWorkoutFlow() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 3))
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Current"].exists)
    }

    @MainActor
    func testTabNavigationAndFinishSheetSmoke() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        openFinishWorkoutSheet(in: app)
        XCTAssertTrue(app.buttons["KeepGoingButton"].waitForExistence(timeout: 3))
        app.buttons["KeepGoingButton"].tap()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))

        app.buttons["ProfileTab"].tap()
        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAddingExerciseAndSetMovesFocusAndKeyboardCanBeDismissed() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        app.buttons["AddExerciseButton"].tap()
        XCTAssertTrue(app.navigationBars["Add Exercise"].waitForExistence(timeout: 3))
        let benchPressRow = app.buttons["ExercisePickerRow-Bench Press-Barbell"]
        XCTAssertTrue(benchPressRow.waitForExistence(timeout: 3))
        benchPressRow.tap()

        let firstWeightField = app.textFields["SetWeightField-0-0"]
        XCTAssertTrue(firstWeightField.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        app.buttons["DismissKeyboardButton"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        firstWeightField.tap()
        firstWeightField.typeText("185")
        app.buttons["AddSetButton-0"].tap()

        let secondWeightField = app.textFields["SetWeightField-0-1"]
        XCTAssertTrue(secondWeightField.waitForExistence(timeout: 3))
        XCTAssertEqual(secondWeightField.value as? String, "185")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testAddingExerciseScrollsNewExerciseToTop() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("Back Squat, Barbell • Quads", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("Bench Press, Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)

        let addedExerciseHeader = app.buttons["ExerciseHeader-1"]
        XCTAssertTrue(addedExerciseHeader.waitForExistence(timeout: 3))
        XCTAssertTrue(
            waitForElement(addedExerciseHeader, maxYOrigin: 150, timeout: 3),
            "Expected ExerciseHeader-1 to scroll near the top, got minY \(addedExerciseHeader.frame.minY)"
        )
    }

    @MainActor
    func testWorkoutOptionsDisablesReorderWithOneExercise() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addBenchPress(in: app)
        dismissKeyboardIfNeeded(in: app)

        openWorkoutOptions(in: app)
        let reorderButton = app.buttons["Reorder Exercises"]
        XCTAssertTrue(reorderButton.waitForExistence(timeout: 3))
        XCTAssertFalse(reorderButton.isEnabled)
    }

    @MainActor
    func testReorderingActiveWorkoutExercisesChangesCardOrder() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("Back Squat, Barbell • Quads", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("Bench Press, Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("Conventional Deadlift, Barbell • Glutes", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("Overhead Press, Barbell • Shoulders", in: app)
        dismissKeyboardIfNeeded(in: app)

        assertActiveWorkoutExerciseOrder(
            ["Back Squat", "Bench Press", "Conventional Deadlift", "Overhead Press"],
            in: app
        )

        openWorkoutOptions(in: app)
        let reorderButton = app.buttons["Reorder Exercises"]
        XCTAssertTrue(reorderButton.waitForExistence(timeout: 3))
        reorderButton.tap()

        XCTAssertTrue(waitForReorderExercisesList(in: app, timeout: 3))
        moveReorderExercise(named: "Overhead Press", before: "Back Squat", in: app)
        let doneButton = app.buttons["DoneReorderExercisesButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.tap()

        assertActiveWorkoutExerciseOrder(
            ["Overhead Press", "Back Squat", "Bench Press", "Conventional Deadlift"],
            in: app
        )
    }

    @MainActor
    func testWorkoutNotesScrollsAboveKeyboardToolbarWhenFocused() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        let notesField = app.textFields["How did this session feel? Any notes for next time..."]
        for _ in 0..<6 where !notesField.exists || !notesField.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        notesField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let doneButton = app.buttons["DismissKeyboardButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        XCTAssertLessThan(notesField.frame.maxY, doneButton.frame.minY - 8)
    }

    @MainActor
    func testExerciseNotesScrollsAboveKeyboardToolbarWhenFocused() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addBenchPress(in: app)
        dismissKeyboardIfNeeded(in: app)

        let notesField = app.textFields["ExerciseNotesField-0"]
        for _ in 0..<6 where !notesField.exists || !notesField.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        notesField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let doneButton = app.buttons["DismissKeyboardButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        XCTAssertLessThan(notesField.frame.maxY, doneButton.frame.minY - 8)
    }

    @MainActor
    func testCompletedWorkoutCanBeOpenedFromWorkoutAndExerciseHistory() {
        let app = makeApp()
        app.launch()

        createCompletedBenchWorkout(in: app, title: "Push History")

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["WorkoutHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Done"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts["Push History"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["185 x 5 @ 8"].exists)
    }

    @MainActor
    func testActiveWorkoutHistorySeparatesSameNameDifferentEquipment() {
        let app = makeApp()
        app.launch()

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileExerciseLibraryLink"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3))
        createExercise(name: "Variant Bench", equipment: "Barbell", muscle: "Chest", in: app)
        createExercise(name: "Variant Bench", equipment: "Dumbbell", muscle: "Chest", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        createCompletedWorkout(
            exerciseButtonLabel: "Variant Bench, Barbell • Chest",
            title: "Barbell Variant",
            weight: "185",
            reps: "5",
            rpe: "8",
            in: app
        )
        createCompletedWorkout(
            exerciseButtonLabel: "Variant Bench, Dumbbell • Chest",
            title: "Dumbbell Variant",
            weight: "70",
            reps: "8",
            rpe: "7",
            in: app
        )

        app.buttons["WorkoutTab"].tap()
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addExercise("Variant Bench, Dumbbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)
        app.buttons["ExerciseHistoryButton-0"].tap()

        XCTAssertTrue(app.staticTexts["Dumbbell Variant"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Barbell Variant"].exists)
    }

    @MainActor
    func testStartingFromPastWorkoutCopiesSetsAsIncomplete() {
        let app = makeApp()
        app.launch()

        createCompletedBenchWorkout(in: app, title: "Past Push")

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.buttons["PastWorkoutButton-0"].waitForExistence(timeout: 3))
        app.buttons["PastWorkoutButton-0"].tap()

        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["WorkoutTitle"].value as? String, "Past Push")
        XCTAssertEqual(app.textFields["SetWeightField-0-0"].value as? String, "185")
        XCTAssertEqual(app.textFields["SetRepsField-0-0"].value as? String, "5")
        XCTAssertTrue(app.buttons["SetCompletionButton-0-0"].exists)
        XCTAssertEqual(app.buttons["SetCompletionButton-0-0"].label, "Mark set complete")
    }

    @MainActor
    func testCompletingClonedSetWhileWeightFieldIsFocusedCommitsPlaceholders() {
        assertCompletingClonedSetCommitsPlaceholdersAfterFocusing(fieldIdentifier: "SetWeightField-0-0")
    }

    @MainActor
    func testCompletingClonedSetWhileRPEFieldIsFocusedCommitsPlaceholders() {
        assertCompletingClonedSetCommitsPlaceholdersAfterFocusing(fieldIdentifier: "SetRPEField-0-0")
    }

    @MainActor
    func testClearingCompletedWeightRemovesLoggedWeight() {
        assertClearingCompletedSetField(
            fieldIdentifier: "SetWeightField-0-0",
            expectedHistorySummary: "- x 5 @ 8"
        )
    }

    @MainActor
    func testClearingCompletedRPERemovesLoggedRPE() {
        assertClearingCompletedSetField(
            fieldIdentifier: "SetRPEField-0-0",
            expectedHistorySummary: "185 x 5"
        )
    }

    @MainActor
    func testExerciseHistorySummaryUsesAvailableContentWidth() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addExercise("Bench Press, Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)
        app.buttons["WorkoutTab"].tap()

        let firstSetCompletionButton = app.buttons["SetCompletionButton-0-0"]
        XCTAssertTrue(firstSetCompletionButton.waitForExistence(timeout: 3))
        firstSetCompletionButton.tap()
        openFinishWorkoutSheet(in: app)
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["SaveWorkoutButton"].tap()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        app.staticTexts["Bench Press"].tap()

        let completedSetsCard = app.otherElements["ExerciseHistoryCompletedSetsCard"]
        XCTAssertTrue(completedSetsCard.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(completedSetsCard.frame.width, app.frame.width - 40)
    }

    @MainActor
    func testSettingsWeightUnitConversionRoundsDisplayedWorkoutValues() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addBenchPress(in: app)
        fillFirstBenchSet(in: app)
        dismissKeyboardIfNeeded(in: app)

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileSettingsLink"].tap()
        XCTAssertTrue(app.segmentedControls["WeightUnitPicker"].waitForExistence(timeout: 3))
        app.segmentedControls["WeightUnitPicker"].buttons["Kilograms"].tap()

        app.buttons["WorkoutTab"].tap()
        XCTAssertEqual(app.textFields["SetWeightField-0-0"].value as? String, "83.91")
    }

    @MainActor
    func testSettingsShowsAccountShellAndDeleteAccountPlaceholder() {
        let app = makeApp()
        app.launchArguments.append("--uitest-force-signed-out-auth")
        app.launch()

        app.buttons["ProfileTab"].tap()
        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))
        app.buttons["ProfileSettingsLink"].tap()

        XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sync Status"].exists)
        XCTAssertTrue(app.staticTexts["Local only"].exists)
        XCTAssertTrue(app.staticTexts["Cloud sync is not configured yet."].exists)
        XCTAssertTrue(app.buttons["SettingsDeleteAccountRow"].exists)

        app.buttons["SettingsDeleteAccountRow"].tap()

        XCTAssertTrue(app.staticTexts["SettingsDeleteAccountPlaceholder"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Account deletion is not available yet."].exists)
        let placeholderMessage = "This release still stores your workouts locally. Account deletion will be available before release after cloud data deletion is connected."
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", placeholderMessage)).firstMatch.exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
    }

    @MainActor
    func testSignedOutProfileShowsOptionalAuthAndWorkoutStillWorks() {
        let app = makeApp()
        app.launchArguments.append("--uitest-force-signed-out-auth")
        app.launch()

        app.buttons["ProfileTab"].tap()
        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["ProfileAccountTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["ProfileAccountTitle"].label, "Local lifting log")
        XCTAssertTrue(app.staticTexts["ProfileAccountSubtitle"].label.contains("workouts backed up"))
        XCTAssertTrue(app.buttons["ProfileSignInButton"].exists)

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.buttons["StartBlankWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testExerciseLibraryCreateEditAndRemoveCustomExercise() {
        let app = makeApp()
        app.launch()

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileExerciseLibraryLink"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3))

        app.buttons["CreateExerciseButton"].tap()
        XCTAssertTrue(app.navigationBars["Create Exercise"].waitForExistence(timeout: 3))
        app.textFields["ExerciseNameField"].tap()
        app.textFields["ExerciseNameField"].typeText("Aardvark Row")
        selectPickerValue(identifier: "ExercisePrimaryMuscleGroupPicker", value: "Upper Back", in: app)
        app.buttons["ExerciseEditorSaveButton"].tap()

        XCTAssertTrue(app.buttons["ExerciseLibraryRow-Aardvark Row-Barbell"].waitForExistence(timeout: 3))
        app.buttons["ExerciseLibraryRow-Aardvark Row-Barbell"].tap()
        XCTAssertTrue(app.navigationBars["Edit Exercise"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["ExerciseNameField"], with: "Aardvark Paused Row")
        app.buttons["ExerciseEditorSaveButton"].tap()

        XCTAssertTrue(app.buttons["ExerciseLibraryRow-Aardvark Paused Row-Barbell"].waitForExistence(timeout: 3))
        app.buttons["ExerciseLibraryRow-Aardvark Paused Row-Barbell"].swipeLeft()
        app.buttons["Remove"].tap()
        XCTAssertFalse(app.buttons["ExerciseLibraryRow-Aardvark Paused Row-Barbell"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testExerciseLibraryAllowsSameNameWithDifferentEquipmentAndRejectsExactDuplicate() {
        let app = makeApp()
        app.launch()

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileExerciseLibraryLink"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3))

        createExercise(name: "Variant Press", equipment: "Barbell", muscle: "Chest", in: app)
        createExercise(name: "Variant Press", equipment: "Dumbbell", muscle: "Chest", in: app)

        app.buttons["CreateExerciseButton"].tap()
        XCTAssertTrue(app.navigationBars["Create Exercise"].waitForExistence(timeout: 3))
        app.textFields["ExerciseNameField"].tap()
        app.textFields["ExerciseNameField"].typeText("Variant Press")
        selectPickerValue(identifier: "ExerciseEquipmentPicker", value: "Barbell", in: app)
        selectPickerValue(identifier: "ExercisePrimaryMuscleGroupPicker", value: "Chest", in: app)
        app.buttons["ExerciseEditorSaveButton"].tap()

        XCTAssertTrue(app.staticTexts["An active exercise with that name and equipment already exists."].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3))

        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("Variant Press")
        XCTAssertTrue(app.buttons["ExerciseLibraryRow-Variant Press-Barbell"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ExerciseLibraryRow-Variant Press-Dumbbell"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDiskBackedWorkoutSurvivesAppRelaunch() {
        let app = makeDiskBackedResetApp()
        app.launch()

        createCompletedBenchWorkout(in: app, title: "Relaunch Push")
        app.terminate()

        let relaunchedApp = makeDiskBackedApp()
        relaunchedApp.launch()
        relaunchedApp.buttons["HistoryTab"].tap()

        XCTAssertTrue(relaunchedApp.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        relaunchedApp.buttons["WorkoutHistoryButton-0"].tap()
        XCTAssertTrue(relaunchedApp.staticTexts["Relaunch Push"].waitForExistence(timeout: 3))
        XCTAssertTrue(relaunchedApp.staticTexts["Bench Press"].exists)
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-in-memory-store"]
        app.terminate()
        return app
    }

    @MainActor
    private func makeDiskBackedResetApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-persistent-store"]
        return app
    }

    @MainActor
    private func makeDiskBackedApp() -> XCUIApplication {
        XCUIApplication()
    }

    @MainActor
    private func openWorkoutOptions(in app: XCUIApplication) {
        let optionsButton = app.buttons["WorkoutOptionsButton"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 3))
        optionsButton.tap()
    }

    @MainActor
    private func openFinishWorkoutSheet(in app: XCUIApplication) {
        openWorkoutOptions(in: app)
        let finishButton = app.buttons["Finish Workout"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 3))
        for _ in 0..<2 {
            finishButton.tap()
            if app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 1)
                || app.buttons["KeepGoingButton"].waitForExistence(timeout: 1) {
                return
            }
        }
    }

    @MainActor
    private func createCompletedBenchWorkout(in app: XCUIApplication, title: String) {
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["WorkoutTitle"], with: title)
        addBenchPress(in: app)
        fillFirstBenchSet(in: app)
        app.buttons["SetCompletionButton-0-0"].tap()
        dismissKeyboardIfNeeded(in: app)
        openFinishWorkoutSheet(in: app)
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
        for _ in 0..<2 {
            app.buttons["SaveWorkoutButton"].tap()
            if app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 3) {
                return
            }
        }
        XCTAssertTrue(app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 1))
    }

    @MainActor
    private func createCompletedWorkout(
        exerciseButtonLabel: String,
        title: String,
        weight: String,
        reps: String,
        rpe: String,
        in app: XCUIApplication
    ) {
        app.buttons["WorkoutTab"].tap()
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["WorkoutTitle"], with: title)
        addExercise(exerciseButtonLabel, in: app)
        app.textFields["SetWeightField-0-0"].tap()
        app.textFields["SetWeightField-0-0"].typeText(weight)
        app.textFields["SetRepsField-0-0"].tap()
        app.textFields["SetRepsField-0-0"].typeText(reps)
        app.textFields["SetRPEField-0-0"].tap()
        app.textFields["SetRPEField-0-0"].typeText(rpe)
        app.buttons["SetCompletionButton-0-0"].tap()
        dismissKeyboardIfNeeded(in: app)
        openFinishWorkoutSheet(in: app)
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["SaveWorkoutButton"].tap()
        XCTAssertTrue(app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func assertCompletingClonedSetCommitsPlaceholdersAfterFocusing(fieldIdentifier: String) {
        let app = makeApp()
        app.launch()

        createCompletedBenchWorkout(in: app, title: "Focused Clone")

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.buttons["PastWorkoutButton-0"].waitForExistence(timeout: 3))
        app.buttons["PastWorkoutButton-0"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        app.textFields[fieldIdentifier].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["SetCompletionButton-0-0"].tap()
        dismissKeyboardIfNeeded(in: app)

        openFinishWorkoutSheet(in: app)
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["SaveWorkoutButton"].tap()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts["185 x 5 @ 8"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func assertClearingCompletedSetField(fieldIdentifier: String, expectedHistorySummary: String) {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addBenchPress(in: app)
        fillFirstBenchSet(in: app)
        app.buttons["SetCompletionButton-0-0"].tap()

        replaceText(in: app.textFields[fieldIdentifier], with: "")
        dismissKeyboardIfNeeded(in: app)

        openFinishWorkoutSheet(in: app)
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["SaveWorkoutButton"].tap()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts[expectedHistorySummary].waitForExistence(timeout: 3))
    }

    @MainActor
    private func addBenchPress(in app: XCUIApplication) {
        addExercise("Bench Press, Barbell • Chest", in: app)
        XCTAssertTrue(app.textFields["SetWeightField-0-0"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func fillFirstBenchSet(in app: XCUIApplication) {
        app.textFields["SetWeightField-0-0"].tap()
        app.textFields["SetWeightField-0-0"].typeText("185")
        app.textFields["SetRepsField-0-0"].tap()
        app.textFields["SetRepsField-0-0"].typeText("5")
        app.textFields["SetRPEField-0-0"].tap()
        app.textFields["SetRPEField-0-0"].typeText("8")
    }

    @MainActor
    private func addExercise(_ exerciseButtonLabel: String, in app: XCUIApplication) {
        let addButton = app.buttons["AddExerciseButton"]

        for _ in 0..<8 {
            if addButton.exists && addButton.isHittable {
                addButton.tap()
                if app.navigationBars["Add Exercise"].waitForExistence(timeout: 1) {
                    for _ in 0..<8 {
                        let exerciseButton = app.buttons[exerciseButtonLabel]
                        if exerciseButton.exists && exerciseButton.isHittable {
                            exerciseButton.tap()
                            return
                        }

                        app.swipeUp()
                    }

                    XCTFail("Could not find exercise button \(exerciseButtonLabel)")
                    return
                }
            }

            app.swipeUp()
        }

        XCTFail("Could not present Add Exercise sheet")
    }

    @MainActor
    private func assertActiveWorkoutExerciseOrder(_ expectedNames: [String], in app: XCUIApplication) {
        for (index, expectedName) in expectedNames.enumerated() {
            let header = app.buttons["ExerciseHeader-\(index)"]
            XCTAssertTrue(header.waitForExistence(timeout: 3))
            XCTAssertTrue(
                header.label.contains(expectedName),
                "Expected ExerciseHeader-\(index) to contain \(expectedName), got \(header.label)"
            )
        }
    }

    @MainActor
    private func moveReorderExercise(named sourceName: String, before destinationName: String, in app: XCUIApplication) {
        let list = reorderExercisesList(in: app)
        XCTAssertTrue(list.exists)

        for _ in 0..<2 {
            let sourceRow = reorderExerciseRow(named: sourceName, in: app)
            let destinationRow = reorderExerciseRow(named: destinationName, in: app)

            XCTAssertTrue(sourceRow.waitForExistence(timeout: 3))
            XCTAssertTrue(destinationRow.waitForExistence(timeout: 3))

            if sourceRow.frame.minY < destinationRow.frame.minY {
                return
            }

            let destinationY = max(destinationRow.frame.minY - 12, list.frame.minY + 1)
            let sourceCoordinate = sourceRow.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
            let destinationCoordinate = sourceRow.coordinate(
                withNormalizedOffset: CGVector(
                    dx: 0.92,
                    dy: (destinationY - sourceRow.frame.minY) / sourceRow.frame.height
                )
            )
            sourceCoordinate.press(forDuration: 1.0, thenDragTo: destinationCoordinate)
        }

        let sourceRow = reorderExerciseRow(named: sourceName, in: app)
        let destinationRow = reorderExerciseRow(named: destinationName, in: app)
        XCTAssertLessThan(sourceRow.frame.minY, destinationRow.frame.minY)
    }

    @MainActor
    private func waitForReorderExercisesList(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let collectionView = app.collectionViews["ReorderExercisesList"]
        let table = app.tables["ReorderExercisesList"]

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if collectionView.exists || table.exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        if collectionView.exists || table.exists {
            return true
        }

        XCTFail("ReorderExercisesList did not appear as a collection view or table")
        return false
    }

    @MainActor
    private func reorderExercisesList(in app: XCUIApplication) -> XCUIElement {
        let collectionView = app.collectionViews["ReorderExercisesList"]
        if collectionView.exists {
            return collectionView
        }

        return app.tables["ReorderExercisesList"]
    }

    @MainActor
    private func reorderExerciseRow(named name: String, in app: XCUIApplication) -> XCUIElement {
        reorderExercisesList(in: app)
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", name))
            .firstMatch
    }

    @MainActor
    private func dismissKeyboardIfNeeded(in app: XCUIApplication) {
        if app.keyboards.firstMatch.waitForExistence(timeout: 1) {
            app.buttons["DismissKeyboardButton"].tap()
        }
    }

    @MainActor
    private func waitForElement(_ element: XCUIElement, maxYOrigin: CGFloat, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.frame.minY <= maxYOrigin {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return element.exists && element.frame.minY <= maxYOrigin
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with text: String) {
        if let existingText = field.value as? String, !existingText.isEmpty {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            field.typeKey("a", modifierFlags: .command)
            let deleteText = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingText.count + 1)
            field.typeText(deleteText)
        } else {
            field.tap()
        }
        field.typeText(text)
    }

    @MainActor
    private func createExercise(name: String, equipment: String, muscle: String, in app: XCUIApplication) {
        app.buttons["CreateExerciseButton"].tap()
        XCTAssertTrue(app.navigationBars["Create Exercise"].waitForExistence(timeout: 3))
        app.textFields["ExerciseNameField"].tap()
        app.textFields["ExerciseNameField"].typeText(name)
        selectPickerValue(identifier: "ExerciseEquipmentPicker", value: equipment, in: app)
        selectPickerValue(identifier: "ExercisePrimaryMuscleGroupPicker", value: muscle, in: app)
        app.buttons["ExerciseEditorSaveButton"].tap()
    }

    @MainActor
    private func selectPickerValue(identifier: String, value: String, in app: XCUIApplication) {
        let picker = app.buttons[identifier]
        if picker.waitForExistence(timeout: 1) {
            picker.tap()
            app.buttons[value].tap()
            return
        }

        let segmentedPicker = app.segmentedControls[identifier]
        if segmentedPicker.waitForExistence(timeout: 1) {
            segmentedPicker.buttons[value].tap()
            return
        }

        let staticValue = app.staticTexts[value]
        XCTAssertTrue(staticValue.waitForExistence(timeout: 3))
        staticValue.tap()
    }
}
