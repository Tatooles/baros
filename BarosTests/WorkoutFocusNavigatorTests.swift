import SwiftData
import XCTest
@testable import Baros

@MainActor
final class WorkoutFocusNavigatorTests: XCTestCase {
    func testFocusOrderSkipsEmptyExerciseAndWorkoutNotes() throws {
        let session = WorkoutSession(
            title: "Workout",
            startedAt: .now,
            notes: "  \n",
            status: .active,
            source: .blank
        )
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
            .setWeight(thirdSet.id),
            .setReps(thirdSet.id)
        ]

        XCTAssertEqual(order, expectedOrder)
    }

    func testFocusOrderIncludesExistingWorkoutNote() {
        let session = WorkoutSession(
            title: "Workout",
            startedAt: .now,
            notes: "Felt strong",
            status: .active,
            source: .blank
        )

        XCTAssertEqual(
            WorkoutFocusNavigator.focusOrder(for: session),
            [.workoutTitle, .workoutNotes]
        )
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

    func testFocusOrderIncludesExistingAndExplicitlyRevealedNotes() {
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active, source: .blank)
        let existingNoteExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press", notes: "Pause reps")
        let revealedEmptyExercise = LoggedExercise(orderIndex: 1, exerciseSnapshotName: "Row", notes: "  \n")
        let firstSet = LoggedSet(orderIndex: 0)
        let secondSet = LoggedSet(orderIndex: 0)
        existingNoteExercise.sets = [firstSet]
        revealedEmptyExercise.sets = [secondSet]
        session.loggedExercises = [existingNoteExercise, revealedEmptyExercise]

        let order = WorkoutFocusNavigator.focusOrder(
            for: session,
            inputs: .init(
                revealedExerciseNoteIDs: [revealedEmptyExercise.id],
                isWorkoutNoteRevealed: true
            )
        )

        XCTAssertEqual(order, [
            .workoutTitle,
            .workoutNotes,
            .setWeight(firstSet.id),
            .setReps(firstSet.id),
            .exerciseNotes(existingNoteExercise.id),
            .setWeight(secondSet.id),
            .setReps(secondSet.id),
            .exerciseNotes(revealedEmptyExercise.id),
        ])
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
            inputs: .init(collapsedExerciseIDs: [firstExercise.id])
        )

        let expectedOrder: [WorkoutField] = [
            .workoutTitle,
            .setWeight(secondSet.id),
            .setReps(secondSet.id)
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

    func testRealizationTargetsGroupWorkoutFieldsAboveLazyExerciseCards() {
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active, source: .blank)
        let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let set = LoggedSet(orderIndex: 0)
        exercise.sets = [set]
        session.loggedExercises = [exercise]

        XCTAssertEqual(
            WorkoutFocusNavigator.realizationTarget(containing: .workoutTitle, in: session),
            .workoutHeader
        )
        XCTAssertEqual(
            WorkoutFocusNavigator.realizationTarget(containing: .workoutNotes, in: session),
            .workoutHeader
        )
        XCTAssertEqual(
            WorkoutFocusNavigator.realizationTarget(containing: .exerciseNotes(exercise.id), in: session),
            .exercise(exercise.id)
        )
        XCTAssertEqual(
            WorkoutFocusNavigator.realizationTarget(containing: .setWeight(set.id), in: session),
            .exercise(exercise.id)
        )
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

    func testFocusOrderCacheInvalidatesOnlyForStructureCollapseAndRevealChanges() {
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active, source: .blank)
        let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let firstSet = LoggedSet(orderIndex: 0)
        exercise.sets = [firstSet]
        session.loggedExercises = [exercise]
        let cache = WorkoutFocusOrderCache()

        let initialOrder = cache.update(
            for: session,
            inputs: .init()
        )
        _ = cache.update(
            for: session,
            inputs: .init()
        )

        XCTAssertEqual(cache.rebuildCount, 1)
        XCTAssertEqual(initialOrder, [
            .workoutTitle,
            .setWeight(firstSet.id),
            .setReps(firstSet.id),
        ])

        let secondSet = LoggedSet(orderIndex: 1)
        exercise.sets.append(secondSet)
        let addedOrder = cache.update(
            for: session,
            inputs: .init()
        )

        XCTAssertEqual(cache.rebuildCount, 2)
        XCTAssertTrue(addedOrder.contains(.setWeight(secondSet.id)))

        secondSet.markDeleted()
        let removedOrder = cache.update(
            for: session,
            inputs: .init()
        )

        XCTAssertEqual(cache.rebuildCount, 3)
        XCTAssertFalse(removedOrder.contains(.setWeight(secondSet.id)))

        let collapsedOrder = cache.update(
            for: session,
            inputs: .init(
                collapsedExerciseIDs: [exercise.id],
                revealedExerciseNoteIDs: [exercise.id],
                isWorkoutNoteRevealed: true
            )
        )

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
        let revealExpectation = expectation(description: "latest field revealed")

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
            reveal: {
                revealedFields.append($0)
                revealExpectation.fulfill()
            }
        )

        await fulfillment(of: [revealExpectation], timeout: 1)

        XCTAssertEqual(revealedFields, [fields[2]])
    }

    func testUnrealizedExerciseTransitionCommitsOnlyWhenFocusTransfers() async {
        let source = WorkoutField.setReps(UUID())
        let field = WorkoutField.setWeight(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator(revealDelay: .zero)
        var events: [String] = []
        let revealExpectation = expectation(description: "field revealed after realization")
        coordinator.synchronizeFocus(source)

        coordinator.transitionAfterRealizing(
            to: field,
            commit: { committedField in
                XCTAssertEqual(committedField, source)
                events.append("commit")
            },
            realize: { _ in events.append("realize") },
            assign: { _ in events.append("assign") },
            reveal: { _ in
                events.append("reveal")
                revealExpectation.fulfill()
            }
        )

        await fulfillment(of: [revealExpectation], timeout: 1)

        XCTAssertEqual(
            events,
            ["realize", "commit", "assign", "reveal"]
        )
        XCTAssertEqual(coordinator.currentField, field)
    }

    func testSupersededUnrealizedTransitionsCommitOnlyForTheLatestTransfer() async {
        let source = WorkoutField.setReps(UUID())
        let firstTarget = WorkoutField.setWeight(UUID())
        let latestTarget = WorkoutField.setReps(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator(revealDelay: .seconds(1))
        var committedFields: [WorkoutField?] = []
        let revealExpectation = expectation(description: "latest field revealed")
        coordinator.synchronizeFocus(source)

        coordinator.transitionAfterRealizing(
            to: firstTarget,
            commit: { committedFields.append($0) },
            realize: { _ in },
            assign: { _ in },
            reveal: { _ in XCTFail("The superseded target must not reveal") }
        )
        coordinator.transitionAfterRealizing(
            to: latestTarget,
            delay: .zero,
            commit: { committedFields.append($0) },
            realize: { _ in },
            assign: { _ in },
            reveal: { _ in revealExpectation.fulfill() }
        )

        await fulfillment(of: [revealExpectation], timeout: 1)

        XCTAssertEqual(committedFields, [source])
        XCTAssertEqual(coordinator.currentField, latestTarget)
    }

    func testStagedTransitionKeepsSourceDraftUncommittedUntilAssignment() {
        let source = WorkoutField.setReps(UUID())
        let target = WorkoutField.setWeight(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator(revealDelay: .seconds(1))
        var committedFields: [WorkoutField?] = []
        coordinator.synchronizeFocus(source)

        coordinator.transitionAfterRealizing(
            to: target,
            commit: { committedFields.append($0) },
            realize: { _ in },
            assign: { _ in },
            reveal: { _ in }
        )

        XCTAssertTrue(committedFields.isEmpty)
        XCTAssertEqual(coordinator.currentField, target)
        XCTAssertEqual(coordinator.actualField, source)
    }

    func testStagedTransitionPreservesPartialDecimalUntilFocusTransfers() async {
        let source = WorkoutField.setWeight(UUID())
        let target = WorkoutField.setReps(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator(revealDelay: .milliseconds(20))
        let draft = ActiveWorkoutSetDraft()
        var values = ActiveWorkoutSetInput.Values(weight: nil, reps: nil)
        let revealExpectation = expectation(description: "focus transferred")
        draft.update("101.", for: .weight, isFocused: true)
        coordinator.synchronizeFocus(source)

        coordinator.transitionAfterRealizing(
            to: target,
            commit: { _ in
                values = draft.commit(current: values, weightUnit: .pounds).values
            },
            realize: { _ in },
            assign: { _ in },
            reveal: { _ in revealExpectation.fulfill() }
        )

        XCTAssertEqual(
            draft.text(for: .weight, values: values, weightUnit: .pounds),
            "101."
        )

        await fulfillment(of: [revealExpectation], timeout: 1)
        XCTAssertEqual(values.weight, 101)
    }

    func testTransitioningOutOfAFieldCommitsThatField() {
        let field = WorkoutField.setWeight(UUID())
        let coordinator = WorkoutFocusTransitionCoordinator(revealDelay: .zero)
        var committedFields: [WorkoutField?] = []
        var assignedField: WorkoutField? = field
        coordinator.synchronizeFocus(field)

        coordinator.transition(
            to: nil,
            commit: { committedFields.append($0) },
            assign: { assignedField = $0 },
            reveal: { _ in }
        )

        XCTAssertEqual(committedFields, [field])
        XCTAssertNil(coordinator.currentField)
        XCTAssertNil(assignedField)
    }
}
