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
    func testWorkoutTitleFieldsShowEditAffordance() {
        let app = makeApp(completedBenchWorkoutTitles: ["Existing Editable"])
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        let activeTitleField = app.textFields["WorkoutTitle"]
        XCTAssertTrue(activeTitleField.waitForExistence(timeout: 3))
        let activeTitleAffordance = app.buttons["WorkoutTitleEditAffordance"]
        XCTAssertFalse(activeTitleAffordance.exists)
        activeTitleField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        dismissKeyboardIfNeeded(in: app)

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["WorkoutHistoryButton-0"].tap()

        XCTAssertTrue(app.buttons["EditWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["EditWorkoutButton"].tap()
        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 3))

        XCTAssertTrue(app.staticTexts["CompletedWorkoutTitleLabel"].waitForExistence(timeout: 3))
        let completedTitleField = app.textFields["CompletedWorkoutTitleField"]
        XCTAssertTrue(completedTitleField.waitForExistence(timeout: 3))
        completedTitleField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testFinishWorkoutSheetCanRenameDefaultWorkoutBeforeSaving() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        openFinishWorkoutSheet(in: app)
        let finishTitleField = app.textFields["FinishWorkoutTitleField"]
        XCTAssertTrue(finishTitleField.waitForExistence(timeout: 3))
        XCTAssertEqual(finishTitleField.value as? String, "Workout")
        XCTAssertTrue(app.staticTexts["FinishWorkoutTitleDefaultHint"].exists)
        replaceText(in: finishTitleField, with: "Saturday Push")
        let keyboardDoneButton = app.buttons["Done"]
        XCTAssertTrue(keyboardDoneButton.waitForExistence(timeout: 3))
        keyboardDoneButton.tap()

        XCTAssertTrue(app.buttons["KeepGoingButton"].waitForExistence(timeout: 3))
        app.buttons["KeepGoingButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["WorkoutTitle"].value as? String, "Saturday Push")
    }

    @MainActor
    func testFinishWorkoutSheetNormalizesBlankTitleBeforeKeepGoing() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        openFinishWorkoutSheet(in: app)
        let finishTitleField = app.textFields["FinishWorkoutTitleField"]
        XCTAssertTrue(finishTitleField.waitForExistence(timeout: 3))
        replaceText(in: finishTitleField, with: "")

        let keyboardDoneButton = app.buttons["Done"]
        XCTAssertTrue(keyboardDoneButton.waitForExistence(timeout: 3))
        keyboardDoneButton.tap()

        XCTAssertTrue(app.buttons["KeepGoingButton"].waitForExistence(timeout: 3))
        app.buttons["KeepGoingButton"].tap()

        let activeTitleField = app.textFields["WorkoutTitle"]
        XCTAssertTrue(activeTitleField.waitForExistence(timeout: 3))
        XCTAssertEqual(activeTitleField.value as? String, "Workout")
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
        XCTAssertTrue(app.staticTexts["ProfileEnvironmentBadge"].exists)

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
        // Adding a set creates a blank row and moves focus to its weight field,
        // so it shows the unit placeholder rather than carrying the prior value.
        XCTAssertEqual(secondWeightField.value as? String, "LBS")
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
    func testExerciseMenuHidesReorderWithOneExercise() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addBenchPress(in: app)
        dismissKeyboardIfNeeded(in: app)

        XCTAssertFalse(app.buttons["WorkoutOptionsButton"].exists)
        app.buttons["ExerciseMenuButton-0"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["ReorderExercisesButton-0"].exists)
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

        app.buttons["ExerciseMenuButton-0"].tap()
        let reorderButton = app.buttons["ReorderExercisesButton-0"]
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
        let app = makeApp(completedBenchWorkoutTitles: ["Push History"])
        app.launch()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["WorkoutHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["185 x 5 @ 8 · Done"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts["Push History"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["185 x 5 @ 8"].exists)
    }

    @MainActor
    func testDeletingCompletedWorkoutRemovesItFromHistory() {
        let app = makeApp(completedBenchWorkoutTitles: ["Delete Me"])
        app.launch()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["WorkoutHistoryButton-0"].tap()

        let deleteWorkoutButton = app.buttons["Delete Workout"]
        for _ in 0..<6 where !deleteWorkoutButton.exists || !deleteWorkoutButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(deleteWorkoutButton.waitForExistence(timeout: 3))
        deleteWorkoutButton.tap()

        XCTAssertTrue(app.alerts["Delete Workout?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testEditingCompletedWorkoutUpdatesHistoryDetailAndExerciseHistory() {
        let app = makeApp()
        app.launch()

        createCompletedBenchWorkout(in: app, title: "Editable Push")

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["WorkoutHistoryButton-0"].tap()

        XCTAssertTrue(app.buttons["EditWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["EditWorkoutButton"].tap()
        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 3))

        replaceText(in: app.textFields["CompletedWorkoutTitleField"], with: "Edited Push")
        setCompletedWorkoutDuration(minutes: 45, in: app)
        replaceText(in: app.textFields["CompletedWorkoutNotesField"], with: "Post edit notes")
        dismissKeyboardIfNeeded(in: app)
        replaceText(in: app.textFields["HistorySetWeightField-0-0"], with: "205.")
        XCTAssertEqual(app.textFields["HistorySetWeightField-0-0"].value as? String, "205.")
        app.textFields["HistorySetWeightField-0-0"].typeText("5")
        replaceText(in: app.textFields["HistorySetRepsField-0-0"], with: "6")
        dismissKeyboardIfNeeded(in: app)

        assertRemovedDraftHistorySetDoesNotReuseCachedNumberText(in: app)

        replaceText(in: app.textFields["HistorySetWeightField-0-1"], with: "135")
        replaceText(in: app.textFields["HistorySetRepsField-0-1"], with: "8")
        replaceText(in: app.textFields["HistorySetRPEField-0-1"], with: "7.")
        XCTAssertEqual(app.textFields["HistorySetRPEField-0-1"].value as? String, "7.")
        app.textFields["HistorySetRPEField-0-1"].typeText("5")
        app.buttons["HistorySetCompletionButton-0-1"].tap()
        dismissKeyboardIfNeeded(in: app)

        app.buttons["SaveCompletedWorkoutEditButton"].tap()

        XCTAssertTrue(app.navigationBars["Edited Push"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Post edit notes"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["45:00"].exists)
        XCTAssertTrue(app.staticTexts["205.5 x 6 @ 8 · Done"].exists)
        XCTAssertTrue(app.staticTexts["135 x 8 @ 7.5 · Done"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts["205.5 x 6 @ 8"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["135 x 8 @ 7.5"].exists)
    }

    @MainActor
    func testRemovingFocusedNewCompletedWorkoutSetDoesNotCrash() {
        let app = makeApp()
        app.launch()

        createCompletedBenchWorkout(in: app, title: "Focused Draft Remove")

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["WorkoutHistoryButton-0"].tap()

        XCTAssertTrue(app.buttons["EditWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["EditWorkoutButton"].tap()
        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 3))

        app.buttons["AddHistorySetButton-0"].tap()
        XCTAssertTrue(app.textFields["HistorySetWeightField-0-1"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["HistorySetWeightField-0-1"], with: "135")
        replaceText(in: app.textFields["HistorySetRepsField-0-1"], with: "8")
        replaceText(in: app.textFields["HistorySetRPEField-0-1"], with: "7.5")

        app.buttons["RemoveHistorySetButton-0-1"].tap()
        let removeButton = app.alerts.buttons["Remove"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 3))
        removeButton.tap()

        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["HistorySetWeightField-0-1"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.textFields["HistorySetWeightField-0-0"].exists)
    }

    @MainActor
    func testSignedOutCompletedWorkoutEditPersistsThroughSignedInRelaunch() {
        let app = makeDiskBackedResetApp(extraArguments: ["--uitest-force-signed-out-auth"])
        app.launch()

        createCompletedBenchWorkout(in: app, title: "Signed Out Editable Push")

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["WorkoutHistoryButton-0"].tap()

        XCTAssertTrue(app.buttons["EditWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["EditWorkoutButton"].tap()
        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 3))

        replaceText(in: app.textFields["CompletedWorkoutTitleField"], with: "Signed Out Edited Push")
        dismissKeyboardIfNeeded(in: app)
        replaceText(in: app.textFields["CompletedWorkoutNotesField"], with: "Edited while signed out")
        dismissKeyboardIfNeeded(in: app)

        app.buttons["AddHistorySetButton-0"].tap()
        XCTAssertTrue(app.textFields["HistorySetWeightField-0-1"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["HistorySetWeightField-0-1"], with: "135")
        replaceText(in: app.textFields["HistorySetRepsField-0-1"], with: "8")
        replaceText(in: app.textFields["HistorySetRPEField-0-1"], with: "7.")
        XCTAssertEqual(app.textFields["HistorySetRPEField-0-1"].value as? String, "7.")
        app.textFields["HistorySetRPEField-0-1"].typeText("5")
        app.buttons["HistorySetCompletionButton-0-1"].tap()
        dismissKeyboardIfNeeded(in: app)

        app.buttons["SaveCompletedWorkoutEditButton"].tap()
        XCTAssertTrue(app.navigationBars["Signed Out Edited Push"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Edited while signed out"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["185 x 5 @ 8 · Done"].exists)
        XCTAssertTrue(app.staticTexts["135 x 8 @ 7.5 · Done"].exists)

        app.terminate()

        let relaunchedApp = makeDiskBackedApp(extraArguments: [
            "--uitest-sync-owner", "issuer|ui_owner",
            "--uitest-force-signed-in-auth",
        ])
        relaunchedApp.launch()
        relaunchedApp.buttons["HistoryTab"].tap()
        XCTAssertTrue(relaunchedApp.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        relaunchedApp.buttons["WorkoutHistoryButton-0"].tap()

        XCTAssertTrue(relaunchedApp.navigationBars["Signed Out Edited Push"].waitForExistence(timeout: 3))
        XCTAssertTrue(relaunchedApp.staticTexts["Edited while signed out"].exists)
        XCTAssertTrue(relaunchedApp.staticTexts["185 x 5 @ 8 · Done"].exists)
        XCTAssertTrue(relaunchedApp.staticTexts["135 x 8 @ 7.5 · Done"].exists)

        relaunchedApp.navigationBars.buttons.element(boundBy: 0).tap()
        relaunchedApp.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(relaunchedApp.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        relaunchedApp.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(relaunchedApp.staticTexts["185 x 5 @ 8"].waitForExistence(timeout: 3))
        XCTAssertTrue(relaunchedApp.staticTexts["135 x 8 @ 7.5"].exists)
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
        app.buttons["ExerciseMenuButton-0"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()

        XCTAssertTrue(app.staticTexts["Dumbbell Variant"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Barbell Variant"].exists)
    }

    @MainActor
    func testStartingFromPastWorkoutCopiesSetsAsIncomplete() {
        let app = makeApp(completedBenchWorkoutTitles: ["Past Push"])
        app.launch()

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.buttons["PastWorkoutButton-0"].waitForExistence(timeout: 3))
        app.buttons["PastWorkoutButton-0"].tap()
        confirmStartFromPastWorkout(in: app)

        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["WorkoutTitle"].value as? String, "Past Push")
        let previousValue = app.buttons["SetPreviousValue-0-0"]
        XCTAssertTrue(previousValue.waitForExistence(timeout: 3))
        XCTAssertEqual(previousValue.label, "Previous: 185 × 5")
        XCTAssertEqual(app.textFields["SetWeightField-0-0"].value as? String, "LBS")
        XCTAssertEqual(app.textFields["SetRepsField-0-0"].value as? String, "REPS")
        previousValue.tap()
        XCTAssertEqual(app.textFields["SetWeightField-0-0"].value as? String, "185")
        XCTAssertEqual(app.textFields["SetRepsField-0-0"].value as? String, "5")
        XCTAssertTrue(app.buttons["SetCompletionButton-0-0"].exists)
        XCTAssertEqual(app.buttons["SetCompletionButton-0-0"].label, "Mark set complete")
    }

    @MainActor
    func testStartingFromPastWorkoutRequiresConfirmationBeforeCreatingWorkout() {
        let app = makeApp(completedBenchWorkoutTitles: ["Past Push"])
        app.launch()

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.buttons["PastWorkoutButton-0"].waitForExistence(timeout: 3))
        app.buttons["PastWorkoutButton-0"].tap()

        XCTAssertTrue(app.staticTexts["StartFromPastWorkoutSheetTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["StartFromPastWorkoutExplanation"].exists)
        XCTAssertFalse(app.textFields["WorkoutTitle"].exists)

        app.buttons["StartFromPastWorkoutCancelButton"].tap()
        XCTAssertTrue(app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["WorkoutTitle"].exists)

        app.buttons["PastWorkoutButton-0"].tap()
        confirmStartFromPastWorkout(in: app)

        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["WorkoutTitle"].value as? String, "Past Push")
    }

    @MainActor
    func testClearingCompletedWeightRemovesLoggedWeight() {
        assertClearingCompletedSetField(
            fieldIdentifier: "SetWeightField-0-0",
            expectedHistorySummary: "- x 5 @ 8"
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
    func testSettingsWeightUnitPreferenceRoundsDisplayedWorkoutAndHistoryValues() {
        let app = makeApp(completedBenchWorkoutTitles: ["Metric Display"])
        app.launch()

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileSettingsLink"].tap()
        XCTAssertTrue(app.segmentedControls["WeightUnitPicker"].waitForExistence(timeout: 3))
        app.segmentedControls["WeightUnitPicker"].buttons["Kilograms"].tap()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["WorkoutHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts["83.91"].waitForExistence(timeout: 3))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.staticTexts["83.91 x 5 @ 8"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testKilogramFirstWorkoutEntryDisplaysCleanWeightAndPlaceholder() {
        let app = makeApp()
        app.launch()

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileSettingsLink"].tap()
        XCTAssertTrue(app.segmentedControls["WeightUnitPicker"].waitForExistence(timeout: 3))
        app.segmentedControls["WeightUnitPicker"].buttons["Kilograms"].tap()

        app.buttons["WorkoutTab"].tap()
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addBenchPress(in: app)

        let firstWeightField = app.textFields["SetWeightField-0-0"]
        firstWeightField.tap()
        firstWeightField.typeText("100")
        dismissKeyboardIfNeeded(in: app)
        XCTAssertEqual(firstWeightField.value as? String, "100")

        app.buttons["AddSetButton-0"].tap()
        let secondWeightField = app.textFields["SetWeightField-0-1"]
        XCTAssertTrue(secondWeightField.waitForExistence(timeout: 3))
        // A newly added set is blank, so it shows the kilogram placeholder.
        XCTAssertEqual(secondWeightField.value as? String, "KG")
        secondWeightField.tap()
        secondWeightField.typeText("100")
        dismissKeyboardIfNeeded(in: app)
        XCTAssertEqual(secondWeightField.value as? String, "100")

        app.buttons["ProfileTab"].tap()
        if !app.segmentedControls["WeightUnitPicker"].waitForExistence(timeout: 1) {
            app.buttons["ProfileSettingsLink"].tap()
            XCTAssertTrue(app.segmentedControls["WeightUnitPicker"].waitForExistence(timeout: 3))
        }
        app.segmentedControls["WeightUnitPicker"].buttons["Pounds"].tap()

        app.buttons["WorkoutTab"].tap()
        XCTAssertEqual(app.textFields["SetWeightField-0-0"].value as? String, "220.46")
        XCTAssertEqual(app.textFields["SetWeightField-0-1"].value as? String, "220.46")
    }

    @MainActor
    func testSettingsEditRequestsSyncInUITestMode() {
        let app = makeApp(extraArguments: ["--uitest-sync-owner", "issuer|ui_owner"])
        app.launch()

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileSettingsLink"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.segmentedControls["WeightUnitPicker"].buttons["Kilograms"].tap()

        XCTAssertTrue(app.staticTexts["UITestSyncRequestCount-1"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFailedSyncBannerShowsRetryAndRoutesToSettingsDetails() {
        let app = makeApp(extraArguments: [
            "--uitest-sync-owner", "issuer|ui_owner",
            "--uitest-show-sync-failure",
        ])
        app.launch()

        XCTAssertTrue(app.staticTexts["Cloud sync failed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Your data is saved on this iPhone."].exists)

        app.buttons["GlobalSyncRetryButton"].tap()
        XCTAssertTrue(app.staticTexts["UITestSyncRequestCount-1"].waitForExistence(timeout: 3))

        app.buttons["GlobalSyncDetailsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sync Status"].exists)
        XCTAssertTrue(app.staticTexts["Cloud sync could not finish. Your data is saved on this iPhone."].exists)

        app.buttons["SettingsDeveloperDiagnosticsRow"].tap()
        XCTAssertTrue(app.staticTexts["DeveloperDiagnosticsEnvironment"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["DeveloperDiagnosticsEnvironment"].label, "Development")
        XCTAssertTrue(app.staticTexts["DeveloperDiagnosticsClerkDomain"].exists)
        XCTAssertEqual(
            app.staticTexts["DeveloperDiagnosticsClerkDomain"].label,
            "webcredentials:glad-krill-22.clerk.accounts.dev"
        )
        let syncSummary = app.staticTexts["DeveloperDiagnosticsSyncSummary"]
        XCTAssertTrue(syncSummary.waitForExistence(timeout: 3))
        XCTAssertTrue(syncSummary.label.contains("lastFailure: Convex function sync:fetchChanges failed for token issuer|ui_owner"))
    }

    @MainActor
    func testFailedSyncBannerCanBeDismissed() {
        let app = makeApp(extraArguments: [
            "--uitest-sync-owner", "issuer|ui_owner",
            "--uitest-show-sync-failure",
        ])
        app.launch()

        XCTAssertTrue(app.staticTexts["Cloud sync failed"].waitForExistence(timeout: 3))
        app.buttons["GlobalSyncDismissButton"].tap()
        XCTAssertFalse(app.otherElements["GlobalSyncFailureBanner"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testSettingsShowsSignedOutLocalDataDeletionOnly() {
        let app = makeApp()
        app.launchArguments.append("--uitest-force-signed-out-auth")
        app.launch()

        app.buttons["ProfileTab"].tap()
        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))
        app.buttons["ProfileSettingsLink"].tap()

        XCTAssertTrue(app.staticTexts["Privacy & Data"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["SettingsDeleteLocalDataRow"].exists)
        XCTAssertFalse(app.buttons["SettingsDeleteAccountRow"].exists)
        XCTAssertTrue(app.staticTexts["Privacy Policy"].exists)
        XCTAssertTrue(app.staticTexts["Support"].exists)

        app.buttons["SettingsDeleteLocalDataRow"].tap()
        XCTAssertTrue(app.navigationBars["Delete Local Data"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["DeleteDataConfirmButton"].isEnabled)
        app.textFields["DeleteDataConfirmationField"].tap()
        app.textFields["DeleteDataConfirmationField"].typeText("DELETE")
        XCTAssertTrue(app.buttons["DeleteDataConfirmButton"].isEnabled)
    }

    @MainActor
    func testDeleteLocalDataReturnsToProfileAfterReset() {
        let app = makeApp()
        app.launchArguments.append("--uitest-force-signed-out-auth")
        app.launch()

        app.buttons["ProfileTab"].tap()
        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))
        app.buttons["ProfileSettingsLink"].tap()
        XCTAssertTrue(app.buttons["SettingsDeleteLocalDataRow"].waitForExistence(timeout: 3))
        app.buttons["SettingsDeleteLocalDataRow"].tap()

        XCTAssertTrue(app.navigationBars["Delete Local Data"].waitForExistence(timeout: 3))
        app.textFields["DeleteDataConfirmationField"].tap()
        app.textFields["DeleteDataConfirmationField"].typeText("DELETE")
        app.buttons["DeleteDataConfirmButton"].tap()

        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Settings"].exists)
    }

    @MainActor
    func testSettingsShowsSignedInAccountDeletionOnly() {
        let app = makeApp(extraArguments: ["--uitest-force-signed-in-auth"])
        app.launch()

        app.buttons["ProfileTab"].tap()
        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))
        app.buttons["ProfileSettingsLink"].tap()

        XCTAssertTrue(app.staticTexts["Privacy & Data"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["SettingsDeleteAccountRow"].exists)
        XCTAssertFalse(app.buttons["SettingsDeleteLocalDataRow"].exists)

        app.buttons["SettingsDeleteAccountRow"].tap()
        XCTAssertTrue(app.navigationBars["Delete Account"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["DeleteDataConfirmButton"].isEnabled)
        app.textFields["DeleteDataConfirmationField"].tap()
        app.textFields["DeleteDataConfirmationField"].typeText("DELETE")
        XCTAssertTrue(app.buttons["DeleteDataConfirmButton"].isEnabled)
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
    func testExerciseCreateRequestsSyncInUITestMode() {
        let app = makeApp(extraArguments: ["--uitest-sync-owner", "issuer|ui_owner"])
        app.launch()

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileExerciseLibraryLink"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3))
        createExercise(name: "UI Sync Bench", equipment: "Barbell", muscle: "Chest", in: app)

        XCTAssertTrue(app.staticTexts["UITestSyncRequestCount-1"].waitForExistence(timeout: 3))
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
    func testSwipeToDeleteSetRemovesSet() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("Bench Press, Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)

        app.buttons["AddSetButton-0"].tap()
        dismissKeyboardIfNeeded(in: app)
        let secondWeightField = app.textFields["SetWeightField-0-1"]
        XCTAssertTrue(secondWeightField.waitForExistence(timeout: 3))

        secondWeightField.swipeLeft()
        let deleteButton = app.buttons["DeleteSetButton-0-1"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.tap()

        XCTAssertFalse(app.textFields["SetWeightField-0-1"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["SetWeightField-0-0"].exists)
    }

    @MainActor
    private func makeApp(
        extraArguments: [String] = [],
        completedBenchWorkoutTitles: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let fixtureArguments = completedBenchWorkoutTitles.flatMap {
            ["--uitest-seed-completed-bench-workout", $0]
        }
        let authArguments = extraArguments.contains("--uitest-force-signed-in-auth")
            ? []
            : ["--uitest-force-signed-out-auth"]
        app.launchArguments = [
            "--uitest-reset-persistent-store",
            "--uitest-in-memory-store",
        ] + fixtureArguments + authArguments + extraArguments
        app.terminate()
        return app
    }

    @MainActor
    private func makeDiskBackedResetApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-reset-persistent-store",
            "--uitest-force-signed-out-auth",
        ] + extraArguments
        return app
    }

    @MainActor
    private func makeDiskBackedApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        if extraArguments.isEmpty {
            app.launchArguments = ["--uitest-force-signed-out-auth"]
        } else {
            app.launchArguments = extraArguments.contains("--uitest-force-signed-in-auth")
                ? extraArguments
                : ["--uitest-force-signed-out-auth"] + extraArguments
        }
        return app
    }

    @MainActor
    private func openFinishWorkoutSheet(in app: XCUIApplication) {
        let finishButton = app.buttons["FinishWorkoutButton"]
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
    private func confirmStartFromPastWorkout(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["StartFromPastWorkoutConfirmButton"].waitForExistence(timeout: 3))
        app.buttons["StartFromPastWorkoutConfirmButton"].tap()
    }

    @MainActor
    private func setCompletedWorkoutDuration(minutes: Int, in app: XCUIApplication) {
        let durationButton = app.buttons["CompletedWorkoutDurationButton"]
        XCTAssertTrue(durationButton.waitForExistence(timeout: 3))
        durationButton.tap()

        XCTAssertTrue(app.navigationBars["Duration"].waitForExistence(timeout: 3))
        let fiveMinuteIncrementButton = app.buttons["DurationMinutesIncrementFiveButton"]
        XCTAssertTrue(fiveMinuteIncrementButton.waitForExistence(timeout: 3))
        for _ in 0..<(minutes / 5) {
            fiveMinuteIncrementButton.tap()
        }

        let minuteIncrementButton = app.buttons["DurationMinutesIncrementButton"]
        XCTAssertTrue(minuteIncrementButton.waitForExistence(timeout: 3))
        for _ in 0..<(minutes % 5) {
            minuteIncrementButton.tap()
        }
        XCTAssertTrue(app.staticTexts["CompletedWorkoutDurationPreview"].label.contains("\(minutes) min"))
        app.buttons["DoneDurationEditButton"].tap()
        XCTAssertTrue(durationButton.waitForExistence(timeout: 3))
    }

    @MainActor
    private func assertRemovedDraftHistorySetDoesNotReuseCachedNumberText(in app: XCUIApplication) {
        app.buttons["AddHistorySetButton-0"].tap()
        let draftWeightField = app.textFields["HistorySetWeightField-0-1"]
        XCTAssertTrue(draftWeightField.waitForExistence(timeout: 3))
        replaceText(in: draftWeightField, with: "155.")
        XCTAssertEqual(draftWeightField.value as? String, "155.")
        dismissKeyboardIfNeeded(in: app)

        app.buttons["RemoveHistorySetButton-0-1"].tap()
        let removeButton = app.alerts.buttons["Remove"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 3))
        removeButton.tap()

        app.buttons["AddHistorySetButton-0"].tap()
        let replacementWeightField = app.textFields["HistorySetWeightField-0-1"]
        XCTAssertTrue(replacementWeightField.waitForExistence(timeout: 3))
        XCTAssertEqual(replacementWeightField.value as? String, "LBS")
    }

    @MainActor
    private func createCompletedBenchWorkout(in app: XCUIApplication, title: String) {
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["WorkoutTitle"], with: title)
        addBenchPress(in: app)
        fillFirstBenchSet(in: app)
        enterRPEViaChips("8", in: app)
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
        enterRPEViaChips(rpe, in: app)
        app.buttons["SetCompletionButton-0-0"].tap()
        dismissKeyboardIfNeeded(in: app)
        openFinishWorkoutSheet(in: app)
        XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
        app.buttons["SaveWorkoutButton"].tap()
        XCTAssertTrue(app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func assertClearingCompletedSetField(fieldIdentifier: String, expectedHistorySummary: String) {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addBenchPress(in: app)
        fillFirstBenchSet(in: app)
        enterRPEViaChips("8", in: app)
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
    }

    @MainActor
    private func enterRPEViaChips(_ value: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["RPEToolbarButton"].waitForExistence(timeout: 3))
        app.buttons["RPEToolbarButton"].tap()
        XCTAssertTrue(app.buttons["RPEChip-\(value)"].waitForExistence(timeout: 3))
        app.buttons["RPEChip-\(value)"].tap()
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
