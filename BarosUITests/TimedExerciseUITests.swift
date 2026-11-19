import XCTest

/// Choosing a set's time from the wheels that are a time cell's keyboard, which only the UI can show.
@MainActor
final class TimedExerciseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTimePickerSetsATimeAndTheLoggedTimeReachesHistory() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-in-memory-store", "--uitest-enable-rpe", "--uitest-force-signed-out-auth",
            "--uitest-reset-app-appearance", "--uitest-reset-exercise-picker-sort",
            "--uitest-reset-home-ring-period", "--uitest-reset-signed-out-reminder",
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

        // The wheels are the cell's keyboard. They open on last time's value
        // and mark the set they belong to. The time follows them as they settle.
        time.tap()
        XCTAssertTrue(wheel("SetTimeMinutesWheel", in: app).waitToExist(timeout: 3))
        XCTAssertEqual(wheel("SetTimeMinutesWheel", in: app).value as? String, "1")
        XCTAssertTrue(waitUntil(timeout: 3) { time.isSelected })
        wheel("SetTimeSecondsWheel", in: app).adjust(toPickerWheelValue: "30")
        XCTAssertTrue(waitForValue(time, "1 minute, 30 seconds"))
        attachScreenshot("Choosing a time", app: app)
        app.buttons["DismissKeyboardButton"].tap()
        XCTAssertTrue(wheel("SetTimeMinutesWheel", in: app).waitToDisappear(timeout: 3))
        XCTAssertFalse(time.isSelected)
        XCTAssertEqual(time.value as? String, "1 minute, 30 seconds")

        app.buttons["SetCompletionButton-0-0"].tap()
        XCTAssertTrue(waitUntil(timeout: 3) { app.buttons["SetCompletionButton-0-0"].label == "Mark set incomplete" })
        XCTAssertEqual(time.value as? String, "1 minute, 30 seconds")

        // An empty timed set completes with the time from the set above.
        app.buttons["SetCompletionButton-0-1"].tap()
        XCTAssertTrue(waitForValue(app.buttons["SetTimeField-0-1"], "1 minute, 30 seconds"))

        // Typing a weight and then opening the wheels keeps the weight. The
        // bar above the wheels offers RPE as the keyboard's does; choosing
        // one keeps the time shown and completes the set.
        let carry = app.buttons["SetTimeField-1-0"]
        app.revealAboveWorkoutActions(carry)
        app.textFields["SetWeightField-1-0"].tap()
        app.textFields["SetWeightField-1-0"].typeText("80")
        // Typing settles the list under the keyboard; a tap on a moving list
        // only stops it.
        var lastFrame = CGRect.null
        XCTAssertTrue(waitUntil(timeout: 3) {
            defer { lastFrame = carry.frame }
            return carry.isHittable && carry.frame == lastFrame
        })
        carry.tap()
        XCTAssertTrue(app.buttons["RPEToolbarButton"].waitToExist(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 3) { carry.isSelected })
        XCTAssertTrue(
            waitUntil(timeout: 3) { carry.frame.maxY <= app.buttons["DismissKeyboardButton"].frame.minY },
            "The set stays in view above the wheels and their bar"
        )
        app.buttons["RPEToolbarButton"].tap()
        XCTAssertTrue(app.buttons["RPEChip-8"].waitToExist(timeout: 3))
        attachScreenshot("Time picker with RPE", app: app)
        app.buttons["RPEChip-8"].tap()
        XCTAssertTrue(waitForValue(carry, "1 minute, 30 seconds"))
        XCTAssertEqual(app.textFields["SetWeightField-1-0"].value as? String, "80")
        XCTAssertTrue(waitUntil(timeout: 3) { app.buttons["SetCompletionButton-1-0"].label == "Mark set incomplete" })
        XCTAssertTrue(app.buttons["SetRPEBadge-1-0"].exists)
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
            "Set 1, 80 pounds, 1 minute, 30 seconds, RPE 8"
        )
        attachScreenshot("Workout history with timed sets", app: app)

        // Editing the finished workout uses the same wheels, opened on the set's time.
        app.buttons["EditWorkoutButton"].tap()
        let edited = app.buttons["HistorySetTimeField-0-0"]
        XCTAssertTrue(edited.waitToExist(timeout: 3))
        XCTAssertEqual(edited.value as? String, "1 minute, 30 seconds")
        XCTAssertFalse(app.textFields["HistorySetRepsField-0-0"].exists)
        edited.tap()
        XCTAssertTrue(wheel("SetTimeMinutesWheel", in: app).waitToExist(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 3) { edited.isSelected })
        XCTAssertTrue(
            waitUntil(timeout: 3) { edited.frame.maxY <= app.buttons["DoneSetTimeButton"].frame.minY },
            "The list scrolls the set clear of the wheels and their bar"
        )
        wheel("SetTimeMinutesWheel", in: app).adjust(toPickerWheelValue: "13")
        wheel("SetTimeSecondsWheel", in: app).adjust(toPickerWheelValue: "0")
        attachScreenshot("Editing a timed set", app: app)
        app.buttons["DoneSetTimeButton"].tap()
        XCTAssertTrue(waitForValue(edited, "13 minutes"))
        app.buttons["SaveCompletedWorkoutEditButton"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { logged.exists && logged.label == "Set 1, 13 minutes" })
    }

    private func wheel(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.pickers["SetTimeWheels"].pickerWheels.element(boundBy: identifier == "SetTimeMinutesWheel" ? 0 : 1)
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
