import XCTest

final class BarosUITests: XCTestCase {
    @MainActor
    func testStartBlankWorkoutFlow() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 3))
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["EmptyHistorySignInButton"].exists)
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
    func testFinishWorkoutSheetCommitsTitleWhenDismissedInteractively() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        openFinishWorkoutSheet(in: app)
        let finishTitleField = app.textFields["FinishWorkoutTitleField"]
        XCTAssertTrue(finishTitleField.waitForExistence(timeout: 3))
        replaceText(in: finishTitleField, with: "Dismissed Push")

        let sheetTitle = app.staticTexts["Finish Workout?"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 3))
        let start = sheetTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertFalse(app.buttons["KeepGoingButton"].waitForExistence(timeout: 2))
        let activeTitleField = app.textFields["WorkoutTitle"]
        XCTAssertTrue(activeTitleField.waitForExistence(timeout: 3))
        XCTAssertEqual(activeTitleField.value as? String, "Dismissed Push")
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
    func testLogWorkoutSmoke() {
        let app = makeApp(extraArguments: ["--uitest-disable-animations"])
        app.launch()

        createCompletedBenchWorkout(in: app)

        app.buttons["HistoryTab"].tap()
        let completedWorkout = app.buttons["WorkoutHistoryButton-0"]
        XCTAssertTrue(completedWorkout.waitForExistence(timeout: 3))
        completedWorkout.tap()

        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
        let setSummary = app.staticTexts
            .matching(identifier: "WorkoutHistorySetSummary-0-0")
            .matching(NSPredicate(format: "label == %@", "185 x 5 @ 8 · Done"))
            .firstMatch
        XCTAssertTrue(setSummary.waitForExistence(timeout: 3))
        XCTAssertEqual(setSummary.label, "185 x 5 @ 8 · Done")
    }

    @MainActor
    func testFirstRunWelcomeAppearsOnce() {
        let firstLaunch = makeDiskBackedResetApp(extraArguments: ["--uitest-reset-first-run-experience"])
        firstLaunch.launch()

        XCTAssertTrue(firstLaunch.staticTexts["LaunchExperienceTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(firstLaunch.staticTexts["Welcome to Baros"].exists)
        XCTAssertTrue(firstLaunch.staticTexts["Fast workout logging"].exists)
        XCTAssertTrue(firstLaunch.staticTexts["Your history stays put"].exists)
        XCTAssertTrue(firstLaunch.staticTexts["Optional cloud sync"].exists)
        XCTAssertTrue(firstLaunch.staticTexts["Control your data"].exists)

        firstLaunch.buttons["LaunchExperiencePrimaryButton"].tap()
        XCTAssertFalse(firstLaunch.staticTexts["LaunchExperienceTitle"].waitForExistence(timeout: 1))
        firstLaunch.terminate()

        let secondLaunch = makeDiskBackedApp(skipsFirstRunExperience: false)
        secondLaunch.launch()

        XCTAssertFalse(secondLaunch.staticTexts["Welcome to Baros"].waitForExistence(timeout: 1))
        XCTAssertTrue(secondLaunch.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsCanOpenWhatsNew() {
        let app = makeApp()
        app.launch()

        app.buttons["ProfileTab"].tap()
        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))
        app.buttons["ProfileSettingsLink"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let whatsNewButton = app.buttons["SettingsWhatsNewButton"]
        for _ in 0..<5 where !whatsNewButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(whatsNewButton.exists)
        XCTAssertTrue(whatsNewButton.isHittable)
        whatsNewButton.tap()

        XCTAssertTrue(app.staticTexts["LaunchExperienceTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["What's new in Baros"].exists)
        XCTAssertTrue(app.staticTexts["Cloud sync"].exists)
    }

    @MainActor
    func testSettingsShowsGitHubRepositoryLink() {
        let app = makeApp()
        app.launch()

        app.buttons["ProfileTab"].tap()
        XCTAssertTrue(app.staticTexts["ProfileTitle"].waitForExistence(timeout: 3))
        app.buttons["ProfileSettingsLink"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let githubLink = app.buttons["SettingsGitHubLink"]
        for _ in 0..<5 where !githubLink.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(githubLink.exists)
        XCTAssertTrue(githubLink.isHittable)
        XCTAssertEqual(githubLink.label, "View on GitHub")
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

        // Tap inside the visible rounded field, but outside its centered text.
        // The entire field surface should focus the input, not just the glyphs.
        firstWeightField.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
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
    func testExercisePickerShowsPerformanceSummaryAndInlineSortMenu() {
        let app = makeApp(completedBenchWorkoutTitles: ["Past Push"])
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        app.buttons["AddExerciseButton"].tap()
        XCTAssertTrue(app.navigationBars["Add Exercise"].waitForExistence(timeout: 3))

        let sortMenu = app.buttons["ExercisePickerSortMenu"]
        XCTAssertTrue(sortMenu.waitForExistence(timeout: 3))
        XCTAssertEqual(sortMenu.label, "Sort: Recent")

        let benchPressRow = app.buttons["ExercisePickerRow-Bench Press-Barbell"]
        XCTAssertTrue(benchPressRow.waitForExistence(timeout: 3))
        XCTAssertTrue(benchPressRow.label.contains("Last: "))
        XCTAssertTrue(benchPressRow.label.contains("· 1 workout"))
    }

    @MainActor
    func testExercisePickerPersistsSortSelectionAcrossRelaunch() {
        addTeardownBlock { @MainActor in
            let cleanupApp = self.makeDiskBackedApp(
                extraArguments: ["--uitest-reset-exercise-picker-sort"]
            )
            cleanupApp.launch()
            cleanupApp.terminate()
        }

        let app = makeDiskBackedResetApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        app.buttons["AddExerciseButton"].tap()

        let sortMenu = app.buttons["ExercisePickerSortMenu"]
        XCTAssertTrue(sortMenu.waitForExistence(timeout: 3))
        XCTAssertEqual(sortMenu.label, "Sort: Recent")
        sortMenu.tap()
        let nameSortButton = app.buttons["Name"]
        XCTAssertTrue(nameSortButton.waitForExistence(timeout: 3))
        nameSortButton.tap()
        XCTAssertEqual(sortMenu.label, "Sort: Name")
        app.buttons["Done"].tap()
        app.terminate()

        let relaunchedApp = makeDiskBackedApp()
        relaunchedApp.launch()
        XCTAssertTrue(relaunchedApp.buttons["AddExerciseButton"].waitForExistence(timeout: 3))
        relaunchedApp.buttons["AddExerciseButton"].tap()

        let persistedSortMenu = relaunchedApp.buttons["ExercisePickerSortMenu"]
        XCTAssertTrue(persistedSortMenu.waitForExistence(timeout: 3))
        XCTAssertEqual(persistedSortMenu.label, "Sort: Name")
    }

    @MainActor
    func testAddingExerciseScrollsNewExerciseToTopWhileEditing() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("ExercisePickerRow-Back Squat-Barbell", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("ExercisePickerRow-Bench Press-Barbell", in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let addedExerciseHeader = app.buttons["ExerciseHeader-1"]
        XCTAssertTrue(addedExerciseHeader.waitForExistence(timeout: 3))
        XCTAssertTrue(
            waitForElement(addedExerciseHeader, maxYOrigin: 150, timeout: 3),
            "Expected ExerciseHeader-1 to scroll near the top, got minY \(addedExerciseHeader.frame.minY)"
        )

        dismissKeyboardIfNeeded(in: app)
        XCTAssertTrue(addedExerciseHeader.isHittable)
    }

    @MainActor
    func testExerciseMenuHidesReorderWithOneExercise() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)

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

        addExercise("ExercisePickerRow-Back Squat-Barbell", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("ExercisePickerRow-Bench Press-Barbell", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("ExercisePickerRow-Conventional Deadlift-Barbell", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("ExercisePickerRow-Overhead Press-Barbell", in: app)
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
    func testWorkoutNoteActionAppearsBetweenWorkoutDateAndFirstExercise() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)

        let workoutDate = app.staticTexts["WorkoutDate"]
        let addNoteButton = app.buttons["AddWorkoutNoteButton"]
        let firstExercise = app.buttons["ExerciseHeader-0"]
        XCTAssertTrue(workoutDate.waitForExistence(timeout: 3))
        XCTAssertTrue(addNoteButton.exists)
        XCTAssertTrue(app.staticTexts["Add workout note"].exists)
        XCTAssertTrue(firstExercise.exists)
        XCTAssertGreaterThanOrEqual(addNoteButton.frame.minY, workoutDate.frame.maxY)
        XCTAssertLessThanOrEqual(addNoteButton.frame.maxY, firstExercise.frame.minY)
    }

    @MainActor
    func testWorkoutNotesScrollsAboveKeyboardToolbarWhenFocused() {
        let app = makeApp()
        app.launch()

        let notesField = startBlankWorkoutAndRevealWorkoutNote(in: app)

        XCTAssertEqual(notesField.label, "Workout note")
        XCTAssertFalse(app.staticTexts["WORKOUT NOTES"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let doneButton = app.buttons["DismissKeyboardButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        XCTAssertLessThan(notesField.frame.maxY, doneButton.frame.minY - 8)
    }

    @MainActor
    func testEmptyWorkoutNoteReturnsToCompactStateAfterClearedNoteLosesFocus() {
        let app = makeApp()
        app.launch()

        let notesField = startBlankWorkoutAndRevealWorkoutNote(in: app)
        let addNoteButton = app.buttons["AddWorkoutNoteButton"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        notesField.typeText("Felt strong")
        app.buttons["DismissKeyboardButton"].tap()
        XCTAssertTrue(notesField.exists)

        replaceText(in: notesField, with: "")
        XCTAssertTrue(notesField.exists)
        app.buttons["DismissKeyboardButton"].tap()

        XCTAssertFalse(notesField.waitForExistence(timeout: 1))
        XCTAssertTrue(addNoteButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testExistingWorkoutNotePersistsAcrossBackgroundAndRelaunch() {
        let app = makeDiskBackedResetApp()
        app.launch()

        let notesField = startBlankWorkoutAndRevealWorkoutNote(in: app)
        notesField.typeText("Felt strong")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        XCTAssertEqual(notesField.value as? String, "Felt strong")
        app.terminate()

        let relaunchedApp = makeDiskBackedApp()
        relaunchedApp.launch()
        let relaunchedNotesField = relaunchedApp.textFields["WorkoutNotesField"]
        XCTAssertTrue(relaunchedNotesField.waitForExistence(timeout: 3))
        XCTAssertEqual(relaunchedNotesField.value as? String, "Felt strong")
        XCTAssertFalse(relaunchedApp.buttons["AddWorkoutNoteButton"].exists)
    }

    @MainActor
    func testExerciseNotesScrollsAboveKeyboardToolbarWhenFocused() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)

        let addNoteButton = app.buttons["AddExerciseNoteButton-0"]
        XCTAssertTrue(addNoteButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["ExerciseNotesField-0"].exists)
        addNoteButton.tap()

        let notesField = app.textFields["ExerciseNotesField-0"]
        for _ in 0..<6 where !notesField.exists || !notesField.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        // Tap the lower trailing padding, away from the placeholder glyphs.
        notesField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let doneButton = app.buttons["DismissKeyboardButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        XCTAssertLessThan(notesField.frame.maxY, doneButton.frame.minY - 8)
    }

    @MainActor
    func testEmptyExerciseNoteRevealsFocusesAndHidesOnlyAfterClearedNoteLosesFocus() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)

        let addNoteButton = app.buttons["AddExerciseNoteButton-0"]
        XCTAssertTrue(addNoteButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["ExerciseNotesField-0"].exists)

        addNoteButton.tap()
        let notesField = app.textFields["ExerciseNotesField-0"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["EXERCISE NOTE"].exists)
        XCTAssertEqual(notesField.label, "Exercise note")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        notesField.typeText("Pause reps")
        app.buttons["DismissKeyboardButton"].tap()
        XCTAssertTrue(notesField.exists)

        replaceText(in: notesField, with: "")
        XCTAssertTrue(notesField.exists)
        app.buttons["DismissKeyboardButton"].tap()

        XCTAssertFalse(notesField.waitForExistence(timeout: 1))
        XCTAssertTrue(addNoteButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testAccessibilityDynamicTypeUsesBorderlessTwoRowSetLayout() {
        let app = makeApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ])
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)

        let topRow = app.descendants(matching: .any)["SetAccessibilityTopRow-0-0"]
        let bottomRow = app.descendants(matching: .any)["SetAccessibilityBottomRow-0-0"]
        XCTAssertTrue(topRow.waitForExistence(timeout: 3))
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["SetPreviousLabel-0-0"].exists)
        XCTAssertTrue(app.staticTexts["SetWeightLabel-0-0"].exists)
        XCTAssertTrue(app.staticTexts["SetRepsLabel-0-0"].exists)
        XCTAssertGreaterThanOrEqual(bottomRow.frame.minY, topRow.frame.maxY)
        XCTAssertLessThanOrEqual(bottomRow.frame.maxX, app.windows.firstMatch.frame.maxX)
    }

    @MainActor
    func testMultipleStandardSetRowsStayWithinCompactPhoneWidth() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)

        addSets(2, in: app)

        let windowFrame = app.windows.firstMatch.frame
        for setIndex in 0..<3 {
            let weightField = app.textFields["SetWeightField-0-\(setIndex)"]
            let repsField = app.textFields["SetRepsField-0-\(setIndex)"]
            let completionButton = app.buttons["SetCompletionButton-0-\(setIndex)"]
            XCTAssertTrue(weightField.waitForExistence(timeout: 3))
            XCTAssertTrue(repsField.exists)
            XCTAssertTrue(completionButton.exists)
            XCTAssertGreaterThanOrEqual(weightField.frame.minX, windowFrame.minX)
            XCTAssertLessThan(weightField.frame.maxX, repsField.frame.minX)
            XCTAssertLessThan(repsField.frame.maxX, completionButton.frame.minX)
            XCTAssertLessThanOrEqual(completionButton.frame.maxX, windowFrame.maxX)
        }
    }

    @MainActor
    func testFinalStandardSetRowDoesNotHaveExtraBottomSpacing() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)

        addSets(2, in: app)

        let finalCompletionButton = app.buttons["SetCompletionButton-0-2"]
        let addSetButton = app.buttons["AddSetButton-0"]
        XCTAssertTrue(finalCompletionButton.waitForExistence(timeout: 3))
        XCTAssertTrue(addSetButton.exists)
        XCTAssertLessThanOrEqual(addSetButton.frame.minY - finalCompletionButton.frame.maxY, 8)
    }

    @MainActor
    func testAddExerciseNoteActionFollowsSetSection() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)

        let addSetButton = app.buttons["AddSetButton-0"]
        let addNoteButton = app.buttons["AddExerciseNoteButton-0"]
        XCTAssertTrue(addSetButton.waitForExistence(timeout: 3))
        XCTAssertTrue(addNoteButton.exists)
        XCTAssertGreaterThanOrEqual(addNoteButton.frame.minY, addSetButton.frame.maxY)
    }

    @MainActor
    func testEmptyRevealedExerciseNoteReturnsToCompactStateAfterCollapse() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)
        app.buttons["AddExerciseNoteButton-0"].tap()
        XCTAssertTrue(app.textFields["ExerciseNotesField-0"].waitForExistence(timeout: 3))

        app.buttons["ExerciseHeader-0"].tap()
        app.buttons["ExerciseHeader-0"].tap()

        XCTAssertFalse(app.textFields["ExerciseNotesField-0"].exists)
        XCTAssertTrue(app.buttons["AddExerciseNoteButton-0"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEmptyRevealedExerciseNoteReturnsToCompactStateAfterNavigation() {
        let app = makeApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)
        app.buttons["AddExerciseNoteButton-0"].tap()
        XCTAssertTrue(app.textFields["ExerciseNotesField-0"].waitForExistence(timeout: 3))

        app.buttons["ExerciseMenuButton-0"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()

        XCTAssertFalse(app.textFields["ExerciseNotesField-0"].exists)
        XCTAssertTrue(app.buttons["AddExerciseNoteButton-0"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testExistingExerciseNotePersistsAcrossBackgroundAndRelaunch() {
        let app = makeDiskBackedResetApp()
        app.launch()
        startBlankWorkoutWithBenchPress(in: app)
        app.buttons["AddExerciseNoteButton-0"].tap()
        let notesField = app.textFields["ExerciseNotesField-0"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        notesField.typeText("Pause reps")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        XCTAssertEqual(notesField.value as? String, "Pause reps")
        app.terminate()

        let relaunchedApp = makeDiskBackedApp()
        relaunchedApp.launch()
        let relaunchedNotesField = relaunchedApp.textFields["ExerciseNotesField-0"]
        XCTAssertTrue(relaunchedNotesField.waitForExistence(timeout: 3))
        XCTAssertEqual(relaunchedNotesField.value as? String, "Pause reps")
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
        let completedNotesField = app.textFields["CompletedWorkoutNotesField"]
        // Exercise the lower trailing padding inside the visible field border.
        completedNotesField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        completedNotesField.typeText("Post edit notes")
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
            exerciseRowIdentifier: "ExercisePickerRow-Variant Bench-Barbell",
            title: "Barbell Variant",
            weight: "185",
            reps: "5",
            rpe: "8",
            in: app
        )
        createCompletedWorkout(
            exerciseRowIdentifier: "ExercisePickerRow-Variant Bench-Dumbbell",
            title: "Dumbbell Variant",
            weight: "70",
            reps: "8",
            rpe: "7",
            in: app
        )

        app.buttons["WorkoutTab"].tap()
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addExercise("ExercisePickerRow-Variant Bench-Dumbbell", in: app)
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
    func testStartingFromPastWorkoutDoesNotShowNarrativeReferenceNotes() {
        let app = makeApp(
            extraArguments: ["--uitest-seed-history-exercise-note"],
            completedBenchWorkoutTitles: ["Past Push"]
        )
        app.launch()

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.buttons["PastWorkoutButton-0"].waitForExistence(timeout: 3))
        app.buttons["PastWorkoutButton-0"].tap()
        confirmStartFromPastWorkout(in: app)

        XCTAssertTrue(app.buttons["SetPreviousValue-0-0"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["LAST TIME"].exists)
        XCTAssertFalse(app.staticTexts["Pause at the bottom\nKeep wrists stacked"].exists)
        XCTAssertFalse(app.staticTexts["Previous workout narrative"].exists)
    }

    @MainActor
    func testQuickExerciseHistoryShowsPerformanceSummaryAndFlattenedExerciseNotes() {
        let app = makeApp(
            extraArguments: [
                "--uitest-seed-history-exercise-note",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ],
            completedBenchWorkoutTitles: ["Past Push"]
        )
        app.launch()

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.buttons["PastWorkoutButton-0"].waitForExistence(timeout: 3))
        app.buttons["PastWorkoutButton-0"].tap()
        confirmStartFromPastWorkout(in: app)

        let weightField = app.textFields["SetWeightField-0-0"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 3))
        weightField.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))

        XCTAssertTrue(app.buttons["ExerciseMenuButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseMenuButton-0"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()

        let historyHeading = app.descendants(matching: .any)
            .matching(identifier: "QuickExerciseHistoryHeading")
            .firstMatch
        XCTAssertTrue(historyHeading.waitForExistence(timeout: 3))
        guard historyHeading.exists else { return }
        XCTAssertFalse(keyboard.exists)
        XCTAssertTrue(historyHeading.label.contains("· 1 workout · 1 set"))
        XCTAssertTrue(app.buttons["Done"].exists)
        XCTAssertTrue(app.buttons["Full History"].exists)
        XCTAssertFalse(app.staticTexts["QuickHistoryLimitFooter"].exists)
        let setLabel = app.staticTexts["Set 1"]
        let noteText = app.staticTexts["ExerciseHistoryNoteText"]
        XCTAssertTrue(setLabel.waitForExistence(timeout: 3))
        XCTAssertTrue(noteText.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["ExerciseHistoryNoteLabel"].exists)
        XCTAssertEqual(noteText.label, "Exercise note")
        XCTAssertEqual(noteText.value as? String, "Pause at the bottom\nKeep wrists stacked")
        XCTAssertEqual(noteText.frame.minX, setLabel.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(noteText.frame.height, setLabel.frame.height)
        app.buttons["Done"].tap()
        XCTAssertFalse(keyboard.waitForExistence(timeout: 1))
    }

    @MainActor
    func testQuickExerciseHistoryExplainsTruncatedRecentWorkouts() {
        let app = makeApp(
            completedBenchWorkoutTitles: ["Push One", "Push Two", "Push Three", "Push Four"]
        )
        app.launch()

        app.buttons["WorkoutTab"].tap()
        XCTAssertTrue(app.buttons["PastWorkoutButton-0"].waitForExistence(timeout: 3))
        app.buttons["PastWorkoutButton-0"].tap()
        confirmStartFromPastWorkout(in: app)

        let weightField = app.textFields["SetWeightField-0-0"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 3))
        weightField.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))

        XCTAssertTrue(app.buttons["ExerciseMenuButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseMenuButton-0"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        app.buttons["ExerciseHistoryButton-0"].tap()

        let footer = app.staticTexts["QuickHistoryLimitFooter"]
        XCTAssertTrue(footer.waitForExistence(timeout: 3))
        XCTAssertFalse(keyboard.exists)
        XCTAssertTrue(footer.label.contains("Showing 3 of 4 workouts"))

        let viewAllButton = app.buttons["QuickHistoryViewAllButton"]
        XCTAssertTrue(viewAllButton.exists)
        viewAllButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["ExerciseHistoryHeading"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(keyboard.waitForExistence(timeout: 1))
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
    func testExerciseHistoryHeadingShowsPerformanceSummary() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addExercise("ExercisePickerRow-Bench Press-Barbell", in: app)
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

        let historyHeading = app.descendants(matching: .any)
            .matching(identifier: "ExerciseHistoryHeading")
            .firstMatch
        XCTAssertTrue(historyHeading.waitForExistence(timeout: 3))
        guard historyHeading.exists else { return }
        XCTAssertTrue(historyHeading.label.contains("· 1 workout · 1 set"))
    }

    @MainActor
    func testExerciseHistoryRowShowsPerformanceSummaryInsteadOfSetMultiplier() {
        let app = makeApp(completedBenchWorkoutTitles: ["Past Push"])
        app.launch()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()

        let historyRow = app.buttons["ExerciseHistoryButton-0"]
        XCTAssertTrue(historyRow.waitForExistence(timeout: 3))
        XCTAssertTrue(historyRow.label.contains("Last: "))
        XCTAssertTrue(historyRow.label.contains("· 1 workout"))
        XCTAssertFalse(historyRow.label.contains("x1"))
    }

    @MainActor
    func testIrrelevantActiveWorkoutAndForegroundChangesDoNotRebuildExerciseHistory() throws {
        let app = makeApp(extraArguments: [
            "--uitest-seed-exercise-history-performance",
            "--uitest-measure-exercise-history-invalidation",
        ])
        app.launch()

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 5))
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 10))
        let initialMetrics = try settledExerciseHistoryMetrics(in: app)

        app.buttons["WorkoutTab"].tap()
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 5))
        addBenchPress(in: app)
        dismissKeyboardIfNeeded(in: app)
        let beforeActiveEdit = try settledExerciseHistoryMetrics(in: app)

        app.textFields["SetWeightField-0-0"].tap()
        app.textFields["SetWeightField-0-0"].typeText("185")
        dismissKeyboardIfNeeded(in: app)
        let afterActiveEdit = try settledExerciseHistoryMetrics(in: app)

        XCTAssertEqual(
            afterActiveEdit.resolutions,
            beforeActiveEdit.resolutions,
            "Active Workout field changes rebuilt unchanged completed Exercise History"
        )

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 10))
        let beforeForeground = try settledExerciseHistoryMetrics(in: app)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 10))
        let afterForeground = try settledExerciseHistoryMetrics(in: app)

        print(
            "HISTORY_INVALIDATION_METRICS "
                + "sessions=100 exercises=20 completedSets=3000 "
                + "initialResolutions=\(initialMetrics.resolutions) "
                + "beforeActiveEditResolutions=\(beforeActiveEdit.resolutions) "
                + "afterActiveEditResolutions=\(afterActiveEdit.resolutions) "
                + "beforeForegroundResolutions=\(beforeForeground.resolutions) "
                + "afterForegroundResolutions=\(afterForeground.resolutions) "
                + "totalResolutionTimeMilliseconds=\(afterForeground.resolutionTimeMilliseconds)"
        )
        XCTAssertEqual(
            afterForeground.resolutions,
            beforeForeground.resolutions,
            "Foreground return rebuilt unchanged completed Exercise History"
        )
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

        tapTab(identifier: "ProfileTab", label: "Profile", in: app)
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
        app.swipeUp()
        let syncSummary = app.staticTexts["DeveloperDiagnosticsSyncSummary"]
        XCTAssertTrue(syncSummary.waitForExistence(timeout: 3))
        XCTAssertTrue(syncSummary.label.contains("lastFailure: Convex function sync:fetchChanges failed for token issuer|ui_owner"))
    }

    @MainActor
    func testSettingsSyncRetryRequestsSyncInUITestMode() {
        let app = makeApp(extraArguments: [
            "--uitest-sync-owner", "issuer|ui_owner",
            "--uitest-show-sync-failure",
        ])
        app.launch()

        app.buttons["GlobalSyncDetailsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let settingsRetryButton = app.buttons["SettingsSyncRetryButton"]
        XCTAssertTrue(settingsRetryButton.waitForExistence(timeout: 3))
        settingsRetryButton.tap()

        XCTAssertTrue(app.staticTexts["UITestSyncRequestCount-1"].waitForExistence(timeout: 3))
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

        tapTab(identifier: "ProfileTab", label: "Profile", in: app)
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
        XCTAssertEqual(app.staticTexts["ProfileAccountTitle"].label, "Local workout data")
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
    func testOfflineColdLaunchWithCachedOwnerPreservesOwnerScopedData() {
        let owner = "issuer|offline_cached_owner"
        let app = makeDiskBackedResetApp(extraArguments: [
            "--uitest-sync-owner", owner,
            "--uitest-seed-completed-bench-workout", "Offline Cached Owner Push",
        ])
        app.launch()

        app.buttons["ProfileTab"].tap()
        app.buttons["ProfileSettingsLink"].tap()
        XCTAssertTrue(app.segmentedControls["WeightUnitPicker"].waitForExistence(timeout: 3))
        app.segmentedControls["WeightUnitPicker"].buttons["Kilograms"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["ProfileExerciseLibraryLink"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3))
        createExercise(name: "Aardvark Offline Press", equipment: "Barbell", muscle: "Chest", in: app)
        XCTAssertTrue(app.buttons["ExerciseLibraryRow-Aardvark Offline Press-Barbell"].waitForExistence(timeout: 3))
        app.terminate()

        let relaunchedApp = makeDiskBackedApp(extraArguments: [
            "--uitest-force-signed-in-auth",
            "--uitest-restore-cached-sync-owner",
            "--uitest-restore-cached-sync-owner-subject", "offline_cached_owner",
        ])
        relaunchedApp.launch()

        relaunchedApp.buttons["ProfileTab"].tap()
        XCTAssertTrue(relaunchedApp.staticTexts["KG"].waitForExistence(timeout: 3))
        relaunchedApp.buttons["ProfileExerciseLibraryLink"].tap()
        XCTAssertTrue(relaunchedApp.navigationBars["Exercises"].waitForExistence(timeout: 3))
        XCTAssertTrue(relaunchedApp.buttons["ExerciseLibraryRow-Aardvark Offline Press-Barbell"].waitForExistence(timeout: 3))

        relaunchedApp.buttons["HistoryTab"].tap()
        XCTAssertTrue(relaunchedApp.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        relaunchedApp.buttons["WorkoutHistoryButton-0"].tap()
        XCTAssertTrue(relaunchedApp.staticTexts["Offline Cached Owner Push"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSwipeToDeleteSetRemovesSet() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("ExercisePickerRow-Bench Press-Barbell", in: app)
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
    func testSignedOutEmptyHistorySurfacesShowSharedRecoveryPrompt() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Looking for past workouts?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sign in to sync workouts saved to your account and keep future workouts backed up."].exists)
        let startSignInButton = app.buttons["EmptyHistorySignInButton"]
        XCTAssertTrue(startSignInButton.exists)
        XCTAssertEqual(startSignInButton.label, "Sign in")
        XCTAssertTrue(app.buttons["StartBlankWorkoutButton"].isHittable)

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.staticTexts["Looking for your workouts?"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["EmptyHistorySignInButton"].label, "Sign in")

        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.staticTexts["Looking for your exercise history?"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["EmptyHistorySignInButton"].label, "Sign in")
    }

    @MainActor
    func testEmptyHistorySignInPresentsExistingAuthAndCancellationReturnsToPrompt() {
        let app = makeApp()
        app.launch()

        let signInButton = app.buttons["EmptyHistorySignInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 3))
        signInButton.tap()

        let authView = app.descendants(matching: .any)["EmptyHistoryAuthView"]
        XCTAssertTrue(authView.waitForExistence(timeout: 5))
        app.swipeDown()

        XCTAssertTrue(signInButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Looking for past workouts?"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    func testIdleResolvingCurrentOwnerFallsBackWithoutShowingSignIn() {
        let app = makeApp(extraArguments: ["--uitest-restore-cached-sync-owner"])
        app.launch()

        XCTAssertTrue(app.staticTexts["No Past Workouts"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["EmptyHistorySignInButton"].exists)
        XCTAssertFalse(app.staticTexts["Syncing your workout history…"].exists)
    }

    @MainActor
    func testEmptyHistoryShowsSyncingDuringAuthenticatedRecovery() {
        let app = makeApp(extraArguments: ["--uitest-simulate-empty-history-auth-recovery"])
        app.launch()

        let signInButton = app.buttons["EmptyHistorySignInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 3))
        signInButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["EmptyHistoryAuthView"].waitForExistence(timeout: 5))

        let simulateAuthenticationButton = app.buttons["UITestSimulateEmptyHistoryAuthenticationButton"]
        XCTAssertTrue(simulateAuthenticationButton.waitForExistence(timeout: 3))
        simulateAuthenticationButton.tap()

        XCTAssertTrue(app.staticTexts["Syncing your workout history…"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["EmptyHistorySignInButton"].exists)
        XCTAssertFalse(app.staticTexts["No Past Workouts"].exists)

        XCTAssertTrue(app.staticTexts["No Past Workouts"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Syncing your workout history…"].exists)
    }

    @MainActor
    func testActiveCurrentOwnerWithNoRemoteHistoryShowsOrdinaryEmptyState() {
        let app = makeApp(extraArguments: [
            "--uitest-sync-owner", "issuer|ui_owner",
            "--uitest-force-signed-in-auth",
        ])
        app.launch()

        XCTAssertTrue(app.staticTexts["No Past Workouts"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["EmptyHistorySignInButton"].exists)
        XCTAssertFalse(app.staticTexts["Syncing your workout history…"].exists)
    }

    @MainActor
    func testVisibleUnclaimedLocalHistorySuppressesRecoveryPrompt() {
        let app = makeApp(completedBenchWorkoutTitles: ["Visible Local History"])
        app.launch()

        XCTAssertTrue(app.buttons["PastWorkoutButton-0"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["EmptyHistorySignInButton"].exists)

        app.buttons["HistoryTab"].tap()
        XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["EmptyHistorySignInButton"].exists)

        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["ExerciseHistoryButton-0"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["EmptyHistorySignInButton"].exists)
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
        var launchArguments = [
            "--uitest-reset-persistent-store",
            "--uitest-in-memory-store",
            "--uitest-reset-exercise-picker-sort",
        ] + fixtureArguments + authArguments
        if !extraArguments.contains("--uitest-reset-first-run-experience") {
            launchArguments.append("--uitest-skip-first-run-experience")
        }
        launchArguments += extraArguments
        app.launchArguments = launchArguments
        app.terminate()
        return app
    }

    @MainActor
    private func makeDiskBackedResetApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = [
            "--uitest-reset-persistent-store",
            "--uitest-force-signed-out-auth",
            "--uitest-reset-exercise-picker-sort",
        ]
        if !extraArguments.contains("--uitest-reset-first-run-experience") {
            launchArguments.append("--uitest-skip-first-run-experience")
        }
        launchArguments += extraArguments
        app.launchArguments = launchArguments
        return app
    }

    @MainActor
    private func makeDiskBackedApp(
        extraArguments: [String] = [],
        skipsFirstRunExperience: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments: [String]
        if extraArguments.isEmpty {
            launchArguments = ["--uitest-force-signed-out-auth"]
        } else {
            launchArguments = extraArguments.contains("--uitest-force-signed-in-auth")
                ? extraArguments
                : ["--uitest-force-signed-out-auth"] + extraArguments
        }
        if skipsFirstRunExperience && !extraArguments.contains("--uitest-reset-first-run-experience") {
            launchArguments.append("--uitest-skip-first-run-experience")
        }
        app.launchArguments = launchArguments
        return app
    }

    @MainActor
    private func settledExerciseHistoryMetrics(
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) throws -> (resolutions: Int, resolutionTimeMilliseconds: Double) {
        let element = app.staticTexts["UITestExerciseHistoryMetrics"]
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let refreshButton = app.buttons["UITestExerciseHistoryMetricsRefresh"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: timeout))

        var previous: (resolutions: Int, resolutionTimeMilliseconds: Double)?
        var stableReads = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            refreshButton.tap()
            let current = try parseExerciseHistoryMetrics(element.label)
            if current.resolutions == previous?.resolutions {
                stableReads += 1
                if stableReads >= 3 {
                    return current
                }
            } else {
                previous = current
                stableReads = 0
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        refreshButton.tap()
        return try parseExerciseHistoryMetrics(element.label)
    }

    private func parseExerciseHistoryMetrics(
        _ label: String
    ) throws -> (resolutions: Int, resolutionTimeMilliseconds: Double) {
        var values: [String: String] = [:]
        for component in label.split(separator: " ") {
            let parts = component.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1])
        }
        return (
            try XCTUnwrap(values["resolutions"].flatMap(Int.init)),
            try XCTUnwrap(values["resolutionTimeMilliseconds"].flatMap(Double.init))
        )
    }

    @MainActor
    private func tapTab(identifier: String, label: String, in app: XCUIApplication) {
        let identifiedTab = app.buttons[identifier]
        if identifiedTab.waitForExistence(timeout: 5) {
            identifiedTab.tap()
            return
        }

        let labeledTab = app.buttons[label]
        XCTAssertTrue(labeledTab.waitForExistence(timeout: 2))
        labeledTab.tap()
    }

    @MainActor
    private func openFinishWorkoutSheet(in app: XCUIApplication) {
        let finishButton = app.buttons["FinishWorkoutButton"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 3))
        finishButton.tap()

        XCTAssertTrue(
            app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3)
                || app.buttons["KeepGoingButton"].waitForExistence(timeout: 3)
        )
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
    private func createCompletedBenchWorkout(in app: XCUIApplication, title: String? = nil) {
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        if let title {
            replaceText(in: app.textFields["WorkoutTitle"], with: title)
        }
        addBenchPress(in: app)
        fillFirstBenchSet(in: app)
        enterRPEViaChips("8", in: app)
        app.buttons["SetCompletionButton-0-0"].tap()
        dismissKeyboardIfNeeded(in: app)
        openFinishWorkoutSheet(in: app)
        let saveButton = app.buttons["SaveWorkoutButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()
        XCTAssertTrue(app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func createCompletedWorkout(
        exerciseRowIdentifier: String,
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
        addExercise(exerciseRowIdentifier, in: app)
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
        addExercise("ExercisePickerRow-Bench Press-Barbell", in: app)
        XCTAssertTrue(app.textFields["SetWeightField-0-0"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func startBlankWorkoutWithBenchPress(in app: XCUIApplication) {
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addBenchPress(in: app)
        dismissKeyboardIfNeeded(in: app)
    }

    @MainActor
    private func startBlankWorkoutAndRevealWorkoutNote(in app: XCUIApplication) -> XCUIElement {
        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        let addNoteButton = app.buttons["AddWorkoutNoteButton"]
        for _ in 0..<6 where !addNoteButton.exists || !addNoteButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(addNoteButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["WorkoutNotesField"].exists)
        addNoteButton.tap()

        let notesField = app.textFields["WorkoutNotesField"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        return notesField
    }

    @MainActor
    private func addSets(_ count: Int, in app: XCUIApplication) {
        for _ in 0..<count {
            app.buttons["AddSetButton-0"].tap()
            dismissKeyboardIfNeeded(in: app)
        }
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
    private func addExercise(_ exerciseRowIdentifier: String, in app: XCUIApplication) {
        let addButton = app.buttons["AddExerciseButton"]

        for _ in 0..<8 {
            if addButton.exists && addButton.isHittable {
                addButton.tap()
                if app.navigationBars["Add Exercise"].waitForExistence(timeout: 1) {
                    for _ in 0..<8 {
                        let exerciseButton = app.buttons[exerciseRowIdentifier]
                        let navigationBar = app.navigationBars["Add Exercise"]
                        let searchField = app.searchFields.firstMatch
                        let isFullyVisible = exerciseButton.exists
                            && exerciseButton.frame.minY >= navigationBar.frame.maxY
                            && exerciseButton.frame.maxY <= searchField.frame.minY
                        if isFullyVisible && exerciseButton.isHittable {
                            exerciseButton.tap()
                            return
                        }

                        app.swipeUp()
                    }

                    XCTFail("Could not find exercise button \(exerciseRowIdentifier)")
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
