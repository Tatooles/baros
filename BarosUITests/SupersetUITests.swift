import XCTest

@MainActor
final class SupersetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMenuGroupsExercisesAndCheckingASetChecksTheRound() {
        let app = launch()
        let labels = app.descendants(matching: .any).matching(identifier: "SupersetLabel")
        XCTAssertEqual(labels.count, 0)

        openMenu(1, in: app)
        XCTAssertTrue(app.buttons["JoinPreviousSupersetButton-1"].exists)
        XCTAssertTrue(app.buttons["SupersetWithNextButton-1"].exists)
        XCTAssertFalse(app.buttons["RemoveFromSupersetButton-1"].exists)
        attachScreenshot("Menu before grouping", app: app)
        app.buttons["JoinPreviousSupersetButton-1"].tap()
        XCTAssertTrue(labels.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(labels.firstMatch.label, "Superset of 2 exercises")

        // Only the actions that still apply are offered.
        openMenu(0, in: app)
        XCTAssertFalse(app.buttons["JoinPreviousSupersetButton-0"].exists)
        XCTAssertFalse(app.buttons["SupersetWithNextButton-0"].exists)
        XCTAssertTrue(app.buttons["RemoveFromSupersetButton-0"].exists)
        attachScreenshot("Menu in a superset", app: app)
        app.buttons["RemoveFromSupersetButton-0"].tap()
        XCTAssertTrue(waitForAbsence(labels.firstMatch))

        openMenu(0, in: app)
        app.buttons["SupersetWithNextButton-0"].tap()
        XCTAssertTrue(labels.firstMatch.waitForExistence(timeout: 3))

        // Bench Press has two checked sets; checking Pull-Up's third set checks Bench's third.
        let partner = app.buttons["SetCompletionButton-0-2"]
        XCTAssertEqual(partner.label, "Mark set complete")
        let tapped = app.buttons["SetCompletionButton-1-2"]
        for _ in 0..<4 where !tapped.isHittable { app.swipeUp() }
        tapped.tap()
        XCTAssertTrue(waitForLabel(tapped, "Mark set incomplete"))
        XCTAssertTrue(waitForLabel(partner, "Mark set incomplete"))
        XCTAssertEqual(app.textFields["SetWeightField-0-2"].value as? String, "135", "The partner fills from the set above")
        attachScreenshot("Round checked", app: app)

        // Unchecking a set unchecks only that set.
        tapped.tap()
        XCTAssertTrue(waitForLabel(tapped, "Mark set complete"))
        XCTAssertEqual(partner.label, "Mark set incomplete")
    }

    func testEditWorkoutMovesASupersetAsOneBlockAndCancelKeepsGrouping() {
        let app = launch(seedsSupersets: true)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
        openEditor(in: app)
        let list = app.collectionViews["ReorderExercisesList"]
        XCTAssertEqual(list.cells.count, 4, "Single, pair, giant set and Add Exercises")
        attachScreenshot("Edit Workout with supersets", app: app)

        // Removing a pair member leaves its partner single, as a draft only.
        app.buttons.matching(NSPredicate(format: "label == %@", "Remove Incline Dumbbell Press")).firstMatch.tap()
        XCTAssertFalse(list.cells.containing(NSPredicate(format: "label == %@", "Incline Dumbbell Press")).firstMatch.exists)
        XCTAssertEqual(list.cells.count, 4, "Pull-Up becomes its own row")
        XCTAssertEqual(list.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 1)
        app.buttons["CancelReorderExercisesButton"].tap()
        XCTAssertTrue(app.buttons["ExerciseHeader-2"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)

        openEditor(in: app)
        drag(cellContaining: "Chest Supported Row", above: "Pull-Up", in: app)
        attachScreenshot("Giant set moved", app: app)
        app.buttons["DoneReorderExercisesButton"].tap()
        let expected = ["Slingshot Pause Bench Press", "Chest Supported Row", "Cable Overhead Triceps Extension",
                        "Single-Arm Cable Lateral Raise", "Pull-Up", "Incline Dumbbell Press"]
        for (index, name) in expected.enumerated() {
            let header = app.buttons["ExerciseHeader-\(index)"]
            XCTAssertTrue(header.waitForExistence(timeout: 3))
            XCTAssertTrue(header.label.contains(name), "\(index): \(header.label)")
        }
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
    }

    /// A partner fills from what's typed in its own set above, even before that field loses focus.
    func testRoundFillsPartnersFromATypedDraftInAnotherExercise() {
        let app = launch(seedsSupersets: true)
        app.buttons["ExerciseHeader-0"].tap()
        let draft = app.textFields["SetWeightField-2-0"]
        draft.tap()
        draft.typeText("100")
        let check = app.buttons["SetCompletionButton-1-1"]
        // The field scrolls above the keyboard first.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: check)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 3), .completed)
        check.tap()
        XCTAssertTrue(waitForLabel(app.buttons["SetCompletionButton-2-1"], "Mark set incomplete"))
        XCTAssertEqual(app.textFields["SetWeightField-2-1"].value as? String, "100")
    }

    // MARK: Helpers

    private func launch(seedsSupersets: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-in-memory-store", "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-seed-long-name-active-workout",
        ] + (seedsSupersets ? ["--uitest-seed-supersets"] : [])
        app.launch()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 8))
        return app
    }

    private func openMenu(_ index: Int, in app: XCUIApplication) {
        let menu = app.buttons["ExerciseMenuButton-\(index)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        for _ in 0..<4 where !menu.isHittable { app.swipeDown() }
        menu.tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-\(index)"].waitForExistence(timeout: 3))
    }

    private func openEditor(in app: XCUIApplication) {
        let edit = app.buttons["ActiveWorkoutEditButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        XCTAssertTrue(app.collectionViews["ReorderExercisesList"].waitForExistence(timeout: 3))
    }

    /// Drags a row by its grip until it sits above the destination row.
    private func drag(cellContaining name: String, above destinationName: String, in app: XCUIApplication) {
        let list = app.collectionViews["ReorderExercisesList"]
        func cell(_ name: String) -> XCUIElement {
            list.cells.containing(NSPredicate(format: "label == %@", name)).firstMatch
        }
        for _ in 0..<2 where cell(name).frame.minY > cell(destinationName).frame.minY {
            let source = cell(name)
            let destination = cell(destinationName)
            let grip = source.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let target = source.coordinate(withNormalizedOffset: CGVector(
                dx: 0.95,
                dy: 0.5 + (destination.frame.minY + 10 - source.frame.midY) / source.frame.height
            ))
            grip.press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)
        }
        XCTAssertLessThan(cell(name).frame.minY, cell(destinationName).frame.minY)
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    private func waitForAbsence(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
