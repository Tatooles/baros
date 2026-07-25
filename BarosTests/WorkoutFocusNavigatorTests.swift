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

    func testFocusOrderCacheInvalidatesOnlyForStructureAndCollapseChanges() {
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active, source: .blank)
        let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let firstSet = LoggedSet(orderIndex: 0)
        exercise.sets = [firstSet]
        session.loggedExercises = [exercise]
        let cache = WorkoutFocusOrderCache()

        let initialOrder = cache.update(for: session, collapsedExerciseIDs: [])
        _ = cache.update(for: session, collapsedExerciseIDs: [])

        XCTAssertEqual(cache.rebuildCount, 1)
        XCTAssertEqual(initialOrder, [
            .workoutTitle,
            .setWeight(firstSet.id),
            .setReps(firstSet.id),
            .exerciseNotes(exercise.id),
            .workoutNotes,
        ])

        let secondSet = LoggedSet(orderIndex: 1)
        exercise.sets.append(secondSet)
        let addedOrder = cache.update(for: session, collapsedExerciseIDs: [])

        XCTAssertEqual(cache.rebuildCount, 2)
        XCTAssertTrue(addedOrder.contains(.setWeight(secondSet.id)))

        secondSet.markDeleted()
        let removedOrder = cache.update(for: session, collapsedExerciseIDs: [])

        XCTAssertEqual(cache.rebuildCount, 3)
        XCTAssertFalse(removedOrder.contains(.setWeight(secondSet.id)))

        let collapsedOrder = cache.update(for: session, collapsedExerciseIDs: [exercise.id])

        XCTAssertEqual(cache.rebuildCount, 4)
        XCTAssertEqual(collapsedOrder, [.workoutTitle, .workoutNotes])
    }

    func testRapidMovesResolveFromCoordinatorLiveFocus() {
        let fields = (0..<12).map { _ in WorkoutField.setWeight(UUID()) }
        let coordinator = WorkoutFocusTransitionCoordinator(revealDelay: .zero)
        coordinator.updateFocusOrder(fields)
        coordinator.synchronizeFocus(fields[0])
        var assignedFields: [WorkoutField] = []

        for _ in 0..<10 {
            coordinator.move(
                offset: 1,
                commit: { _ in },
                assign: { assignedFields.append($0) },
                reveal: { _ in }
            )
        }

        XCTAssertEqual(assignedFields.count, 10)
        XCTAssertEqual(coordinator.currentField, fields[10])
    }

    func testLatestFocusRevealRequestCancelsStaleReveal() async {
        let fields = (0..<3).map { _ in WorkoutField.setWeight(UUID()) }
        let coordinator = WorkoutFocusTransitionCoordinator(revealDelay: .milliseconds(20))
        coordinator.updateFocusOrder(fields)
        coordinator.synchronizeFocus(fields[0])
        var revealedFields: [WorkoutField] = []

        coordinator.move(
            offset: 1,
            commit: { _ in },
            assign: { _ in },
            reveal: { revealedFields.append($0) }
        )
        coordinator.move(
            offset: 1,
            commit: { _ in },
            assign: { _ in },
            reveal: { revealedFields.append($0) }
        )

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(revealedFields, [fields[2]])
    }

    func testTransitioningOutOfAFieldCommitsItsRegisteredDraft() {
        let field = WorkoutField.setWeight(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator(revealDelay: .zero)
        let registry = WorkoutFieldCommitRegistry()
        var commitCount = 0
        var assignedField: WorkoutField? = field
        _ = registry.register(fields: [field]) {
            commitCount += 1
        }
        coordinator.synchronizeFocus(field)

        coordinator.transition(
            to: nil,
            commit: registry.commit,
            assign: { assignedField = $0 },
            reveal: { _ in }
        )

        XCTAssertEqual(commitCount, 1)
        XCTAssertNil(coordinator.currentField)
        XCTAssertNil(assignedField)
    }
}
