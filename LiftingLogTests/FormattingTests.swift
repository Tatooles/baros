import Foundation
import XCTest
@testable import LiftingLog

final class FormattingTests: XCTestCase {
    func testDurationFormatterUsesHourStyleWhenNeeded() {
        XCTAssertEqual(AppTheme.formatDuration(3674), "1:01:14")
    }

    func testDurationFormatterUsesMinuteStyleForShorterValues() {
        XCTAssertEqual(AppTheme.formatDuration(76), "01:16")
    }

    func testDateFormatterIncludesWeekdayMonthAndDay() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 21)) ?? .now
        XCTAssertTrue(AppTheme.formatDate(date).contains("April"))
    }

    func testMeasurementUnitProvidesUppercaseWorkoutFieldPlaceholder() {
        XCTAssertEqual(MeasurementUnit.pounds.fieldPlaceholder, "LBS")
        XCTAssertEqual(MeasurementUnit.kilograms.fieldPlaceholder, "KG")
    }

    func testDecimalWorkoutInputPreservesTrailingSeparatorWhileEditing() {
        var input = WorkoutNumberInputText()

        input.updateDraft("8.")

        XCTAssertEqual(input.displayText(for: 8), "8.")
    }

    func testDecimalWorkoutInputUsesFormattedModelValueAfterEditingEnds() {
        var input = WorkoutNumberInputText()

        input.updateDraft("8.")
        input.endEditing()

        XCTAssertEqual(input.displayText(for: 8), "8")
    }

    func testNumberParserAcceptsLocaleDecimalSeparator() {
        let locale = Locale(identifier: "fr_FR")

        XCTAssertEqual(WorkoutFormatters.parseNumber("8,5", locale: locale), 8.5)
    }

    func testNumberFormatterRoundsConvertedWeightForDisplay() {
        XCTAssertEqual(WorkoutFormatters.number(102.058), "102.06")
    }
}
