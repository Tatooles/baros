import XCTest
@testable import Baros

final class WhatsNewContentTests: XCTestCase {
    func testCurrentReleaseUsesMarketingVersionAsReleaseKey() {
        let buildInfo = AppBuildInfo(infoDictionary: [
            "CFBundleDisplayName": "Baros",
            "CFBundleIdentifier": "com.kevintatooles.LiftingLog",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "42",
            "BarosEnvironment": "Production",
        ], sourceMetadata: nil)

        let release = WhatsNewContent.current(buildInfo: buildInfo)

        XCTAssertEqual(release.version, "1.0")
        XCTAssertEqual(release.title, "What's new in Baros")
        XCTAssertEqual(
            release.summary,
            "The first release of Baros: fast workout logging, a safe local history, and optional cloud sync."
        )
        XCTAssertTrue(release.shouldAutoShow)
    }

    func testCurrentReleaseContentHasCompleteRows() {
        let release = WhatsNewContent.current(buildInfo: AppBuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "1.0",
        ], sourceMetadata: nil))

        XCTAssertFalse(release.summary.isEmpty)
        XCTAssertGreaterThanOrEqual(release.items.count, 3)
        for item in release.items {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.systemImage.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.detail.isEmpty)
        }
    }
}
