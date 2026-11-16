import XCTest

/// Captures the raw screens behind the App Store screenshots and baros.fit imagery.
/// Skipped unless `BAROS_MARKETING_CAPTURE=1`; run it through
/// the release skill's `scripts/capture-screens.sh`, which sets the simulator up first.
/// Each test attaches one screenshot named after its shot in `docs/release/listing.json`.
final class MarketingScreenshotTests: XCTestCase {
    private let timeout: TimeInterval = 8

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BAROS_MARKETING_CAPTURE"] == "1",
            "Marketing capture runs only through the release skill's capture-screens.sh"
        )
        continueAfterFailure = false
    }

    @MainActor
    func testHomeYear() {
        let app = launch()
        let picker = app.segmentedControls["HomeRingPeriodPicker"]
        XCTAssertTrue(picker.waitToExist(timeout: timeout))
        picker.buttons["Year"].tap()
        settle()
        capture("home-year")
    }

    @MainActor
    func testActiveWorkoutResting() {
        let app = launch()
        startTemplate("Push Day", in: app)
        for set in 0..<2 {
            let complete = app.buttons["SetCompletionButton-0-\(set)"]
            XCTAssertTrue(complete.waitToExist(timeout: timeout))
            complete.tap()
        }
        // Lets the rest timer count down from its starting value.
        Thread.sleep(forTimeInterval: 3)
        capture("active-rest")
    }

    @MainActor
    func testTemplates() {
        let app = launch()
        openTemplatePicker(in: app)
        settle()
        capture("templates")
    }

    @MainActor
    func testSuperset() {
        let app = launch()
        // Full Body opens with a press-and-row superset; log its first round.
        startTemplate("Full Body", in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "SupersetLabel").firstMatch
            .waitToExist(timeout: timeout))
        // One check logs the whole round: the partner set completes with it.
        let complete = app.buttons["SetCompletionButton-0-0"]
        XCTAssertTrue(complete.waitToExist(timeout: timeout))
        complete.tap()
        let partner = app.buttons["SetCompletionButton-1-0"]
        XCTAssertTrue(waitUntil(timeout: timeout) { partner.exists && partner.label == "Mark set incomplete" })
        Thread.sleep(forTimeInterval: 3)
        capture("superset")
    }

    @MainActor
    func testStrengthRecords() {
        let app = launch()
        app.tabButton(.history).tap()
        app.segmentedControls["HistoryModePicker"].buttons["Exercises"].tap()
        let squat = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "ExerciseHistoryButton-", "Back Squat"
        )).firstMatch
        XCTAssertTrue(squat.waitToExist(timeout: timeout))
        squat.tap()
        settle()
        capture("strength-records")
    }

    @MainActor
    func testWorkoutDetail() {
        let app = launch()
        app.tabButton(.history).tap()
        let push = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "WorkoutHistoryButton-", "Push Day"
        )).firstMatch
        XCTAssertTrue(push.waitToExist(timeout: timeout))
        push.tap()
        XCTAssertTrue(app.descendants(matching: .any)["WorkoutHistoryHeading"].waitToExist(timeout: timeout))
        settle()
        capture("workout-detail")
    }

    @MainActor
    func testSettings() {
        let app = launch()
        app.tabButton(.settings).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitToExist(timeout: timeout))
        settle()
        capture("settings")
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // The pool simulators are shared, so pin what formats dates and numbers. Resetting the
        // app appearance restores its dark default whatever the simulator uses.
        app.launchArguments = [
            "--uitest-in-memory-store", "--uitest-force-signed-out-auth", "--uitest-reset-app-appearance",
            "--uitest-reset-home-ring-period", "--uitest-skip-first-run-experience",
            "--uitest-seed-marketing", "--uitest-marketing-capture",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["HomeTitle"].waitToExist(timeout: timeout))
        return app
    }

    @MainActor
    private func openTemplatePicker(in app: XCUIApplication) {
        app.buttons["StartWorkoutButton"].tap()
        let useTemplate = app.buttons["UseTemplateButton"]
        XCTAssertTrue(useTemplate.waitToExist(timeout: timeout))
        useTemplate.tap()
        XCTAssertTrue(app.buttons["TemplateRow-Push Day"].waitToExist(timeout: timeout))
    }

    @MainActor
    private func startTemplate(_ name: String, in app: XCUIApplication) {
        openTemplatePicker(in: app)
        app.buttons["TemplateRow-\(name)"].tap()
        let start = app.buttons["StartFromTemplateButton"]
        XCTAssertTrue(start.waitToExist(timeout: timeout))
        start.tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitToExist(timeout: timeout))
    }

    /// Lets transitions and scroll deceleration finish before the capture.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func capture(_ shot: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "marketing-\(shot)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
