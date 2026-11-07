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
        app.revealAboveWorkoutActions(tapped)
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
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        XCTAssertEqual(list.cells.count, 4, "Single, pair, giant set and Add Exercises")
        attachScreenshot("Edit Workout with supersets", app: app)

        // Removing a pair member leaves its partner single, as a draft only.
        removeSupersetMember("Incline Dumbbell Press", in: app)
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

    func testSavingAWorkoutAsATemplateKeepsItsSupersets() {
        let app = launch(seedsSupersets: true)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
        app.buttons["FinishWorkoutButton"].tap()
        let toggle = app.switches["SaveAsTemplateToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.switches.firstMatch.tap()
        app.buttons["SaveWorkoutButton"].tap()

        XCTAssertTrue(app.staticTexts["HomeTitle"].waitForExistence(timeout: 3))
        app.buttons["StartWorkoutButton"].tap()
        XCTAssertTrue(app.buttons["UseTemplateButton"].waitForExistence(timeout: 3))
        app.buttons["UseTemplateButton"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "TemplateRow-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.buttons["StartFromTemplateButton"].waitForExistence(timeout: 3))
        attachScreenshot("Template review with supersets", app: app)
        // The grouped native list also hosts the template name above its movable rows.
        app.buttons["EditTemplateButton"].tap()
        let name = app.textFields["TemplateNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText(" Edited\n")
        drag(cellContaining: "Pull-Up", above: "Bench Press", in: app)
        app.buttons["SaveTemplateButton"].tap()
        XCTAssertTrue(app.staticTexts["TemplateReviewTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["TemplateReviewTitle"].label.contains("Edited"))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
        app.buttons["StartFromTemplateButton"].tap()

        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
    }

    func testLinkModeKeepsEveryCardInPlace() {
        let app = launch(seedsSupersets: true)
        openEditor(in: app)
        assertCardsStayInPlaceThroughLinkMode(in: app)
    }

    /// A workout longer than the screen, starting in the list without supersets.
    func testLinkModeKeepsScrolledCardsInPlaceInBothLists() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-in-memory-store", "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-seed-large-active-workout",
        ]
        app.launch()
        openEditor(in: app)
        let link = app.buttons["EditWorkoutLinkExercisesButton"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        assertCardsStayInPlaceThroughLinkMode(in: app)

        // Scrolled up inside the mode: leaving keeps that position rather than jumping to the end.
        startLinking(link, in: app)
        app.swipeDown()
        settle()
        let scrolled = cardFrames(in: app)
        let done = app.buttons["DoneLinkingButton"]
        done.tap()
        XCTAssertTrue(waitForAbsence(done))
        settle()
        assertSameCards(scrolled, cardFrames(in: app), "Leaving after scrolling up")

        // The first superset swaps in the other list, whose cards have to line up too.
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        startLinking(link, in: app)
        let lastLink = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "SupersetLinkButton-")
        ).allElementsBoundByIndex.last(where: \.isHittable)
        XCTAssertNotNil(lastLink)
        lastLink?.tap()
        done.tap()
        XCTAssertTrue(waitForAbsence(done))
        XCTAssertTrue(link.waitForExistence(timeout: 3))
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        assertCardsStayInPlaceThroughLinkMode(in: app)
    }

    private func assertCardsStayInPlaceThroughLinkMode(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let link = app.buttons["EditWorkoutLinkExercisesButton"]
        settle()
        let regular = cardFrames(in: app)
        XCTAssertGreaterThan(regular.count, 1, file: file, line: line)
        startLinking(link, in: app)
        let done = app.buttons["DoneLinkingButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), file: file, line: line)
        settle()
        assertSameCards(regular, cardFrames(in: app), "Entering link mode", file: file, line: line)
        done.tap()
        XCTAssertTrue(waitForAbsence(done), file: file, line: line)
        settle()
        assertSameCards(regular, cardFrames(in: app), "Leaving link mode", file: file, line: line)
    }

    /// Lets the crossfade finish and the scroll come to rest.
    private func settle() { Thread.sleep(forTimeInterval: 0.8) }

    /// Each exercise card on screen, by identifier. The list without supersets exposes a
    /// whole cell instead of its card, so that card's edges come from its text's 14pt padding.
    private func cardFrames(in app: XCUIApplication) -> [String: CGRect] {
        let window = app.windows.firstMatch.frame
        let cards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "ReorderExerciseRow-")
        ).allElementsBoundByIndex
        var frames: [String: CGRect] = [:]
        for card in cards where card.exists && card.frame.width > 1 && card.frame.minY < window.height {
            var frame = card.frame
            if frame.width >= window.width - 1 {
                let texts = card.staticTexts.allElementsBoundByIndex
                guard let first = texts.first, let last = texts.last else { continue }
                frame = CGRect(
                    x: first.frame.minX - 14, y: frame.minY + 6,
                    width: last.frame.maxX + 14 - (first.frame.minX - 14), height: frame.height - 12
                )
            }
            frames[card.identifier] = frame
        }
        return frames
    }

    private func assertSameCards(
        _ expected: [String: CGRect], _ actual: [String: CGRect], _ step: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // A card can leave the screen under the bars, so compare those that show in both.
        let shared = Set(expected.keys).intersection(actual.keys)
        XCTAssertGreaterThan(shared.count, 1, step, file: file, line: line)
        for id in shared {
            guard let before = expected[id], let after = actual[id] else { continue }
            XCTAssertEqual(before.minX, after.minX, accuracy: 1, "\(step): left edge", file: file, line: line)
            XCTAssertEqual(before.maxX, after.maxX, accuracy: 1, "\(step): right edge", file: file, line: line)
            XCTAssertEqual(before.minY, after.minY, accuracy: 1, "\(step): top edge", file: file, line: line)
        }
    }

    func testTemplateEditorLinksExercisesAndSaves() {
        let app = launch(seedsSupersets: true)
        app.buttons["FinishWorkoutButton"].tap()
        let toggle = app.switches["SaveAsTemplateToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.switches.firstMatch.tap()
        app.buttons["SaveWorkoutButton"].tap()
        XCTAssertTrue(app.staticTexts["HomeTitle"].waitForExistence(timeout: 3))
        app.buttons["StartWorkoutButton"].tap()
        XCTAssertTrue(app.buttons["UseTemplateButton"].waitForExistence(timeout: 3))
        app.buttons["UseTemplateButton"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "TemplateRow-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.buttons["EditTemplateButton"].waitForExistence(timeout: 3))
        app.buttons["EditTemplateButton"].tap()

        // Starting from the name field: the mode has to take the keyboard away.
        let name = app.textFields["TemplateNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        // The name sits above the cards, so they would show it moving too.
        assertCardsStayInPlaceThroughLinkMode(in: app)

        name.tap()
        name.typeText(" Linked")
        startLinking(app.buttons["EditWorkoutLinkExercisesButton"], in: app)
        let doneLinking = app.buttons["DoneLinkingButton"]
        XCTAssertTrue(doneLinking.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForAbsence(app.keyboards.firstMatch))
        XCTAssertTrue(doneLinking.isHittable)

        let joinFirst = app.buttons["SupersetLinkButton-0"]
        XCTAssertTrue(joinFirst.label.hasPrefix("Link "))
        joinFirst.tap()
        XCTAssertTrue(waitForLabelPrefix(joinFirst, "Unlink "))
        doneLinking.tap()
        XCTAssertTrue(waitForAbsence(doneLinking))
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertTrue((name.value as? String)?.contains("Linked") == true, "Linking keeps the typed name")

        app.buttons["SaveTemplateButton"].tap()
        XCTAssertTrue(app.staticTexts["TemplateReviewTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "SupersetLabel").firstMatch.label,
            "Superset of 3 exercises"
        )
    }

    /// A partner fills from what's typed in its own set above, even before that field loses focus.
    func testRoundFillsPartnersFromATypedDraftInAnotherExercise() {
        let app = launch(seedsSupersets: true)
        app.buttons["ExerciseHeader-0"].tap()
        let draft = app.textFields["SetWeightField-2-0"]
        app.revealAboveWorkoutActions(draft)
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
        XCTAssertTrue(app.buttons["ActiveWorkoutEditButton"].waitForExistence(timeout: 8))
        openEditor(in: app)
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        let source = list.cells.containing(NSPredicate(format: "label == %@", "Slingshot Pause Bench Press")).firstMatch
        let grip = source.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let target = grip.withOffset(CGVector(dx: 0, dy: 150))
        grip.press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 4)
        attachScreenshot("Reorder after hovering", app: app)
        let label = app.staticTexts["ReorderStabilityProbe"].value as? String ?? ""
        print("Native reorder slot changes: \(label)")
        let moves = Int(label) ?? -1
        XCTAssertGreaterThanOrEqual(moves, 0, "The probe must report its measurement")
        XCTAssertLessThan(moves, 6, "One row boundary must not repeatedly rearrange cells")
        let partner = list.cells.containing(NSPredicate(format: "label == %@", "Pull-Up")).firstMatch
        if source.frame.minY < partner.frame.minY {
            let sourceGrip = source.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let belowPartner = sourceGrip.withOffset(CGVector(dx: 0, dy: partner.frame.maxY - source.frame.midY + 12))
            sourceGrip.press(forDuration: 0.6, thenDragTo: belowPartner, withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        XCTAssertGreaterThan(source.frame.minY, partner.frame.minY, "A full boundary crossing must still reorder")

    }

    func testRemovingLastSupersetPartnerKeepsCancelSemantics() {
        let app = launch(seedsSupersets: true)
        // Remove the members of each group until only single exercises remain.
        openEditor(in: app)
        for name in ["Incline Dumbbell Press", "Cable Overhead Triceps Extension", "Single-Arm Cable Lateral Raise"] {
            removeSupersetMember(name, in: app)
        }
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        XCTAssertTrue(list.exists)
        XCTAssertEqual(list.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 0)
        app.buttons["CancelReorderExercisesButton"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
    }

    func testLinkModeJoinsAndSplitsAsADraftAndDoneKeepsIt() {
        let app = launch(seedsSupersets: true)
        let labels = app.descendants(matching: .any).matching(identifier: "SupersetLabel")
        XCTAssertEqual(labels.count, 2)
        openEditor(in: app)

        let linkExercises = app.buttons["EditWorkoutLinkExercisesButton"]
        startLinking(linkExercises, in: app)
        let doneLinking = app.buttons["DoneLinkingButton"]
        XCTAssertTrue(doneLinking.waitForExistence(timeout: 3))
        // The regular list, with its labels and remove buttons, gives way to the links.
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        XCTAssertTrue(waitForAbsence(list))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove ")).firstMatch.exists)
        attachScreenshot("Link mode", app: app)

        // Slingshot joins the Pull-Up pair, and the joint between them turns linked.
        let joinFirst = app.buttons["SupersetLinkButton-0"]
        XCTAssertTrue(joinFirst.label.hasPrefix("Link "))
        XCTAssertTrue(app.buttons["SupersetLinkButton-1"].label.hasPrefix("Unlink "))
        joinFirst.tap()
        XCTAssertTrue(waitForLabelPrefix(joinFirst, "Unlink "))
        attachScreenshot("Linked", app: app)
        doneLinking.tap()
        XCTAssertTrue(waitForAbsence(doneLinking))
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertEqual(
            list.descendants(matching: .any).matching(identifier: "SupersetLabel").firstMatch.label,
            "Superset of 3 exercises"
        )

        // Cancel throws the draft away.
        app.buttons["CancelReorderExercisesButton"].tap()
        XCTAssertTrue(app.buttons["ExerciseHeader-2"].waitForExistence(timeout: 3))
        XCTAssertEqual(labels.firstMatch.label, "Superset of 2 exercises")

        // Done keeps a split of the giant set: its last exercise goes single.
        openEditor(in: app)
        startLinking(linkExercises, in: app)
        XCTAssertTrue(doneLinking.waitForExistence(timeout: 3))
        let splitLast = app.buttons["SupersetLinkButton-4"]
        XCTAssertTrue(splitLast.label.hasPrefix("Unlink "))
        splitLast.tap()
        XCTAssertTrue(waitForLabelPrefix(splitLast, "Link "))
        doneLinking.tap()
        XCTAssertTrue(waitForAbsence(doneLinking))
        app.buttons["DoneReorderExercisesButton"].tap()
        XCTAssertTrue(app.buttons["ExerciseHeader-2"].waitForExistence(timeout: 3))
        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(labels.element(boundBy: 1).label, "Superset of 2 exercises")
    }

    /// A member's minus asks first, like a single exercise's minus.
    func testSupersetMemberMinusRevealsDeleteBeforeRemoving() {
        let app = launch(seedsSupersets: true)
        openEditor(in: app)
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        let member = list.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Incline Dumbbell Press")).firstMatch
        let minus = app.buttons.matching(NSPredicate(format: "label == %@", "Remove Incline Dumbbell Press")).firstMatch
        let delete = app.buttons.matching(NSPredicate(format: "label == %@", "Delete Incline Dumbbell Press")).firstMatch
        XCTAssertTrue(minus.waitForExistence(timeout: 3))

        minus.tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "The first tap only reveals Delete")
        XCTAssertTrue(member.exists)
        XCTAssertGreaterThan(delete.frame.minX, member.frame.maxX - 1, "Delete sits trailing of the member")
        attachScreenshot("Superset member Delete revealed", app: app)
        // The minus again, the card, or another row closes it without removing anything.
        minus.tap()
        XCTAssertTrue(waitForAbsence(delete))

        // A long name truncates beside Delete rather than wrapping, so the row keeps its height.
        let longName = "Cable Overhead Triceps Extension"
        let long = list.descendants(matching: .any).matching(NSPredicate(format: "label == %@", longName)).firstMatch
        let longDelete = app.buttons.matching(NSPredicate(format: "label == %@", "Delete \(longName)")).firstMatch
        let restingHeight = long.frame.height
        app.buttons.matching(NSPredicate(format: "label == %@", "Remove \(longName)")).firstMatch.tap()
        XCTAssertTrue(longDelete.waitForExistence(timeout: 3))
        XCTAssertEqual(long.frame.height, restingHeight, accuracy: 1)
        attachScreenshot("Long name truncates beside Delete", app: app)
        long.tap()
        XCTAssertTrue(waitForAbsence(longDelete))
        XCTAssertEqual(long.frame.height, restingHeight, accuracy: 1)

        minus.tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        member.tap()
        XCTAssertTrue(waitForAbsence(delete))
        minus.tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        list.cells.containing(NSPredicate(format: "label == %@", "Slingshot Pause Bench Press")).firstMatch.tap()
        XCTAssertTrue(waitForAbsence(delete))
        XCTAssertTrue(member.exists)

        minus.tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(waitForAbsence(member))
        app.buttons["CancelReorderExercisesButton"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "SupersetLabel").count, 2)
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

    private func removeSupersetMember(_ name: String, in app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label == %@", "Remove \(name)")).firstMatch.tap()
        let delete = app.buttons.matching(NSPredicate(format: "label == %@", "Delete \(name)")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
    }

    private func openEditor(in app: XCUIApplication) {
        let edit = app.buttons["ActiveWorkoutEditButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch.waitForExistence(timeout: 3))
    }

    /// Drags a row by its grip until it sits above the destination row.
    private func drag(cellContaining name: String, above destinationName: String, in app: XCUIApplication) {
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
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

    private func startLinking(_ button: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        // Lets the sheet finish presenting before judging whether the row is on screen.
        Thread.sleep(forTimeInterval: 0.6)
        let list = app.descendants(matching: .any).matching(identifier: "ReorderExercisesList").firstMatch
        for _ in 0..<4 where !button.isHittable { list.swipeUp() }
        button.tap()
    }

    private func waitForLabelPrefix(_ element: XCUIElement, _ prefix: String) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
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
