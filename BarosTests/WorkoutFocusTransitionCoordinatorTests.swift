import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class WorkoutFocusTransitionCoordinatorTests: XCTestCase {
    func testRPEEditingResetsWhenFocusMovesToDifferentSet() {
        let firstSetID = UUID()
        let secondSetID = UUID()

        XCTAssertFalse(
            RPEEditingFocusPolicy.shouldReset(editingSetID: firstSetID, newFocusedField: .setWeight(firstSetID))
        )
        XCTAssertFalse(
            RPEEditingFocusPolicy.shouldReset(editingSetID: firstSetID, newFocusedField: .setReps(firstSetID))
        )
        XCTAssertTrue(
            RPEEditingFocusPolicy.shouldReset(editingSetID: firstSetID, newFocusedField: .setWeight(secondSetID))
        )
        XCTAssertTrue(
            RPEEditingFocusPolicy.shouldReset(editingSetID: firstSetID, newFocusedField: .workoutNotes)
        )
        XCTAssertFalse(
            RPEEditingFocusPolicy.shouldReset(editingSetID: nil, newFocusedField: .setWeight(secondSetID))
        )
    }
}
