import XCTest
@testable import Baros

final class AppReleaseCatalogTests: XCTestCase {
    func testCurrentAppVersionIsCataloged() {
        XCTAssertNotNil(AppReleaseCatalog.release(for: AppBuildInfo.current.version))
    }

    func testVersionOneZeroUsesItsDedicatedReleaseSheet() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.whatsNew(for: "1.0"))

        XCTAssertEqual(release.version, "1.0")
        XCTAssertEqual(release.sheetID, .version1_0)
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
