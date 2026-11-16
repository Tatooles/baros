import Foundation
import XCTest
@testable import Baros

final class FormattingTests: XCTestCase {
    func testExerciseHeaderTitleBindsSpacedDashesToThePrecedingWord() {
        XCTAssertEqual(WorkoutFormatters.exerciseHeaderTitle("Lying Leg Curl - Cap"), "Lying Leg Curl\u{00A0}– Cap")
        XCTAssertEqual(WorkoutFormatters.exerciseHeaderTitle("Row – Wide"), "Row\u{00A0}– Wide")
        XCTAssertEqual(WorkoutFormatters.exerciseHeaderTitle("Row — Wide"), "Row\u{00A0}— Wide")
        XCTAssertEqual(WorkoutFormatters.exerciseHeaderTitle("Single-Arm Row"), "Single-Arm Row")
    }

    func testDurationFormatterUsesHourStyleWhenNeeded() {
        XCTAssertEqual(AppTheme.formatDuration(3674), "1:01:14")
        XCTAssertEqual(AppTheme.formatDuration(76), "01:16")
    }

    func testElapsedDescriptionIncludesSeconds() {
        XCTAssertEqual(WorkoutFormatters.elapsedDescription(2_339), "38:59 elapsed")
        XCTAssertEqual(WorkoutFormatters.elapsedDescription(3_899), "1:04:59 elapsed")
    }

    func testElapsedCompactDescriptionOmitsRedundantSuffix() {
        XCTAssertEqual(WorkoutFormatters.elapsedCompactDescription(2_339), "38:59")
        XCTAssertEqual(WorkoutFormatters.elapsedCompactDescription(3_899), "1:04:59")
    }

    func testElapsedAccessibilityDescriptionUsesSpokenUnitsIncludingSeconds() {
        XCTAssertEqual(WorkoutFormatters.elapsedAccessibilityDescription(0), "0 seconds elapsed")
        XCTAssertEqual(WorkoutFormatters.elapsedAccessibilityDescription(60), "1 minute, 0 seconds elapsed")
        XCTAssertEqual(WorkoutFormatters.elapsedAccessibilityDescription(3_600), "1 hour, 0 seconds elapsed")
        XCTAssertEqual(
            WorkoutFormatters.elapsedAccessibilityDescription(3_899),
            "1 hour, 4 minutes, 59 seconds elapsed"
        )
    }

    func testHomeElapsedDescriptionUsesMinuteGranularity() {
        XCTAssertEqual(WorkoutFormatters.homeElapsedDescription(2_339), "38 min elapsed")
        XCTAssertEqual(WorkoutFormatters.homeElapsedDescription(3_899), "1 hr 04 min elapsed")
        XCTAssertEqual(WorkoutFormatters.homeElapsedDescription(-1), "0 min elapsed")
    }

    func testCountDescriptionsUseSingularOnlyForOne() {
        XCTAssertEqual(WorkoutFormatters.setCount(0), "0 sets")
        XCTAssertEqual(WorkoutFormatters.setCount(1), "1 set")
        XCTAssertEqual(WorkoutFormatters.setCount(3), "3 sets")
        XCTAssertEqual(WorkoutFormatters.exerciseCount(1), "1 exercise")
        XCTAssertEqual(WorkoutFormatters.exerciseCount(2), "2 exercises")
    }

    func testDateFormatterIncludesWeekdayMonthAndDay() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 21)) ?? .now
        XCTAssertTrue(AppTheme.formatDate(date).contains("April"))
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

    func testWorkoutNumberInputIgnoresEmptyWriteWhenFieldIsNotFocused() {
        var input = WorkoutNumberInputText()

        input.updateDraft("", isFocused: false)

        XCTAssertNil(input.draftText)
    }

    func testWorkoutNumberInputRepsFallbackRoundTripsThroughPolicy() {
        let input = WorkoutNumberInputText()

        let text = input.displayText(fallback: String(1_000))

        XCTAssertEqual(text, "1000")
        XCTAssertEqual(
            WorkoutNumericInputPolicy.parseReps(
                text,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            1_000
        )
    }

    func testDecimalWorkoutInputUsesFormattedModelValueAfterEditingEnds() {
        var input = WorkoutNumberInputText()

        input.updateDraft("8.")
        input.endEditing()

        XCTAssertEqual(input.displayText(for: 8), "8")
    }

    func testNumberParserHonorsLocaleChangesBetweenCalls() {
        for _ in 0..<3 {
            XCTAssertEqual(WorkoutFormatters.parseNumber("1,234.5", locale: Locale(identifier: "en_US")), 1234.5)
            XCTAssertEqual(WorkoutFormatters.parseNumber("1.234,5", locale: Locale(identifier: "de_DE")), 1234.5)
            XCTAssertEqual(WorkoutFormatters.parseNumber("8,5", locale: Locale(identifier: "fr_FR")), 8.5)
            XCTAssertNil(WorkoutFormatters.parseNumber("invalid", locale: Locale(identifier: "en_US")))
            XCTAssertNil(WorkoutFormatters.parseNumber("  ", locale: Locale(identifier: "fr_FR")))
        }
    }

    func testNumberParserKeepsConcurrentCallersLocalesIndependent() {
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let usesDecimalComma = index.isMultiple(of: 2)
            let locale = Locale(identifier: usesDecimalComma ? "de_DE" : "en_US")
            let expected = usesDecimalComma ? 1.234 : 1234.0
            XCTAssertEqual(WorkoutFormatters.parseNumber("1,234", locale: locale), expected)
        }
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

    func testWorkoutNumericPolicyValidatesWeightBoundaries() {
        let cases: [(Double, Double?)] = [
            (-0.1, nil), (0, 0), (10_000, 10_000), (10_000.1, nil), (.infinity, nil),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(WorkoutNumericInputPolicy.validatedWeight(value), expected, "\(value)")
        }
    }

    func testWorkoutNumericPolicyValidatesRepsBoundaries() {
        let cases: [(Int, Int?)] = [(0, nil), (1, 1), (1_000, 1_000), (1_001, nil)]
        for (value, expected) in cases {
            XCTAssertEqual(WorkoutNumericInputPolicy.validatedReps(value), expected, "\(value)")
        }
    }

    func testWorkoutNumericPolicyValidatesRPEBoundaries() {
        let cases: [(Double, Double?)] = [(0.9, nil), (1, 1), (10, 10), (10.1, nil), (.nan, nil)]
        for (value, expected) in cases {
            XCTAssertEqual(WorkoutNumericInputPolicy.validatedRPE(value), expected, "\(value)")
        }
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

    func testWorkoutNumericPolicyParsesLocaleRepsInput() {
        XCTAssertEqual(
            WorkoutNumericInputPolicy.parseReps(
                "٥",
                locale: Locale(identifier: "ar_EG")
            ),
            5
        )
    }

    func testWorkoutNumericPolicyRejectsFractionalRepsInput() {
        XCTAssertNil(
            WorkoutNumericInputPolicy.parseReps(
                "5.5",
                locale: Locale(identifier: "en_US_POSIX")
            )
        )
    }

    func testWorkoutNumericPolicyRejectsPartiallyParsedRepsInput() {
        let malformedInputs = ["5abc", "5 abc", "5kg", "5.0abc"]

        for input in malformedInputs {
            XCTAssertNil(
                WorkoutNumericInputPolicy.parseReps(
                    input,
                    locale: Locale(identifier: "en_US_POSIX")
                ),
                input
            )
        }

        XCTAssertNil(
            WorkoutNumericInputPolicy.parseReps(
                "٥abc",
                locale: Locale(identifier: "ar_EG")
            ),
            "٥abc"
        )
    }

    func testWorkoutNumericPolicyRejectsPartiallyParsedWeightAndRPEInput() {
        XCTAssertNil(
            WorkoutNumericInputPolicy.parseWeight(
                "185kg",
                unit: .pounds,
                locale: Locale(identifier: "en_US_POSIX")
            )
        )
        XCTAssertNil(
            WorkoutNumericInputPolicy.parseRPE(
                "8abc",
                locale: Locale(identifier: "en_US_POSIX")
            )
        )
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
