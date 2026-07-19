import XCTest
@testable import Baros

final class SetCompletionPreviousFillPolicyTests: XCTestCase {
    func testFillsBeforeCompletionWhenEitherWeightOrRepsIsMissing() {
        let previous = PreviousSetPerformance(weight: 185, reps: 5)

        XCTAssertTrue(SetCompletionPreviousFillPolicy.shouldFillBeforeCompletion(
            isCompleted: false,
            weight: 200,
            reps: nil,
            previous: previous
        ))
        XCTAssertTrue(SetCompletionPreviousFillPolicy.shouldFillBeforeCompletion(
            isCompleted: false,
            weight: nil,
            reps: 8,
            previous: previous
        ))
    }

    func testDoesNotFillBeforeCompletionWithoutPreviousOrAfterCompletion() {
        XCTAssertFalse(SetCompletionPreviousFillPolicy.shouldFillBeforeCompletion(
            isCompleted: false,
            weight: nil,
            reps: nil,
            previous: nil
        ))
        XCTAssertFalse(SetCompletionPreviousFillPolicy.shouldFillBeforeCompletion(
            isCompleted: true,
            weight: nil,
            reps: nil,
            previous: PreviousSetPerformance(weight: 185, reps: 5)
        ))
    }

    func testIgnoresEmptyWriteWhenFieldIsNotFocused() {
        // A spurious commit-on-resign (e.g. after auto-filling from Previous on
        // completion) arrives while the field is no longer focused and must be dropped.
        XCTAssertTrue(CompletionEmptyWriteGuard.shouldIgnoreEmptyWrite(value: "", isFieldFocused: false))
    }

    func testHonorsEmptyWriteWhileFieldIsFocused() {
        // The user actively clearing a focused field is a legitimate edit.
        XCTAssertFalse(CompletionEmptyWriteGuard.shouldIgnoreEmptyWrite(value: "", isFieldFocused: true))
    }

    func testHonorsNonEmptyWriteRegardlessOfFocus() {
        XCTAssertFalse(CompletionEmptyWriteGuard.shouldIgnoreEmptyWrite(value: "185", isFieldFocused: false))
        XCTAssertFalse(CompletionEmptyWriteGuard.shouldIgnoreEmptyWrite(value: "185", isFieldFocused: true))
    }
}
