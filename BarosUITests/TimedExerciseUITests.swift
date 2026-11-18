import XCTest

/// Typing a time into a set, which only the keyboard and field can show.
@MainActor
final class TimedExerciseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTimeFieldFormatsTypedDigitsAndTheLoggedTimeReachesHistory() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-in-memory-store", "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-disable-animations",
            "--uitest-seed-timed-exercises", "--uitest-seed-timed-active-workout",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitToExist(timeout: 8))

        // A timed exercise shows Time where reps would be, with last time's value beside it.
        let time = app.textFields["SetTimeField-0-0"]
        XCTAssertTrue(time.waitToExist(timeout: 3))
        XCTAssertFalse(app.textFields["SetRepsField-0-0"].exists)
        XCTAssertEqual(app.buttons["SetPreviousValue-0-0"].label, "Previous: 1:00")
        XCTAssertEqual(app.buttons["SetPreviousValue-1-0"].label, "Previous: 70 × 1:30")
        attachScreenshot("Timed exercises before logging", app: app)

        // Digits fill in from the right, and deleting one re-flows the rest.
        time.tap()
        time.typeText("130")
        XCTAssertTrue(waitForValue(time, "1:30"))
        attachScreenshot("Typing a time", app: app)
        time.typeText("5")
        XCTAssertTrue(waitForValue(time, "13:05"))
        time.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(waitForValue(time, "1:30"))

        app.buttons["SetCompletionButton-0-0"].tap()
        XCTAssertTrue(waitUntil(timeout: 3) { app.buttons["SetCompletionButton-0-0"].label == "Mark set incomplete" })
        XCTAssertEqual(time.value as? String, "1:30")

        // An empty timed set completes with the time from the set above.
        app.buttons["SetCompletionButton-0-1"].tap()
        XCTAssertTrue(waitForValue(app.textFields["SetTimeField-0-1"], "1:30"))

        // Seconds past 59 carry into minutes when the field is left.
        let carry = app.textFields["SetTimeField-1-0"]
        app.revealAboveWorkoutActions(carry)
        app.textFields["SetWeightField-1-0"].tap()
        app.textFields["SetWeightField-1-0"].typeText("80")
        carry.tap()
        carry.typeText("90")
        app.buttons["SetCompletionButton-1-0"].tap()
        XCTAssertTrue(waitForValue(carry, "1:30"))
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

        // Editing the finished workout uses the same time entry.
        app.buttons["EditWorkoutButton"].tap()
        let edited = app.textFields["HistorySetTimeField-0-0"]
        XCTAssertTrue(edited.waitToExist(timeout: 3))
        XCTAssertEqual(edited.value as? String, "1:30")
        XCTAssertFalse(app.textFields["HistorySetRepsField-0-0"].exists)
        // Tap past the centered text so the caret lands at its end.
        edited.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        edited.typeText("0")
        XCTAssertTrue(waitForValue(edited, "13:00"))
        attachScreenshot("Editing a timed set", app: app)
        app.buttons["SaveCompletedWorkoutEditButton"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { logged.exists && logged.label == "Set 1, 13 minutes" })
    }

    private func waitForValue(_ field: XCUIElement, _ value: String) -> Bool {
        waitUntil(timeout: 3) { field.exists && field.value as? String == value }
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
