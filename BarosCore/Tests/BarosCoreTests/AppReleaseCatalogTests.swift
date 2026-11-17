import XCTest
@testable import BarosCore

final class AppReleaseCatalogTests: XCTestCase {
    func testCatalogedVersionsUseTheirDedicatedReleaseSheets() throws {
        let dedicatedSheets: [(version: String, sheetID: WhatsNewSheetID)] = [
            ("1.0", .version1_0),
            ("1.2", .version1_2),
            ("1.3", .version1_3),
            ("1.4", .version1_4),
            ("1.5", .version1_5),
        ]

        for (version, sheetID) in dedicatedSheets {
            let release = try XCTUnwrap(AppReleaseCatalog.whatsNew(for: version), version)

            XCTAssertEqual(release.version, version)
            XCTAssertEqual(release.sheetID, sheetID, version)
            XCTAssertEqual(AppReleaseCatalog.latestWhatsNew(upTo: version), release, version)
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

        XCTAssertEqual(release.version, "1.5")
    }

    func testUncatalogedOlderVersionCannotOpenNewerReleaseHighlightsFromSettings() {
        XCTAssertNil(AppReleaseCatalog.latestWhatsNew(upTo: "0.9"))
    }

    func testMalformedVersionCannotOpenReleaseHighlightsFromSettings() {
        XCTAssertNil(AppReleaseCatalog.latestWhatsNew(upTo: "not-a-version"))
    }
}
