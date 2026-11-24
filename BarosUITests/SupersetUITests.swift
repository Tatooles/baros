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
        XCTAssertTrue(labels.firstMatch.waitToExist(timeout: 3))
        XCTAssertEqual(labels.firstMatch.label, "Superset of 2 exercises")

        openMenu(0, in: app)
        XCTAssertFalse(app.buttons["JoinPreviousSupersetButton-0"].exists)
        XCTAssertFalse(app.buttons["SupersetWithNextButton-0"].exists)
        XCTAssertTrue(app.buttons["RemoveFromSupersetButton-0"].exists)
        attachScreenshot("Menu in a superset", app: app)
        app.buttons["RemoveFromSupersetButton-0"].tap()
        XCTAssertTrue(waitForAbsence(labels.firstMatch))

        openMenu(0, in: app)
        app.buttons["SupersetWithNextButton-0"].tap()
        XCTAssertTrue(labels.firstMatch.waitToExist(timeout: 3))

        let partner = app.buttons["SetCompletionButton-0-2"]
        XCTAssertEqual(partner.label, "Mark set complete")
        let tapped = app.buttons["SetCompletionButton-1-2"]
        for _ in 0..<4 where !(tapped.exists && tapped.isHittable) { app.swipeUp() }
        app.revealAboveWorkoutActions(tapped)
        tapped.tap()
        XCTAssertTrue(waitForLabel(tapped, "Mark set incomplete"))
        XCTAssertTrue(waitForLabel(partner, "Mark set incomplete"))
        XCTAssertEqual(app.textFields["SetWeightField-0-2"].value as? String, "135", "The partner fills from the set above")
        attachScreenshot("Round checked", app: app)

        tapped.tap()
        XCTAssertTrue(waitForLabel(tapped, "Mark set complete"))
        XCTAssertEqual(partner.label, "Mark set incomplete")
    }

    func testEditWorkoutMovesASupersetAsOneBlockAndCancelKeepsGrouping() {
        let app = launch(seedsSupersets: true)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
        openEditor(in: app)
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        XCTAssertEqual(exerciseRows(in: app).count, 6)
        attachScreenshot("Edit Workout with supersets", app: app)

        removeSupersetMember("Incline Dumbbell Press", in: app)
        XCTAssertFalse(exerciseRow("Incline Dumbbell Press", in: app).exists)
        XCTAssertEqual(exerciseRows(in: app).count, 5)
        XCTAssertEqual(list.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 1)
        for name in ["Cable Overhead Triceps Extension", "Single-Arm Cable Lateral Raise"] {
            removeSupersetMember(name, in: app)
        }
        XCTAssertEqual(list.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 0)
        app.buttons["CancelReorderExercisesButton"].tap()
        discardChanges(in: app)
        XCTAssertTrue(app.buttons["ExerciseHeader-2"].waitToExist(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)

        openEditor(in: app)
        // The label's grip moves the whole giant set; it stays whole and apart from the pair.
        dragSuperset(at: 1, lastMember: "Single-Arm Cable Lateral Raise", above: "Pull-Up", in: app)
        attachScreenshot("Giant set moved", app: app)
        app.buttons["SaveReorderExercisesButton"].tap()
        let expected = ["Slingshot Pause Bench Press", "Chest Supported Row", "Cable Overhead Triceps Extension",
                        "Single-Arm Cable Lateral Raise", "Pull-Up", "Incline Dumbbell Press"]
        for (index, name) in expected.enumerated() {
            let header = app.buttons["ExerciseHeader-\(index)"]
            XCTAssertTrue(header.waitToExist(timeout: 3))
            XCTAssertTrue(header.label.contains(name), "\(index): \(header.label)")
        }
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
    }

    func testSavingAWorkoutAsATemplateKeepsItsSupersets() {
        let app = launch(seedsSupersets: true)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
        app.buttons["FinishWorkoutButton"].tap()
        let toggle = app.switches["SaveAsTemplateToggle"]
        XCTAssertTrue(toggle.waitToExist(timeout: 3))
        toggle.switches.firstMatch.tap()
        app.buttons["SaveWorkoutButton"].tap()

        XCTAssertTrue(app.staticTexts["HomeTitle"].waitToExist(timeout: 3))
        app.buttons["StartWorkoutButton"].tap()
        XCTAssertTrue(app.buttons["UseTemplateButton"].waitToExist(timeout: 3))
        app.buttons["UseTemplateButton"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "TemplateRow-")).firstMatch
        XCTAssertTrue(row.waitToExist(timeout: 3))
        row.tap()
        XCTAssertTrue(app.buttons["StartFromTemplateButton"].waitToExist(timeout: 3))
        attachScreenshot("Template review with supersets", app: app)
        app.buttons["EditTemplateButton"].tap()
        let name = app.textFields["TemplateNameField"]
        XCTAssertTrue(name.waitToExist(timeout: 3))
        name.tap()
        name.typeText(" Edited\n")
        dragSuperset(at: 0, lastMember: "Incline Dumbbell Press", above: "Bench Press", in: app)
        app.buttons["SaveTemplateButton"].tap()
        XCTAssertTrue(app.staticTexts["TemplateReviewTitle"].waitToExist(timeout: 3))
        XCTAssertTrue(app.staticTexts["TemplateReviewTitle"].label.contains("Edited"))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
        app.buttons["StartFromTemplateButton"].tap()

        XCTAssertTrue(app.textFields["WorkoutTitle"].waitToExist(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
    }

    /// A workout longer than the screen: Add stays reachable at any scroll, and a tapped
    /// joint stays under the finger as a superset label appears or moves above it.
    func testLongWorkoutKeepsAddPinnedAndJointsUnderTheFinger() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-in-memory-store", "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-seed-large-active-workout",
        ]
        app.launch()
        openEditor(in: app)
        let add = app.buttons["EditWorkoutAddExercisesButton"]
        XCTAssertTrue(add.isHittable)
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        list.swipeUp()
        settle()
        XCTAssertTrue(add.isHittable, "Add stays pinned however far the list scrolls")

        // Held still in the autoscroll zone under the navigation bar, a grip neither scrolls
        // the list nor moves its row.
        let top = app.navigationBars["Edit Workout"].frame.maxY
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "ReorderExerciseRow-"))
        func edgeRow() -> XCUIElement? {
            rows.allElementsBoundByIndex.first { $0.isHittable && $0.frame.midY > top + 4 && $0.frame.midY < top + 76 }
        }
        for _ in 0..<3 where edgeRow() == nil {
            let center = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: 40)))
            settle()
        }
        guard let edge = edgeRow() else { return XCTFail("No row in the top autoscroll zone") }
        edge.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).press(forDuration: 1.5)
        XCTAssertFalse(app.buttons["SaveReorderExercisesButton"].isEnabled, "A press alone changes nothing")

        let onScreen = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "SupersetLinkButton-"))
            .allElementsBoundByIndex.filter { $0.isHittable && $0.label.hasPrefix("Link ") && $0.frame.minY > 200 }
        guard onScreen.count >= 2 else { return XCTFail("Fewer than two joints on screen") }
        let joint = app.buttons[onScreen[onScreen.count - 1].identifier]
        let above = app.buttons[onScreen[onScreen.count - 2].identifier]
        let before = joint.frame.midY
        joint.tap()
        XCTAssertTrue(waitForLabelPrefix(joint, "Unlink "))
        settle()
        XCTAssertEqual(joint.frame.midY, before, accuracy: 3, "The scroll makes up for the new label")
        attachScreenshot("Linked in a long workout", app: app)

        // Joining the single above moves the label up instead of adding one.
        let aboveBefore = above.frame.midY
        above.tap()
        XCTAssertTrue(waitForLabelPrefix(above, "Unlink "))
        settle()
        XCTAssertEqual(above.frame.midY, aboveBefore, accuracy: 3, "The scroll makes up for the moved label")
    }

    /// Lets animations finish and the scroll come to rest.
    private func settle() { Thread.sleep(forTimeInterval: 0.8) }

    func testTemplateEditorLinksExercisesAndSaves() {
        let app = launch(seedsSupersets: true)
        app.buttons["FinishWorkoutButton"].tap()
        let toggle = app.switches["SaveAsTemplateToggle"]
        XCTAssertTrue(toggle.waitToExist(timeout: 3))
        toggle.switches.firstMatch.tap()
        app.buttons["SaveWorkoutButton"].tap()
        XCTAssertTrue(app.staticTexts["HomeTitle"].waitToExist(timeout: 3))
        app.buttons["StartWorkoutButton"].tap()
        XCTAssertTrue(app.buttons["UseTemplateButton"].waitToExist(timeout: 3))
        app.buttons["UseTemplateButton"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "TemplateRow-")).firstMatch
        XCTAssertTrue(row.waitToExist(timeout: 3))
        row.tap()
        XCTAssertTrue(app.buttons["EditTemplateButton"].waitToExist(timeout: 3))
        app.buttons["EditTemplateButton"].tap()

        // Linking sits in the same list as the name, with no mode to enter.
        let name = app.textFields["TemplateNameField"]
        XCTAssertTrue(name.waitToExist(timeout: 3))
        name.tap()
        name.typeText(" Linked")

        let joinFirst = app.buttons["SupersetLinkButton-0"]
        XCTAssertTrue(joinFirst.label.hasPrefix("Link "))
        joinFirst.tap()
        XCTAssertTrue(waitForLabelPrefix(joinFirst, "Unlink "))
        XCTAssertTrue((name.value as? String)?.contains("Linked") == true, "Linking keeps the typed name")

        app.buttons["SaveTemplateButton"].tap()
        XCTAssertTrue(app.staticTexts["TemplateReviewTitle"].waitToExist(timeout: 3))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "SupersetLabel").firstMatch.label,
            "Superset of 3 exercises"
        )
    }

    func testRoundFillsPartnersFromATypedDraftInAnotherExercise() {
        let app = launch(seedsSupersets: true)
        app.buttons["ExerciseHeader-0"].tap()
        let draft = app.textFields["SetWeightField-2-0"]
        app.revealAboveWorkoutActions(draft)
        draft.tap()
        draft.typeText("100")
        let check = app.buttons["SetCompletionButton-1-1"]
        XCTAssertTrue(waitUntil(timeout: 3) { check.exists && check.isHittable })
        check.tap()
        XCTAssertTrue(waitForLabel(app.buttons["SetCompletionButton-2-1"], "Mark set incomplete"))
        XCTAssertEqual(app.textFields["SetWeightField-2-1"].value as? String, "100")
    }

    func testLinkedCompletionDoesNotReplaceRejectedPartnerReps() {
        let app = launch(seedsSupersets: true)
        app.buttons["ExerciseHeader-0"].tap()
        let reps = app.textFields["SetRepsField-2-0"]
        app.revealAboveWorkoutActions(reps)
        reps.tap()
        reps.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "1001")
        app.buttons["SetCompletionButton-1-0"].tap()
        XCTAssertTrue(waitForLabel(app.buttons["SetCompletionButton-2-0"], "Mark set incomplete"))
        XCTAssertEqual(app.textFields["SetRepsField-2-0"].value as? String, "REPS")
        attachScreenshot("Rejected partner reps stay empty", app: app)
    }

    func testSupersetReorderDoesNotOscillateWhileHovering() { runHoverProbe(grouped: true) }
    func testNormalReorderDoesNotOscillateWhileHovering() { runHoverProbe(grouped: false) }

    private func runHoverProbe(grouped: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-in-memory-store", "--uitest-force-signed-out-auth",
            "--uitest-reset-app-appearance", "--uitest-skip-first-run-experience",
            "--uitest-seed-long-name-active-workout", "--uitest-reorder-stability-probe", "--uitest-reorder-minimal"] + (grouped ? ["--uitest-seed-supersets"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["ActiveWorkoutEditButton"].waitToExist(timeout: 8))
        openEditor(in: app)
        let source = exerciseRow("Slingshot Pause Bench Press", in: app)
        let grip = source.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let target = grip.withOffset(CGVector(dx: 0, dy: 150))
        grip.press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 4)
        attachScreenshot("Reorder after hovering", app: app)
        let label = app.staticTexts["ReorderStabilityProbe"].value as? String ?? ""
        print("Native reorder slot changes: \(label)")
        let moves = Int(label) ?? -1
        XCTAssertGreaterThanOrEqual(moves, 0, "The probe must report its measurement")
        XCTAssertLessThan(moves, 6, "One row boundary must not repeatedly rearrange cells")
        let partner = exerciseRow("Pull-Up", in: app)
        if source.frame.minY < partner.frame.minY {
            let sourceGrip = source.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let belowPartner = sourceGrip.withOffset(CGVector(dx: 0, dy: partner.frame.maxY - source.frame.midY + 12))
            sourceGrip.press(forDuration: 0.6, thenDragTo: belowPartner, withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        XCTAssertGreaterThan(source.frame.minY, partner.frame.minY, "A full boundary crossing must still reorder")

    }

    func testJointsJoinAndSplitAsADraftAndSaveKeepsIt() {
        let app = launch(seedsSupersets: true)
        let labels = app.descendants(matching: .any).matching(identifier: "SupersetLabel")
        XCTAssertEqual(labels.count, 2)
        openEditor(in: app)
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch

        let joinFirst = app.buttons["SupersetLinkButton-0"]
        XCTAssertTrue(joinFirst.label.hasPrefix("Link "))
        XCTAssertTrue(app.buttons["SupersetLinkButton-1"].label.hasPrefix("Unlink "))
        joinFirst.tap()
        XCTAssertTrue(waitForLabelPrefix(joinFirst, "Unlink "))
        attachScreenshot("Linked", app: app)
        XCTAssertEqual(
            list.descendants(matching: .any).matching(identifier: "SupersetLabel").firstMatch.label,
            "Superset of 3 exercises"
        )
        // Undo takes the link back.
        app.buttons["ReorderUndoButton"].tap()
        XCTAssertTrue(waitForLabelPrefix(joinFirst, "Link "))
        joinFirst.tap()
        XCTAssertTrue(waitForLabelPrefix(joinFirst, "Unlink "))

        app.buttons["CancelReorderExercisesButton"].tap()
        discardChanges(in: app)
        XCTAssertTrue(app.buttons["ExerciseHeader-2"].waitToExist(timeout: 3))
        XCTAssertEqual(labels.firstMatch.label, "Superset of 2 exercises")

        // Save keeps a split of the giant set: its last exercise goes single.
        openEditor(in: app)
        let splitLast = app.buttons["SupersetLinkButton-4"]
        XCTAssertTrue(splitLast.label.hasPrefix("Unlink "))
        splitLast.tap()
        XCTAssertTrue(waitForLabelPrefix(splitLast, "Link "))
        app.buttons["SaveReorderExercisesButton"].tap()
        XCTAssertTrue(app.buttons["ExerciseHeader-2"].waitToExist(timeout: 3))
        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(labels.element(boundBy: 1).label, "Superset of 2 exercises")
    }

    /// Members reorder within their superset by their own grips, and leave it when
    /// dragged clear; a single dropped between two members joins.
    func testMemberGripsReorderWithinAndOutOfASuperset() {
        let app = launch(seedsSupersets: true)
        openEditor(in: app)
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        let labels = list.descendants(matching: .any).matching(identifier: "SupersetLabel")
        // Picking up the last member at the end of the list, without moving it, keeps it in.
        let lastGrip = exerciseRow("Single-Arm Cable Lateral Raise", in: app)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        lastGrip.press(forDuration: 0.6)
        XCTAssertEqual(labels.element(boundBy: 1).label, "Superset of 3 exercises")
        XCTAssertFalse(app.buttons["SaveReorderExercisesButton"].isEnabled, "A press alone changes nothing")
        drag(row: "Incline Dumbbell Press", above: "Pull-Up", in: app)
        XCTAssertEqual(labels.firstMatch.label, "Superset of 2 exercises", "Reordering inside keeps the pair")
        drag(row: "Slingshot Pause Bench Press", between: "Incline Dumbbell Press", and: "Pull-Up", in: app)
        XCTAssertEqual(labels.firstMatch.label, "Superset of 3 exercises", "Dropped between members, it joins")
        attachScreenshot("Joined by dragging", app: app)
        // The last member has no row below to pass: dragging it past the outline makes it single.
        let last = exerciseRow("Single-Arm Cable Lateral Raise", in: app)
        let grip = last.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        grip.press(forDuration: 0.3, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: last.frame.height)),
                   withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(waitUntil(timeout: 3) { labels.element(boundBy: 1).label == "Superset of 2 exercises" })
        app.buttons["SaveReorderExercisesButton"].tap()
        let expected = ["Incline Dumbbell Press", "Slingshot Pause Bench Press", "Pull-Up"]
        for (index, name) in expected.enumerated() {
            let header = app.buttons["ExerciseHeader-\(index)"]
            XCTAssertTrue(header.waitToExist(timeout: 3))
            XCTAssertTrue(header.label.contains(name), "\(index): \(header.label)")
        }
    }

    /// A member swipes within its container to Remove, and Undo puts it back in its superset.
    func testSwipingASupersetMemberRemovesItAndUndoRestoresIt() {
        let app = launch(seedsSupersets: true)
        openEditor(in: app)
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        let member = exerciseRow("Incline Dumbbell Press", in: app)
        XCTAssertTrue(member.waitToExist(timeout: 3))
        let before = member.frame

        let remove = revealRemove("Incline Dumbbell Press", in: app)
        XCTAssertLessThanOrEqual(remove.frame.maxX, before.maxX, "Remove stays inside the container")
        attachScreenshot("Superset member Remove revealed", app: app)
        remove.tap()
        XCTAssertTrue(waitForAbsence(member))
        XCTAssertTrue(app.descendants(matching: .any)["ReorderNotice"].label.contains("Removed Incline Dumbbell Press"))
        let undo = app.buttons["ReorderUndoButton"]
        undo.tap()
        XCTAssertTrue(member.waitToExist(timeout: 3))
        XCTAssertFalse(undo.isEnabled)
        XCTAssertEqual(list.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
    }

    private func launch(seedsSupersets: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-in-memory-store", "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-seed-long-name-active-workout",
        ] + (seedsSupersets ? ["--uitest-seed-supersets"] : [])
        app.launch()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitToExist(timeout: 8))
        return app
    }

    private func openMenu(_ index: Int, in app: XCUIApplication) {
        let menu = app.buttons["ExerciseMenuButton-\(index)"]
        XCTAssertTrue(menu.waitToExist(timeout: 3))
        for _ in 0..<4 where !(menu.exists && menu.isHittable) { app.swipeDown() }
        menu.tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-\(index)"].waitToExist(timeout: 3))
    }

    private func removeSupersetMember(_ name: String, in app: XCUIApplication) {
        revealRemove(name, in: app).tap()
        XCTAssertTrue(waitForAbsence(exerciseRow(name, in: app)))
    }

    /// Swipes a row far enough to show its Remove, without removing it.
    private func revealRemove(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let row = exerciseRow(name, in: app)
        XCTAssertTrue(row.waitToExist(timeout: 3))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).press(
            forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)),
            withVelocity: .fast, thenHoldForDuration: 0
        )
        let remove = app.buttons.matching(NSPredicate(format: "label == %@", "Remove \(name)")).firstMatch
        XCTAssertTrue(remove.waitToExist(timeout: 3), "Remove did not appear for \(name)")
        return remove
    }

    private func discardChanges(in app: XCUIApplication) {
        let discard = app.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitToExist(timeout: 3))
        discard.tap()
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        XCTAssertTrue(waitForAbsence(list))
    }

    private func exerciseRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "ReorderExerciseRow-"))
    }

    private func exerciseRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "ReorderExerciseRow-", name)
        ).firstMatch
    }

    private func openEditor(in app: XCUIApplication) {
        let edit = app.buttons["ActiveWorkoutEditButton"]
        XCTAssertTrue(edit.waitToExist(timeout: 3))
        edit.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch.waitToExist(timeout: 3))
    }

    /// Drags a row by its grip until it sits above the destination row.
    private func drag(row name: String, above destinationName: String, in app: XCUIApplication) {
        for _ in 0..<2 where exerciseRow(name, in: app).frame.minY > exerciseRow(destinationName, in: app).frame.minY {
            let source = exerciseRow(name, in: app)
            let destination = exerciseRow(destinationName, in: app)
            let grip = source.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let target = grip.withOffset(CGVector(dx: 0, dy: destination.frame.minY + 10 - source.frame.midY))
            grip.press(forDuration: 0.3, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)
        }
        XCTAssertLessThan(exerciseRow(name, in: app).frame.minY, exerciseRow(destinationName, in: app).frame.minY)
    }

    /// Drags a row by its grip so its center lands in the gap between two others.
    private func drag(row name: String, between upper: String, and lower: String, in app: XCUIApplication) {
        let source = exerciseRow(name, in: app)
        XCTAssertTrue(source.waitToExist(timeout: 3))
        let gap = (exerciseRow(upper, in: app).frame.maxY + exerciseRow(lower, in: app).frame.minY) / 2
        let grip = source.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        grip.press(forDuration: 0.3, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: gap - source.frame.midY)),
                   withVelocity: .slow, thenHoldForDuration: 0.6)
        let (top, middle, bottom) = (exerciseRow(upper, in: app).frame, exerciseRow(name, in: app).frame, exerciseRow(lower, in: app).frame)
        XCTAssertTrue(top.minY < middle.minY && middle.minY < bottom.minY, "\(name) lands between \(upper) and \(lower)")
    }

    /// Drags a superset by its label's grip until the whole block sits above the destination row.
    private func dragSuperset(at index: Int, lastMember: String, above destinationName: String, in app: XCUIApplication) {
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        let label = list.descendants(matching: .any).matching(identifier: "SupersetLabel").element(boundBy: index)
        XCTAssertTrue(label.waitToExist(timeout: 3))
        let destination = exerciseRow(destinationName, in: app)
        let blockMidY = (label.frame.minY + exerciseRow(lastMember, in: app).frame.maxY) / 2
        let grip = label.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        // The block's center has to pass above the destination's.
        let target = grip.withOffset(CGVector(dx: 0, dy: destination.frame.minY - 24 - blockMidY))
        grip.press(forDuration: 0.3, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertLessThan(exerciseRow(lastMember, in: app).frame.maxY, destination.frame.minY)
    }

    private func waitForLabelPrefix(_ element: XCUIElement, _ prefix: String) -> Bool {
        waitUntil(timeout: 3) { element.exists && element.label.hasPrefix(prefix) }
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        waitUntil(timeout: 3) { element.exists && element.label == label }
    }

    private func waitForAbsence(_ element: XCUIElement) -> Bool {
        element.waitToDisappear(timeout: 3)
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
