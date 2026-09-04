import XCTest
@testable import Baros

final class ActiveWorkoutSetInputTests: XCTestCase {
    func testReturnsOnlyMissingPreviousValueBeforeCompletion() {
        let input = ActiveWorkoutSetInput()
        let previous = PreviousSetPerformance(weight: 185, reps: 5)

        XCTAssertEqual(
            input.previousFillBeforeCompletion(
                isCompleted: false,
                values: .init(weight: 200, reps: nil),
                previous: previous
            ),
            PreviousSetPerformance(weight: nil, reps: 5)
        )
        XCTAssertEqual(
            input.previousFillBeforeCompletion(
                isCompleted: false,
                values: .init(weight: nil, reps: 8),
                previous: previous
            ),
            PreviousSetPerformance(weight: 185, reps: nil)
        )
    }

    func testPreparingRPECompletionKeepsTypedValuesAndFillsRemainingPreviousValue() {
        var input = ActiveWorkoutSetInput()
        input.update("200", for: .weight, isFocused: true)

        let values = input.preparedValuesForSetAction(
            current: .init(weight: 185, reps: nil),
            weightUnit: .pounds,
            completesSet: true,
            isCompleted: false,
            previous: PreviousSetPerformance(weight: 175, reps: 5)
        )

        XCTAssertEqual(values, .init(weight: 200, reps: 5))
    }

    func testPreparingClearSelectionDoesNotFillPreviousValues() {
        var input = ActiveWorkoutSetInput()

        let values = input.preparedValuesForSetAction(
            current: .init(weight: nil, reps: nil),
            weightUnit: .pounds,
            completesSet: false,
            isCompleted: false,
            previous: PreviousSetPerformance(weight: 175, reps: 5)
        )

        XCTAssertEqual(values, .init(weight: nil, reps: nil))
    }

    func testPreparingCompletionFillsClearedFieldsButKeepsInvalidFieldsMissing() {
        for (weightText, repsText, expected) in [
            ("", "", ActiveWorkoutSetInput.Values(weight: 175, reps: 5)),
            ("invalid", "", .init(weight: nil, reps: 5)),
            ("", "invalid", .init(weight: 175, reps: nil)),
            ("invalid", "invalid", .init(weight: nil, reps: nil)),
            ("200", "8", .init(weight: 200, reps: 8)),
        ] {
            var input = ActiveWorkoutSetInput()
            input.update(weightText, for: .weight, isFocused: true)
            input.update(repsText, for: .reps, isFocused: true)

            let values = input.preparedValuesForSetAction(
                current: .init(weight: 200, reps: 8),
                weightUnit: .pounds,
                completesSet: true,
                isCompleted: false,
                previous: .init(weight: 175, reps: 5)
            )

            XCTAssertEqual(values, expected, "Inputs: \(weightText), \(repsText)")
            XCTAssertFalse(input.commit(current: values, weightUnit: .pounds).shouldPersist)
        }
    }

    func testPreparingUncheckCommitsClearedAndTypedFieldsWithoutPreviousFill() {
        var input = ActiveWorkoutSetInput()
        input.update("", for: .weight, isFocused: true)
        input.update("8", for: .reps, isFocused: true)

        let values = input.preparedValuesForSetAction(
            current: .init(weight: 200, reps: 5),
            weightUnit: .pounds,
            completesSet: false,
            isCompleted: true,
            previous: .init(weight: 175, reps: 6)
        )

        XCTAssertEqual(values, .init(weight: nil, reps: 8))
        XCTAssertFalse(input.commit(current: values, weightUnit: .pounds).shouldPersist)
    }

    func testPreparingCompletedSetRPEEditDoesNotFillClearedFields() {
        var input = ActiveWorkoutSetInput()
        input.update("", for: .reps, isFocused: true)

        let values = input.preparedValuesForSetAction(
            current: .init(weight: 200, reps: 5),
            weightUnit: .pounds,
            completesSet: true,
            isCompleted: true,
            previous: .init(weight: 175, reps: 6)
        )

        XCTAssertEqual(values, .init(weight: 200, reps: nil))
    }

    func testPreparingCompletionConvertsTypedKilogramsAndKeepsPreviousWeightCanonical() throws {
        var input = ActiveWorkoutSetInput()
        input.update("100", for: .weight, isFocused: true)
        let typedValues = input.preparedValuesForSetAction(
            current: .init(weight: nil, reps: nil),
            weightUnit: .kilograms,
            completesSet: true,
            isCompleted: false,
            previous: .init(weight: 185, reps: 5)
        )
        XCTAssertEqual(try XCTUnwrap(typedValues.weight), 220.462262185, accuracy: 0.000001)
        XCTAssertEqual(typedValues.reps, 5)
        XCTAssertFalse(input.commit(current: typedValues, weightUnit: .kilograms).shouldPersist)

        var emptyInput = ActiveWorkoutSetInput()
        let previousValues = emptyInput.preparedValuesForSetAction(
            current: .init(weight: nil, reps: nil),
            weightUnit: .kilograms,
            completesSet: true,
            isCompleted: false,
            previous: .init(weight: 185, reps: 5)
        )
        XCTAssertEqual(previousValues, .init(weight: 185, reps: 5))
    }

    func testDoesNotReturnPreviousFillWithoutPreviousOrAfterCompletion() {
        let input = ActiveWorkoutSetInput()

        XCTAssertNil(input.previousFillBeforeCompletion(
            isCompleted: false,
            values: .init(weight: nil, reps: nil),
            previous: nil
        ))
        XCTAssertNil(input.previousFillBeforeCompletion(
            isCompleted: true,
            values: .init(weight: nil, reps: nil),
            previous: PreviousSetPerformance(weight: 185, reps: 5)
        ))
    }

    func testRejectedWeightStillBlocksPreviousFillAfterEditingEnds() {
        var input = ActiveWorkoutSetInput()
        input.update("10001", for: .weight, isFocused: true)

        let commit = input.commit(
            current: .init(weight: nil, reps: 5),
            weightUnit: .pounds
        )

        XCTAssertEqual(commit.values, .init(weight: nil, reps: 5))
        XCTAssertFalse(commit.shouldPersist)
        XCTAssertNil(input.previousFillBeforeCompletion(
            isCompleted: false,
            values: commit.values,
            previous: PreviousSetPerformance(weight: 185, reps: 5)
        ))
    }

    func testRejectedWeightDoesNotSuppressPreviousRepsFill() {
        var input = ActiveWorkoutSetInput()
        input.update("10001", for: .weight, isFocused: true)

        let commit = input.commit(
            current: .init(weight: nil, reps: nil),
            weightUnit: .pounds
        )

        XCTAssertEqual(
            input.previousFillBeforeCompletion(
                isCompleted: false,
                values: commit.values,
                previous: PreviousSetPerformance(weight: 185, reps: 5)
            ),
            PreviousSetPerformance(weight: nil, reps: 5)
        )
    }

    func testRejectedRepsStillBlocksPreviousFillAfterEditingEnds() {
        var input = ActiveWorkoutSetInput()
        input.update("1001", for: .reps, isFocused: true)

        let commit = input.commit(
            current: .init(weight: 185, reps: nil),
            weightUnit: .pounds
        )

        XCTAssertEqual(commit.values, .init(weight: 185, reps: nil))
        XCTAssertFalse(commit.shouldPersist)
        XCTAssertNil(input.previousFillBeforeCompletion(
            isCompleted: false,
            values: commit.values,
            previous: PreviousSetPerformance(weight: 185, reps: 5)
        ))
    }

    func testRejectedRepsDoesNotSuppressPreviousWeightFill() {
        var input = ActiveWorkoutSetInput()
        input.update("1001", for: .reps, isFocused: true)

        let commit = input.commit(
            current: .init(weight: nil, reps: nil),
            weightUnit: .pounds
        )

        XCTAssertEqual(
            input.previousFillBeforeCompletion(
                isCompleted: false,
                values: commit.values,
                previous: PreviousSetPerformance(weight: 185, reps: 5)
            ),
            PreviousSetPerformance(weight: 185, reps: nil)
        )
    }

    func testExplicitPreviousFillClearsRejectionForTheFieldItFills() {
        var input = ActiveWorkoutSetInput()
        input.update("10001", for: .weight, isFocused: true)
        _ = input.commit(
            current: .init(weight: nil, reps: nil),
            weightUnit: .pounds
        )

        let values = ActiveWorkoutSetInput.Values(weight: 185, reps: nil)
        input.clearRejectionsSatisfiedByPreviousFill(values)

        XCTAssertEqual(
            input.previousFillBeforeCompletion(
                isCompleted: false,
                values: values,
                previous: PreviousSetPerformance(weight: 185, reps: 5)
            ),
            PreviousSetPerformance(weight: nil, reps: 5)
        )
    }

    func testRejectedFieldStaysRejectedWhenPreviousFillIsInvalid() {
        var input = ActiveWorkoutSetInput()
        input.update("10001", for: .weight, isFocused: true)
        _ = input.commit(
            current: .init(weight: nil, reps: 5),
            weightUnit: .pounds
        )

        let invalidFill = ActiveWorkoutSetInput.Values(weight: 10_001, reps: 5)
        input.clearRejectionsSatisfiedByPreviousFill(invalidFill)

        XCTAssertNil(input.previousFillBeforeCompletion(
            isCompleted: false,
            values: .init(weight: nil, reps: 5),
            previous: PreviousSetPerformance(weight: 185, reps: 5)
        ))
    }

    func testWeightDisplayPreservesInProgressDecimalEntry() {
        var input = ActiveWorkoutSetInput()
        input.update("8.", for: .weight, isFocused: true)

        XCTAssertEqual(
            input.text(
                for: .weight,
                values: .init(weight: 8, reps: nil),
                weightUnit: .pounds
            ),
            "8."
        )
    }

    func testInvalidStoredValuesAreExposedAsMissingInsteadOfDisplayed() {
        var input = ActiveWorkoutSetInput()
        let invalidValues = ActiveWorkoutSetInput.Values(weight: 10_001, reps: 1_001)

        XCTAssertEqual(input.text(for: .weight, values: invalidValues, weightUnit: .pounds), "")
        XCTAssertEqual(input.text(for: .reps, values: invalidValues, weightUnit: .pounds), "")
        XCTAssertEqual(
            input.commit(current: invalidValues, weightUnit: .pounds),
            .init(values: .init(weight: nil, reps: nil), shouldPersist: false)
        )
    }

    func testIgnoresEmptyWriteWhenFieldIsNotFocused() {
        var input = ActiveWorkoutSetInput()
        input.update("", for: .weight, isFocused: false)

        XCTAssertEqual(
            input.commit(current: .init(weight: 185, reps: 5), weightUnit: .pounds),
            .init(values: .init(weight: 185, reps: 5), shouldPersist: false)
        )
    }

    func testHonorsEmptyWriteWhileFieldIsFocused() {
        var input = ActiveWorkoutSetInput()
        input.update("", for: .weight, isFocused: true)

        XCTAssertEqual(
            input.commit(current: .init(weight: 185, reps: 5), weightUnit: .pounds),
            .init(values: .init(weight: nil, reps: 5), shouldPersist: true)
        )
    }

    func testHonorsNonEmptyWriteRegardlessOfFocus() {
        var input = ActiveWorkoutSetInput()
        input.update("200", for: .weight, isFocused: false)

        XCTAssertEqual(
            input.commit(current: .init(weight: 185, reps: 5), weightUnit: .pounds),
            .init(values: .init(weight: 200, reps: 5), shouldPersist: true)
        )
    }

    func testUnchangedDraftEndsEditingWithoutRequestingPersistence() {
        var input = ActiveWorkoutSetInput()
        input.update("185", for: .weight, isFocused: true)

        let commit = input.commit(
            current: .init(weight: 185, reps: 5),
            weightUnit: .pounds
        )

        XCTAssertEqual(
            commit,
            .init(values: .init(weight: 185, reps: 5), shouldPersist: false)
        )
        XCTAssertEqual(
            input.text(
                for: .weight,
                values: commit.values,
                weightUnit: .pounds
            ),
            "185"
        )
    }

    @MainActor
    func testRegisteredSetPreparationReturnsValuesWithoutCommitting() {
        let field = WorkoutField.setReps(UUID())
        let registry = ActiveSetInputRegistry()
        var commitCount = 0
        _ = registry.register(
            fields: [field],
            commit: { commitCount += 1 },
            prepareForRPESelection: { completesSet in
                XCTAssertTrue(completesSet)
                return .init(weight: 200, reps: 5)
            }
        )

        let values = registry.prepareSetValues(for: field, completesSet: true)

        XCTAssertEqual(values, .init(weight: 200, reps: 5))
        XCTAssertEqual(commitCount, 0)
    }

    @MainActor
    func testUpdateRegistrationReplacesPreparationForAllRegisteredFields() {
        let setID = UUID()
        let fields = [
            WorkoutField.setWeight(setID),
            WorkoutField.setReps(setID),
        ]
        let registry = ActiveSetInputRegistry()
        let registrationID = registry.register(
            fields: fields,
            commit: {},
            prepareForRPESelection: { _ in .init(weight: nil, reps: nil) }
        )

        registry.updateRegistration(
            registrationID,
            commit: {},
            prepareForRPESelection: { _ in .init(weight: 185, reps: 5) }
        )

        for field in fields {
            XCTAssertEqual(
                registry.prepareSetValues(for: field, completesSet: true),
                .init(weight: 185, reps: 5)
            )
        }
    }
}
