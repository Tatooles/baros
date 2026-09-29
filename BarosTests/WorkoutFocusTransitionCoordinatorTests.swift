import XCTest
@testable import Baros

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

    func testTransitioningOutOfAFieldRunsItsCommitCallback() {
        let field = WorkoutField.setWeight(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator()
        var commitCount = 0
        var assignedField: WorkoutField? = field
        coordinator.synchronizeFocus(field)

        coordinator.transition(
            to: nil,
            commit: { committedField in
                XCTAssertEqual(committedField, field)
                commitCount += 1
            },
            assign: { assignedField = $0 }
        )

        XCTAssertEqual(commitCount, 1)
        XCTAssertNil(coordinator.currentField)
        XCTAssertNil(assignedField)
    }

    func testTappedFocusChangeCommitsTheDepartingFieldOnce() {
        let weight = WorkoutField.setWeight(UUID())
        let reps = WorkoutField.setReps(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator()
        var committedFields: [WorkoutField?] = []
        coordinator.synchronizeFocus(weight)

        coordinator.observeFocusChange(from: weight, to: reps) { committedFields.append($0) }
        // A repeated notification for the same focus is only an acknowledgement.
        coordinator.observeFocusChange(from: weight, to: reps) { committedFields.append($0) }

        XCTAssertEqual(committedFields, [weight])
        XCTAssertEqual(coordinator.currentField, reps)
    }

    func testProgrammaticFocusAcknowledgementKeepsScheduledReveal() async {
        let target = WorkoutField.setWeight(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator()
        let revealExpectation = expectation(description: "reveal runs")

        coordinator.transition(to: target, commit: { _ in }, assign: { _ in })
        coordinator.scheduleReveal(after: .milliseconds(20)) { revealExpectation.fulfill() }
        coordinator.observeFocusChange(from: nil, to: target) { _ in }

        await fulfillment(of: [revealExpectation], timeout: 1)
    }

    func testTappedFocusChangeCancelsScheduledReveal() async throws {
        let target = WorkoutField.setWeight(UUID())
        let tapped = WorkoutField.setReps(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator()
        var didReveal = false

        coordinator.transition(to: target, commit: { _ in }, assign: { _ in })
        coordinator.scheduleReveal(after: .milliseconds(20)) { didReveal = true }
        coordinator.observeFocusChange(from: target, to: tapped) { _ in }

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(didReveal)
    }
}
