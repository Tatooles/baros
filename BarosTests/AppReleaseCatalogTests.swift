import XCTest
@testable import Baros

final class AppReleaseCatalogTests: XCTestCase {
    func testCurrentAppVersionIsCataloged() {
        XCTAssertNotNil(AppReleaseCatalog.release(for: AppBuildInfo.current.version))
    }

    func testVersionOneZeroHasInitialReleaseHighlights() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.whatsNew(for: "1.0"))

        XCTAssertEqual(release.version, "1.0")
        XCTAssertEqual(release.title, "What's new in Baros")
        XCTAssertEqual(
            release.summary,
            "The first release of Baros: fast workout logging, a safe local history, and optional cloud sync."
        )
    }

    func testVersionOneZeroReleaseContentHasCompleteRows() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.whatsNew(for: "1.0"))

        XCTAssertFalse(release.summary.isEmpty)
        XCTAssertGreaterThanOrEqual(release.items.count, 3)
        for item in release.items {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.systemImage.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.detail.isEmpty)
        }
    }

    func testVersionOneOneIsCatalogedWithoutReleaseHighlights() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.release(for: "1.1"))

        XCTAssertEqual(release.version, "1.1")
        XCTAssertNil(release.whatsNew)
    }

    func testVersionOneOneCanOpenLatestReleaseHighlightsFromSettings() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.latestWhatsNew(upTo: "1.1"))

        XCTAssertEqual(release.version, "1.0")
    }

    func testUncatalogedFutureVersionCanOpenLatestReleaseHighlightsFromSettings() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.latestWhatsNew(upTo: "999.0"))

        XCTAssertEqual(release.version, "1.0")
    }

    func testUncatalogedOlderVersionCannotOpenNewerReleaseHighlightsFromSettings() {
        XCTAssertNil(AppReleaseCatalog.latestWhatsNew(upTo: "0.9"))
    }

    func testMalformedVersionCannotOpenReleaseHighlightsFromSettings() {
        XCTAssertNil(AppReleaseCatalog.latestWhatsNew(upTo: "not-a-version"))
    }
}
