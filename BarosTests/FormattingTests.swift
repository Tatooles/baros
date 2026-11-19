import Foundation
import XCTest
@testable import Baros
@testable import BarosCore

final class FormattingTests: XCTestCase {
    func testDurationFormatterUsesHourStyleWhenNeeded() {
        XCTAssertEqual(AppTheme.formatDuration(3674), "1:01:14")
        XCTAssertEqual(AppTheme.formatDuration(76), "01:16")
    }

    func testDateFormatterIncludesWeekdayMonthAndDay() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 21)) ?? .now
        XCTAssertTrue(AppTheme.formatDate(date).contains("April"))
    }
}
