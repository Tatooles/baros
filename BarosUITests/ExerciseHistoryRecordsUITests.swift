import XCTest

@MainActor
final class ExerciseHistoryRecordsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRecordsStayInformationalAndMarkTheirSourceSets() {
        let app = openRecords()
        let heaviest = app.descendants(matching: .any)["ExerciseRecord-heaviestRep"]
        let estimate = app.descendants(matching: .any)["ExerciseRecord-estimated1RM"]
        XCTAssertTrue(heaviest.waitForExistence(timeout: 5))
        XCTAssertTrue(estimate.exists)
        XCTAssertFalse(app.buttons["ExerciseRecord-heaviestRep"].exists)
        XCTAssertFalse(app.buttons["ExerciseRecord-estimated1RM"].exists)
        XCTAssertTrue(heaviest.label.contains("Heaviest Rep, 225 lbs, from 225 lbs for 1 rep, Set 3,"))
        XCTAssertTrue(estimate.label.contains("Estimated 1RM, 245 lbs, from 210 lbs for 5 reps, Set 2,"))
        attachScreenshot(named: "Strength records summary", app: app)

        let info = app.buttons["AboutStrengthRecordsButton"]
        info.tap()
        XCTAssertTrue(app.navigationBars["About strength records"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The estimate does not account for effort."].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "A trophy marks a set")).firstMatch.exists)
        attachScreenshot(named: "Strength records explanation", app: app)
        app.buttons["Done"].tap()

        let values = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "ExerciseHistorySetValue-"))
        let heaviestValue = values.matching(NSPredicate(format: "label CONTAINS %@", "225 pounds, 1 rep")).firstMatch
        let estimateValue = values.matching(NSPredicate(format: "label CONTAINS %@", "210 pounds, 5 reps")).firstMatch
        for _ in 0..<5 where !estimateValue.isHittable { app.swipeUp() }
        XCTAssertEqual(heaviestValue.label, "Set 3, 225 pounds, 1 rep, Heaviest Rep")
        XCTAssertEqual(estimateValue.label, "Set 2, 210 pounds, 5 reps, Estimated 1RM")
        XCTAssertEqual(values.count, 6)
        XCTAssertFalse(app.staticTexts["Set 3"].exists, app.debugDescription)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ExerciseRecordBadge-")).count, 0)
        attachScreenshot(named: "Inline source record glyphs", app: app)
    }

    func testRecordsAndBadgesSupportAccessibilityTextSizes() {
        let app = openRecords(extraArguments: [
            "--uitest-accessibility-dynamic-type",
        ])
        XCTAssertTrue(app.descendants(matching: .any)["ExerciseRecord-heaviestRep"].waitForExistence(timeout: 5))
        let badge = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "ExerciseHistorySetValue-", "Estimated 1RM")).firstMatch
        for _ in 0..<12 where !badge.isHittable { app.swipeUp() }
        XCTAssertTrue(badge.isHittable)
        XCTAssertGreaterThanOrEqual(badge.frame.minX, 0)
        XCTAssertLessThanOrEqual(badge.frame.maxX, app.frame.maxX)
        attachScreenshot(named: "Source badges at accessibility text size", app: app)
    }

    func testExerciseHistoryDetailPresentsJournalSectionsAndCompleteSetAnnouncements() {
        for appearance in ["dark", "light"] {
            let app = openRecords(extraArguments: ["-Baros.AppAppearance.preference", appearance])

            XCTAssertTrue(app.staticTexts["Records"].exists)
            XCTAssertTrue(app.buttons["AboutStrengthRecordsButton"].exists)

            let sourceWorkout = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "ExercisePerformanceWorkoutButton-")
            ).firstMatch
            XCTAssertTrue(sourceWorkout.waitForExistence(timeout: 3))
            XCTAssertTrue(sourceWorkout.label.contains("Upper Body"))
            XCTAssertTrue(sourceWorkout.label.contains("3 sets"))
            XCTAssertGreaterThanOrEqual(sourceWorkout.frame.height, 44)

            let values = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "ExerciseHistorySetValue-")
            )
            XCTAssertEqual(values.count, 6)
            let heaviest = values.matching(NSPredicate(format: "label CONTAINS %@", "Heaviest Rep")).firstMatch
            XCTAssertEqual(heaviest.label, "Set 3, 225 pounds, 1 rep, Heaviest Rep")
            XCTAssertTrue(app.staticTexts["3 sets"].exists)
            attachScreenshot(named: "exercise-no-rpe-\(appearance)", app: app)
            app.terminate()
        }
    }

    func testSparseHistoryAndDoubleBadgesWithLongWorkoutTitle() {
        for scenario in ["same-set", "no-estimate", "empty"] {
            let app = openRecords(extraArguments: ["--uitest-strength-records-scenario", scenario])
            switch scenario {
            case "same-set":
                let value = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "ExerciseHistorySetValue-"))
                    .matching(NSPredicate(format: "label CONTAINS %@", "225 pounds, 5 reps")).firstMatch
                for _ in 0..<5 where !value.isHittable { app.swipeUp() }
                XCTAssertTrue(value.isHittable)
                XCTAssertTrue(value.label.contains("Heaviest Rep"))
                XCTAssertTrue(value.label.contains("Estimated 1RM"))
                XCTAssertEqual(value.label, "Set 3, 225 pounds, 5 reps, Heaviest Rep, Estimated 1RM")
                XCTAssertFalse(app.staticTexts["Set 3"].exists)
                XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ExerciseRecordBadge-")).count, 0)
            case "no-estimate":
                XCTAssertTrue(app.staticTexts["No estimate yet"].waitForExistence(timeout: 3))
                XCTAssertFalse(app.descendants(matching: .any)["ExerciseRecord-estimated1RM"].exists)
            default:
                XCTAssertTrue(app.staticTexts["No records yet"].waitForExistence(timeout: 3))
                XCTAssertFalse(app.descendants(matching: .any)["ExerciseRecord-heaviestRep"].exists)
            }
            attachScreenshot(named: "Strength records \(scenario)", app: app)
            app.terminate()
        }
    }

    func testQuickHistoryUsesJournalRowsWithoutComputingRecords() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-reset-persistent-store", "--uitest-in-memory-store",
            "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-seed-strength-records",
        ]
        app.launch()
        let start = app.buttons["StartWorkoutButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        app.buttons["UsePastWorkoutButton"].tap()
        let pastWorkout = app.buttons["PastWorkoutButton-0"]
        XCTAssertTrue(pastWorkout.waitForExistence(timeout: 3))
        pastWorkout.tap()
        app.buttons["StartFromPastWorkoutConfirmButton"].tap()
        let menu = app.buttons["ExerciseMenuButton-0"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["QuickExerciseHistoryHeading"].waitForExistence(timeout: 5))

        let dates = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "ExerciseHistorySessionDate-"
        ))
        XCTAssertEqual(dates.count, 2)
        let values = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "ExerciseHistorySetValue-"
        ))
        XCTAssertEqual(values.count, 6)
        let heaviest = values.matching(NSPredicate(format: "label CONTAINS %@", "225 pounds")).firstMatch
        XCTAssertEqual(heaviest.label, "Set 3, 225 pounds, 1 rep")
        XCTAssertFalse(app.buttons["AboutStrengthRecordsButton"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["ExerciseRecord-heaviestRep"].exists)
        XCTAssertEqual(values.matching(NSPredicate(format: "label CONTAINS %@", "Estimated 1RM")).count, 0)
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "ExercisePerformanceWorkoutButton-"
        )).count, 2)
    }

    func testLongValuesAndDuplicateOccurrencesPreserveRecordSourceContext() {
        for (unit, size) in [("pounds", "UICTContentSizeCategoryL"), ("kilograms", "UICTContentSizeCategoryXXXL")] {
            let app = openRecords(extraArguments: [
                "--uitest-strength-records-scenario", "review-layout",
                "-UIPreferredContentSizeCategoryName", size,
            ], kilograms: unit == "kilograms")
            let record = app.descendants(matching: .any)["ExerciseRecord-heaviestRep"]
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            XCTAssertTrue(record.label.contains("Set 2,"))
            XCTAssertTrue(record.label.contains("2025"))
            let estimate = app.descendants(matching: .any)["ExerciseRecord-estimated1RM"]
            XCTAssertEqual(record.frame.width, estimate.frame.width, accuracy: 1)
            XCTAssertEqual(record.frame.height, estimate.frame.height, accuracy: 1)
            XCTAssertEqual(record.frame.minY, estimate.frame.minY, accuracy: 1)
            attachScreenshot(named: "review-record-source-\(unit)", app: app)

            let values = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@", "ExerciseHistorySetValue-"
            ))
            let longValue = values.matching(NSPredicate(format: "label CONTAINS %@", "1000 reps")).firstMatch
            for _ in 0..<8 where !longValue.isHittable { app.swipeUp() }
            XCTAssertTrue(longValue.isHittable)
            XCTAssertTrue(longValue.label.hasPrefix("Set 2,"))
            XCTAssertTrue(longValue.label.contains(unit))
            XCTAssertGreaterThanOrEqual(longValue.frame.minX, 32)
            XCTAssertLessThanOrEqual(longValue.frame.maxX, app.frame.maxX - 32)
            attachScreenshot(named: "review-long-values-\(unit)", app: app)

            let secondNote = app.staticTexts["Second occurrence note"]
            for _ in 0..<8 where !secondNote.isHittable { app.swipeUp() }
            XCTAssertTrue(secondNote.isHittable)
            XCTAssertEqual(values.count, 3)
            attachScreenshot(named: "review-duplicate-occurrences-\(unit)", app: app)
            app.terminate()
        }
    }

    func testRPEFitsAtLargestStandardTextSize() {
        let app = openRecords(extraArguments: [
            "--uitest-strength-records-scenario", "rpe-layout",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL",
        ])
        let values = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "ExerciseHistorySetValue-"
        ))
        for rpe in ["RPE 10", "RPE 9.5"] {
            let row = values.matching(NSPredicate(format: "label CONTAINS %@", rpe)).firstMatch
            for _ in 0..<8 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable)
            XCTAssertGreaterThanOrEqual(row.frame.minX, 32)
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX - 32)
            XCTAssertLessThan(row.frame.height, 40, "This fixture should keep the value and RPE on one line at XXXL.")
        }
        attachScreenshot(named: "history-rpe-largest-standard-text", app: app)
    }

    func testMaximumValuesWrapAcrossHistoryAtLargestAccessibilitySize() {
        let app = openRecords(extraArguments: [
            "--uitest-strength-records-scenario", "accessibility-limits",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        assertMaximumValuesFit(in: app, identifierPrefix: "ExerciseHistorySetValue-", screen: "exercise")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls["HistoryModePicker"].buttons["Workouts"].tap()
        let workout = app.buttons["WorkoutHistoryButton-0"]
        XCTAssertTrue(workout.waitForExistence(timeout: 3))
        workout.tap()
        assertMaximumValuesFit(in: app, identifierPrefix: "WorkoutHistorySetSummary-", screen: "workout")

        app.buttons["HomeTab"].tap()
        let start = app.buttons["StartWorkoutButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        app.buttons["UsePastWorkoutButton"].tap()
        let pastWorkout = app.buttons["PastWorkoutButton-0"]
        XCTAssertTrue(pastWorkout.waitForExistence(timeout: 3))
        pastWorkout.tap()
        let confirm = app.buttons["StartFromPastWorkoutConfirmButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        for _ in 0..<5 where !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        let menu = app.buttons["ExerciseMenuButton-0"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["ExerciseHistoryButton-0"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["QuickExerciseHistoryHeading"].waitForExistence(timeout: 5))
        assertMaximumValuesFit(in: app, identifierPrefix: "ExerciseHistorySetValue-", screen: "quick-history")
    }

    private func assertMaximumValuesFit(in app: XCUIApplication, identifierPrefix: String, screen: String) {
        let rows = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", identifierPrefix
        ))
        for weight in ["10000 pounds", "9,999.99 pounds"] {
            let row = rows.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", weight, "1000 reps")).firstMatch
            for _ in 0..<12 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable)
            XCTAssertGreaterThanOrEqual(row.frame.minX, 32)
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX - 32)
            attachScreenshot(named: "\(screen)-maximum-values-\(weight)-accessibility5", app: app)
        }
    }

    private func openRecords(extraArguments: [String] = [], kilograms: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-reset-persistent-store", "--uitest-in-memory-store",
            "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-seed-strength-records",
        ] + extraArguments
        app.launch()
        if kilograms {
            app.buttons["ProfileTab"].tap()
            app.buttons["ProfileSettingsLink"].tap()
            let units = app.segmentedControls["WeightUnitPicker"]
            XCTAssertTrue(units.waitForExistence(timeout: 3))
            units.buttons["Kilograms"].tap()
        }
        let history = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "HistoryTab", "History")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.tap()
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        let exercise = app.buttons["ExerciseHistoryButton-0"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 3))
        exercise.tap()
        return app
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
