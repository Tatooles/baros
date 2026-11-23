import Foundation
import XCTest
@testable import BarosCore

final class LiveHeartRateTests: XCTestCase {
    private let measuredAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshReadingIsShown() {
        let reading = LiveHeartRate(beatsPerMinute: 128, measuredAt: measuredAt)

        XCTAssertEqual(reading.displayedBeatsPerMinute(at: measuredAt.addingTimeInterval(LiveHeartRate.freshness)), 128)
    }

    func testStaleReadingIsHidden() {
        let reading = LiveHeartRate(beatsPerMinute: 128, measuredAt: measuredAt)

        XCTAssertNil(reading.displayedBeatsPerMinute(at: measuredAt.addingTimeInterval(LiveHeartRate.freshness + 1)))
    }

    func testZeroAndFutureReadingsAreHidden() {
        XCTAssertNil(LiveHeartRate(beatsPerMinute: 0, measuredAt: measuredAt).displayedBeatsPerMinute(at: measuredAt))
        XCTAssertNil(LiveHeartRate(beatsPerMinute: 90, measuredAt: measuredAt.addingTimeInterval(60))
            .displayedBeatsPerMinute(at: measuredAt))
    }
}
