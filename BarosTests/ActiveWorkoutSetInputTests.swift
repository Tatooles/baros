import XCTest
@testable import Baros

final class ActiveWorkoutSetInputTests: XCTestCase {
    @MainActor
    func testDraftStoreKeepsAnEditedValueAcrossRowRealizationChanges() {
        let setID = UUID()
        let store = ActiveWorkoutSetDraftStore()
        let firstRealization = store.draft(for: setID)

        firstRealization.update("185.", for: .weight, isFocused: true)

        let secondRealization = store.draft(for: setID)
        XCTAssertTrue(firstRealization === secondRealization)
        XCTAssertEqual(
            secondRealization.text(
                for: .weight,
                values: .init(weight: nil, reps: nil),
                weightUnit: .pounds
            ),
            "185."
        )
    }

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
}
