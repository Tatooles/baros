import XCTest

@MainActor
final class AppUpdatePromptUITests: XCTestCase {
    private func app(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-in-memory-store", "--uitest-force-signed-out-auth",
                               "--uitest-skip-first-run-experience", "--uitest-update-available"] + extra
        return app
    }

    func testLaterPersistsAcrossRelaunch() {
        let app = app(extra: ["--uitest-update-reset"])
        app.launch()
        let alert = app.alerts["Update available"]
        XCTAssertTrue(alert.waitForExistence(timeout: 12))
        XCTAssertTrue(alert.buttons["Update"].exists)
        alert.buttons["Later"].tap()
        XCTAssertFalse(alert.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitest-update-reset" }
        app.launch()
        XCTAssertFalse(alert.waitForExistence(timeout: 4))
    }

    func testActiveWorkoutDefersPromptEvenWhenMinimized() {
        let app = app(extra: ["--uitest-update-reset", "--uitest-seed-large-active-workout"])
        app.launch()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.alerts["Update available"].waitForExistence(timeout: 2))
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 3))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)))
        XCTAssertTrue(app.buttons["ActiveWorkoutAccessory"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["WorkoutTitle"].exists)
        XCTAssertFalse(app.alerts["Update available"].waitForExistence(timeout: 2))
    }

    func testBackgroundedPromptCanBeOfferedAgainWithoutRecordingLater() {
        let app = app(extra: ["--uitest-update-reset"])
        app.launch()
        let alert = app.alerts["Update available"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        alert.buttons["Later"].tap()
        XCTAssertFalse(alert.exists)
    }

    func testModalDefersOfferUntilDismissal() {
        let app = app(extra: ["--uitest-update-reset", "--uitest-update-delayed"])
        app.launch()
        let start = app.buttons["StartWorkoutButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let cancel = app.buttons["StartWorkoutCancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts["Update available"].waitForExistence(timeout: 6))
        cancel.tap()
        XCTAssertTrue(app.alerts["Update available"].waitForExistence(timeout: 5))
        app.alerts["Update available"].buttons["Later"].tap()
    }

    func testOnboardingDefersPrompt() {
        let app = app(extra: ["--uitest-update-reset", "--uitest-reset-first-run-experience"])
        app.launchArguments.removeAll { $0 == "--uitest-skip-first-run-experience" }
        app.launch()
        XCTAssertFalse(app.alerts["Update available"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue"].exists)
    }
}
