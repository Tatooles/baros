import XCTest

/// Choosing a set's time from the picker sheet, which only the UI can show.
@MainActor
final class TimedExerciseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTimePickerSetsATimeAndTheLoggedTimeReachesHistory() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-in-memory-store", "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-disable-animations",
            "--uitest-seed-timed-exercises", "--uitest-seed-timed-active-workout",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitToExist(timeout: 8))

        // A timed exercise shows Time where reps would be, with last time's value beside it.
        let time = app.buttons["SetTimeField-0-0"]
        XCTAssertTrue(time.waitToExist(timeout: 3))
        XCTAssertFalse(app.textFields["SetRepsField-0-0"].exists)
        XCTAssertEqual(app.buttons["SetPreviousValue-0-0"].label, "Previous: 1:00")
        XCTAssertEqual(app.buttons["SetPreviousValue-1-0"].label, "Previous: 70 × 1:30")
        attachScreenshot("Timed exercises before logging", app: app)

        // The wheels open on last time's value, and nothing is saved until Done.
        time.tap()
        XCTAssertTrue(wheel("SetTimeMinutesWheel", in: app).waitToExist(timeout: 3))
        XCTAssertEqual(wheel("SetTimeMinutesWheel", in: app).value as? String, "1")
        XCTAssertFalse(app.buttons["ClearSetTimeButton"].exists)
        wheel("SetTimeSecondsWheel", in: app).adjust(toPickerWheelValue: "30")
        attachScreenshot("Choosing a time", app: app)
        app.buttons["CancelSetTimeButton"].tap()
        XCTAssertTrue(waitForValue(time, "TIME"), "Cancel leaves the set without a time")

        time.tap()
        wheel("SetTimeSecondsWheel", in: app).adjust(toPickerWheelValue: "30")
        app.buttons["DoneSetTimeButton"].tap()
        XCTAssertTrue(waitForValue(time, "1:30"))

        app.buttons["SetCompletionButton-0-0"].tap()
        XCTAssertTrue(waitUntil(timeout: 3) { app.buttons["SetCompletionButton-0-0"].label == "Mark set incomplete" })
        XCTAssertEqual(time.value as? String, "1:30")

        // An empty timed set completes with the time from the set above.
        app.buttons["SetCompletionButton-0-1"].tap()
        XCTAssertTrue(waitForValue(app.buttons["SetTimeField-0-1"], "1:30"))

        // Typing a weight and then opening the picker keeps the weight.
        let carry = app.buttons["SetTimeField-1-0"]
        app.revealAboveWorkoutActions(carry)
        app.textFields["SetWeightField-1-0"].tap()
        app.textFields["SetWeightField-1-0"].typeText("80")
        carry.tap()
        XCTAssertTrue(app.buttons["DoneSetTimeButton"].waitToExist(timeout: 3))
        app.buttons["DoneSetTimeButton"].tap()
        XCTAssertTrue(waitForValue(carry, "1:30"))
        XCTAssertEqual(app.textFields["SetWeightField-1-0"].value as? String, "80")
        app.buttons["SetCompletionButton-1-0"].tap()
        attachScreenshot("Timed sets logged", app: app)

        app.buttons["FinishWorkoutButton"].tap()
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitToExist(timeout: 3))
        app.buttons["SaveWorkoutButton"].tap()

        app.tabButton(.history).tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitToExist(timeout: 5))
        app.buttons["WorkoutHistoryButton-0"].tap()
        let logged = app.descendants(matching: .any).matching(identifier: "WorkoutHistorySetSummary-0-0").firstMatch
        XCTAssertTrue(logged.waitToExist(timeout: 3))
        XCTAssertEqual(logged.label, "Set 1, 1 minute, 30 seconds")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "WorkoutHistorySetSummary-1-0").firstMatch.label,
            "Set 1, 80 pounds, 1 minute, 30 seconds"
        )
        attachScreenshot("Workout history with timed sets", app: app)

        // Editing the finished workout uses the same picker, opened on the set's time.
        app.buttons["EditWorkoutButton"].tap()
        let edited = app.buttons["HistorySetTimeField-0-0"]
        XCTAssertTrue(edited.waitToExist(timeout: 3))
        XCTAssertEqual(edited.value as? String, "1:30")
        XCTAssertFalse(app.textFields["HistorySetRepsField-0-0"].exists)
        edited.tap()
        XCTAssertTrue(app.buttons["ClearSetTimeButton"].waitToExist(timeout: 3))
        wheel("SetTimeMinutesWheel", in: app).adjust(toPickerWheelValue: "13")
        wheel("SetTimeSecondsWheel", in: app).adjust(toPickerWheelValue: "0")
        attachScreenshot("Editing a timed set", app: app)
        app.buttons["DoneSetTimeButton"].tap()
        XCTAssertTrue(waitForValue(edited, "13:00"))
        app.buttons["SaveCompletedWorkoutEditButton"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { logged.exists && logged.label == "Set 1, 13 minutes" })
    }

    private func wheel(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.pickers[identifier].pickerWheels.firstMatch
    }

    private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        waitUntil(timeout: 3) { element.exists && element.value as? String == value }
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
