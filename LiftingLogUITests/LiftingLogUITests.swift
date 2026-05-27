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

        app.buttons["Finish"].tap()
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
        app.buttons["Bench Press, Strength • Barbell • Chest"].tap()

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
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
    }

    @MainActor
    func testAddingExerciseScrollsNewExerciseToTop() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("Back Squat, Strength • Barbell • Quads", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("Bench Press, Strength • Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)

        let addedExerciseHeader = app.buttons["ExerciseHeader-1"]
        XCTAssertTrue(addedExerciseHeader.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(addedExerciseHeader.frame.minY, 150)
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
    func testExerciseHistorySummaryUsesAvailableContentWidth() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addExercise("Bench Press, Strength • Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)
        app.buttons["WorkoutTab"].tap()

        let firstSetCompletionButton = app.buttons["SetCompletionButton-0-0"]
        XCTAssertTrue(firstSetCompletionButton.waitForExistence(timeout: 3))
        firstSetCompletionButton.tap()
        app.buttons["FinishWorkoutButton"].tap()
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
        app.textFields["ExercisePrimaryMuscleField"].tap()
        app.textFields["ExercisePrimaryMuscleField"].typeText("Back")
        app.buttons["ExerciseEditorSaveButton"].tap()

        XCTAssertTrue(app.buttons["ExerciseLibraryRow-Aardvark Row"].waitForExistence(timeout: 3))
        app.buttons["ExerciseLibraryRow-Aardvark Row"].tap()
        XCTAssertTrue(app.navigationBars["Edit Exercise"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["ExerciseNameField"], with: "Aardvark Paused Row")
        app.buttons["ExerciseEditorSaveButton"].tap()

        XCTAssertTrue(app.buttons["ExerciseLibraryRow-Aardvark Paused Row"].waitForExistence(timeout: 3))
        app.buttons["ExerciseLibraryRow-Aardvark Paused Row"].swipeLeft()
        app.buttons["Remove"].tap()
        XCTAssertFalse(app.buttons["ExerciseLibraryRow-Aardvark Paused Row"].waitForExistence(timeout: 1))
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
    private func createCompletedBenchWorkout(in app: XCUIApplication, title: String) {
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["WorkoutTitle"], with: title)
        addBenchPress(in: app)
        fillFirstBenchSet(in: app)
        app.buttons["SetCompletionButton-0-0"].tap()
        dismissKeyboardIfNeeded(in: app)
        app.buttons["FinishWorkoutButton"].tap()
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
    private func addBenchPress(in app: XCUIApplication) {
        addExercise("Bench Press, Strength • Barbell • Chest", in: app)
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
                    app.buttons[exerciseButtonLabel].tap()
                    return
                }
            }

            app.swipeUp()
        }

        XCTFail("Could not present Add Exercise sheet")
    }

    @MainActor
    private func dismissKeyboardIfNeeded(in app: XCUIApplication) {
        if app.keyboards.firstMatch.waitForExistence(timeout: 1) {
            app.buttons["DismissKeyboardButton"].tap()
        }
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let existingText = field.value as? String, !existingText.isEmpty {
            let deleteText = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingText.count)
            field.typeText(deleteText)
        }
        field.typeText(text)
    }
}
