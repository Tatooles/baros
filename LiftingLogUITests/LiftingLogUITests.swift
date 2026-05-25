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
    func testExerciseHistorySummaryUsesAvailableContentWidth() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("Bench Press, Strength • Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)
        app.buttons["WorkoutTab"].tap()
        let firstSetCompletionButton = app.buttons["SetCompleteButton-0-0"]
        XCTAssertTrue(firstSetCompletionButton.waitForExistence(timeout: 3))
        firstSetCompletionButton.tap()
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["SaveWorkoutButton"].tap()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Exercises"].tap()
        app.staticTexts["Bench Press"].tap()

        let completedSetsCard = app.otherElements["ExerciseHistoryCompletedSetsCard"]
        XCTAssertTrue(completedSetsCard.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(completedSetsCard.frame.width, app.frame.width - 40)
    }

    @MainActor
    func testWorkoutHistoryDetailOmitsVolumeSection() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("Bench Press, Strength • Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)
        app.buttons["WorkoutTab"].tap()
        let firstSetCompletionButton = app.buttons["SetCompleteButton-0-0"]
        XCTAssertTrue(firstSetCompletionButton.waitForExistence(timeout: 3))
        firstSetCompletionButton.tap()
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["SaveWorkoutButton"].tap()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Workout,")).firstMatch.tap()

        XCTAssertFalse(app.staticTexts["Volume"].exists)
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-in-memory-store"]
        return app
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
}
