import Foundation
import XCTest
@testable import Baros

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

    func testKilogramDisplayInputRoundTripsThroughCanonicalPounds() {
        let storedPounds = MeasurementUnit.kilograms.canonicalWeight(fromDisplayWeight: 100)

        XCTAssertEqual(storedPounds ?? 0, 220.462262185, accuracy: 0.000_001)
        XCTAssertEqual(MeasurementUnit.kilograms.displayWeight(fromCanonicalPounds: storedPounds) ?? 0, 100, accuracy: 0.000_001)
        XCTAssertEqual(
            storedPounds.flatMap { MeasurementUnit.kilograms.displayWeight(fromCanonicalPounds: $0) }.map(WorkoutFormatters.number),
            "100"
        )
    }

    func testPoundDisplayInputKeepsCanonicalPoundsUnchanged() {
        XCTAssertEqual(MeasurementUnit.pounds.canonicalWeight(fromDisplayWeight: 185), 185)
        XCTAssertEqual(MeasurementUnit.pounds.displayWeight(fromCanonicalPounds: 185), 185)
    }

    func testWeightConversionHelpersPreserveNilValues() {
        XCTAssertNil(MeasurementUnit.kilograms.canonicalWeight(fromDisplayWeight: nil))
        XCTAssertNil(MeasurementUnit.kilograms.displayWeight(fromCanonicalPounds: nil))
    }

    func testDecimalWorkoutInputPreservesTrailingSeparatorWhileEditing() {
        var input = WorkoutNumberInputText()

        input.updateDraft("8.")

        XCTAssertEqual(input.displayText(for: 8), "8.")
    }

    func testDecimalWorkoutInputExposesPendingDraftText() {
        var input = WorkoutNumberInputText()

        XCTAssertNil(input.draftText)
        input.updateDraft("8.5")
        XCTAssertEqual(input.draftText, "8.5")
        input.endEditing()
        XCTAssertNil(input.draftText)
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

    func testNumberFormatterDisplaysLargeWholeNumberWithoutTrapping() {
        let value = Double("999999999999999999999999")!

        XCTAssertEqual(WorkoutFormatters.number(value), "1000000000000000000000000")
    }

    func testNumberParserRejectsNonFiniteValues() {
        let overflowingInput = String(repeating: "9", count: 400)

        XCTAssertNil(WorkoutFormatters.parseNumber(overflowingInput, locale: Locale(identifier: "en_US_POSIX")))
    }

    func testWorkoutNumericPolicyAcceptsWeightAtUpperBoundary() {
        XCTAssertEqual(WorkoutNumericInputPolicy.validatedWeight(10_000), 10_000)
    }

    func testWorkoutNumericPolicyAcceptsZeroWeightAtLowerBoundary() {
        XCTAssertEqual(WorkoutNumericInputPolicy.validatedWeight(0), 0)
    }

    func testWorkoutNumericPolicyRejectsOutOfPolicyWeights() {
        XCTAssertNil(WorkoutNumericInputPolicy.validatedWeight(-0.1))
        XCTAssertNil(WorkoutNumericInputPolicy.validatedWeight(10_000.1))
        XCTAssertNil(WorkoutNumericInputPolicy.validatedWeight(.infinity))
    }

    func testWorkoutNumericPolicyAcceptsRepsAtUpperBoundary() {
        XCTAssertEqual(WorkoutNumericInputPolicy.validatedReps(1_000), 1_000)
    }

    func testWorkoutNumericPolicyAcceptsOneRepAtLowerBoundary() {
        XCTAssertEqual(WorkoutNumericInputPolicy.validatedReps(1), 1)
    }

    func testWorkoutNumericPolicyRejectsOutOfPolicyReps() {
        XCTAssertNil(WorkoutNumericInputPolicy.validatedReps(0))
        XCTAssertNil(WorkoutNumericInputPolicy.validatedReps(1_001))
    }

    func testWorkoutNumericPolicyAcceptsRPEAtUpperBoundary() {
        XCTAssertEqual(WorkoutNumericInputPolicy.validatedRPE(10), 10)
    }

    func testWorkoutNumericPolicyAcceptsRPEAtLowerBoundary() {
        XCTAssertEqual(WorkoutNumericInputPolicy.validatedRPE(1), 1)
    }

    func testWorkoutNumericPolicyRejectsOutOfPolicyRPE() {
        XCTAssertNil(WorkoutNumericInputPolicy.validatedRPE(0.9))
        XCTAssertNil(WorkoutNumericInputPolicy.validatedRPE(10.1))
        XCTAssertNil(WorkoutNumericInputPolicy.validatedRPE(.nan))
    }

    func testWorkoutNumericPolicyParsesLocaleWeightInput() {
        XCTAssertEqual(
            WorkoutNumericInputPolicy.parseWeight(
                "8,5",
                unit: .pounds,
                locale: Locale(identifier: "fr_FR")
            ),
            8.5
        )
    }

    func testWorkoutNumericPolicyParsesLeadingDecimalWeightInput() {
        XCTAssertEqual(
            WorkoutNumericInputPolicy.parseWeight(
                ".5",
                unit: .pounds,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            0.5
        )
    }

    func testWorkoutNumericPolicyRejectsRepsAboveUpperBoundary() {
        XCTAssertNil(WorkoutNumericInputPolicy.parseReps("1001"))
    }

    func testWorkoutNumericPolicyParsesLocaleRPEInput() {
        XCTAssertEqual(
            WorkoutNumericInputPolicy.parseRPE(
                "8,5",
                locale: Locale(identifier: "fr_FR")
            ),
            8.5
        )
    }

    func testVolumeFormatterDisplaysCanonicalPoundVolumeInSelectedUnit() {
        let canonicalVolume = MeasurementUnit.kilograms.canonicalWeight(fromDisplayWeight: 100)! * 5

        XCTAssertEqual(WorkoutFormatters.volume(canonicalPounds: canonicalVolume, unit: .kilograms), "500")
        XCTAssertEqual(WorkoutFormatters.volume(canonicalPounds: canonicalVolume, unit: .pounds), "1,102.31")
    }
}
