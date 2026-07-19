import SwiftData
import XCTest
@testable import Baros

@MainActor
final class WorkoutFocusNavigatorTests: XCTestCase {
    func testFocusOrderTraversesWholeWorkout() throws {
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active, source: .blank)
        let firstExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let secondExercise = LoggedExercise(orderIndex: 1, exerciseSnapshotName: "Row")
        let firstSet = LoggedSet(orderIndex: 0)
        let secondSet = LoggedSet(orderIndex: 1)
        let thirdSet = LoggedSet(orderIndex: 0)
        firstExercise.sets = [secondSet, firstSet]
        secondExercise.sets = [thirdSet]
        session.loggedExercises = [secondExercise, firstExercise]

        let order = WorkoutFocusNavigator.focusOrder(for: session)

        let expectedOrder: [WorkoutField] = [
            .workoutTitle,
            .setWeight(firstSet.id),
            .setReps(firstSet.id),
            .setWeight(secondSet.id),
            .setReps(secondSet.id),
            .exerciseNotes(firstExercise.id),
            .setWeight(thirdSet.id),
            .setReps(thirdSet.id),
            .exerciseNotes(secondExercise.id),
            .workoutNotes
        ]

        XCTAssertEqual(order, expectedOrder)
    }

    func testAdjacentFocusTraversesExerciseNotesBetweenExercises() {
        let firstExerciseID = UUID()
        let firstSetID = UUID()
        let secondSetID = UUID()
        let order: [WorkoutField] = [
            .workoutTitle,
            .setWeight(firstSetID),
            .setReps(firstSetID),
            .exerciseNotes(firstExerciseID),
            .setWeight(secondSetID),
            .workoutNotes
        ]

        XCTAssertEqual(
            WorkoutFocusNavigator.adjacentField(from: .setReps(firstSetID), in: order, offset: 1),
            .exerciseNotes(firstExerciseID)
        )
        XCTAssertEqual(
            WorkoutFocusNavigator.adjacentField(from: .exerciseNotes(firstExerciseID), in: order, offset: -1),
            .setReps(firstSetID)
        )
        XCTAssertEqual(
            WorkoutFocusNavigator.adjacentField(from: .exerciseNotes(firstExerciseID), in: order, offset: 1),
            .setWeight(secondSetID)
        )
        XCTAssertEqual(
            WorkoutFocusNavigator.adjacentField(from: .setWeight(secondSetID), in: order, offset: -1),
            .exerciseNotes(firstExerciseID)
        )
    }

    func testFocusOrderSkipsFieldsForCollapsedExercises() {
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active, source: .blank)
        let firstExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let secondExercise = LoggedExercise(orderIndex: 1, exerciseSnapshotName: "Row")
        let firstSet = LoggedSet(orderIndex: 0)
        let secondSet = LoggedSet(orderIndex: 0)
        firstExercise.sets = [firstSet]
        secondExercise.sets = [secondSet]
        session.loggedExercises = [firstExercise, secondExercise]

        let order = WorkoutFocusNavigator.focusOrder(
            for: session,
            collapsedExerciseIDs: [firstExercise.id]
        )

        let expectedOrder: [WorkoutField] = [
            .workoutTitle,
            .setWeight(secondSet.id),
            .setReps(secondSet.id),
            .exerciseNotes(secondExercise.id),
            .workoutNotes
        ]

        XCTAssertEqual(order, expectedOrder)
    }

    func testAdjacentFocusReturnsPreviousAndNextTargets() {
        let firstSetID = UUID()
        let secondSetID = UUID()
        let order: [WorkoutField] = [
            .workoutTitle,
            .setWeight(firstSetID),
            .setReps(firstSetID),
            .setWeight(secondSetID),
            .workoutNotes
        ]

        XCTAssertEqual(
            WorkoutFocusNavigator.adjacentField(from: .setReps(firstSetID), in: order, offset: -1),
            .setWeight(firstSetID)
        )
        XCTAssertEqual(
            WorkoutFocusNavigator.adjacentField(from: .setReps(firstSetID), in: order, offset: 1),
            .setWeight(secondSetID)
        )
        XCTAssertNil(WorkoutFocusNavigator.adjacentField(from: .workoutTitle, in: order, offset: -1))
        XCTAssertNil(WorkoutFocusNavigator.adjacentField(from: .workoutNotes, in: order, offset: 1))
        XCTAssertNil(WorkoutFocusNavigator.adjacentField(from: nil, in: order, offset: 1))
        XCTAssertNil(WorkoutFocusNavigator.adjacentField(from: .setReps(secondSetID), in: order, offset: 1))
    }

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
