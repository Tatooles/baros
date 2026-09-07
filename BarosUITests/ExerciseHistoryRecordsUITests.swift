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
        XCTAssertTrue(heaviest.label.contains("225"))
        XCTAssertTrue(estimate.label.contains("245"))
        attachScreenshot(named: "Strength records summary", app: app)

        let info = app.buttons["AboutStrengthRecordsButton"]
        info.tap()
        XCTAssertTrue(app.navigationBars["About strength records"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The estimate does not account for effort."].exists)
        attachScreenshot(named: "Strength records explanation", app: app)
        app.buttons["Done"].tap()

        let badges = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ExerciseRecordBadge-"))
        let heaviestBadge = badges.matching(NSPredicate(format: "label == %@", "Heaviest Rep")).firstMatch
        let estimateBadge = badges.matching(NSPredicate(format: "label == %@", "Estimated 1RM")).firstMatch
        for _ in 0..<5 where !estimateBadge.isHittable { app.swipeUp() }
        XCTAssertTrue(heaviestBadge.exists)
        XCTAssertTrue(estimateBadge.isHittable)
        XCTAssertEqual(badges.count, 2)
        attachScreenshot(named: "Gold inline source set badges", app: app)

        let values = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ExerciseHistorySetValue-"))
        let heaviestValue = values.matching(NSPredicate(format: "label == %@", "225 x 1")).firstMatch
        let estimateValue = values.matching(NSPredicate(format: "label == %@", "210 x 5")).firstMatch
        XCTAssertLessThanOrEqual(heaviestBadge.frame.maxX, heaviestValue.frame.minX)
        XCTAssertLessThanOrEqual(estimateBadge.frame.maxX, estimateValue.frame.minX)
        XCTAssertLessThan(abs(estimateBadge.frame.midY - estimateValue.frame.midY), 5)
    }

    func testRecordsAndBadgesSupportAccessibilityTextSizes() {
        let app = openRecords(extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])
        XCTAssertTrue(app.descendants(matching: .any)["ExerciseRecord-heaviestRep"].waitForExistence(timeout: 5))
        let badge = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ExerciseRecordBadge-estimated1RM-")).firstMatch
        for _ in 0..<12 where !badge.isHittable { app.swipeUp() }
        XCTAssertTrue(badge.isHittable)
        XCTAssertGreaterThanOrEqual(badge.frame.minX, 0)
        XCTAssertLessThanOrEqual(badge.frame.maxX, app.frame.maxX)
        attachScreenshot(named: "Source badges at accessibility text size", app: app)
    }

    private func openRecords(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-reset-persistent-store", "--uitest-in-memory-store",
            "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-skip-first-run-experience", "--uitest-seed-strength-records",
        ] + extraArguments
        app.launch()
        let history = app.buttons["HistoryTab"]
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
