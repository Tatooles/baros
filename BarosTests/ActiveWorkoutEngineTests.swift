import SwiftData
import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class ActiveWorkoutEngineTests: XCTestCase {
    func testExerciseCardSetProgressIgnoresTombstonedSets() throws {
        let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let completedSet = LoggedSet(orderIndex: 0, isCompleted: true)
        let deletedCompletedSet = LoggedSet(orderIndex: 1, isCompleted: true)
        let openSet = LoggedSet(orderIndex: 2, isCompleted: false)
        deletedCompletedSet.markDeleted(now: Date(timeIntervalSince1970: 600))
        loggedExercise.sets = [completedSet, deletedCompletedSet, openSet]

        let progress = ExerciseCardView.setProgress(for: loggedExercise)

        XCTAssertEqual(progress.completed, 1)
        XCTAssertEqual(progress.total, 2)
        XCTAssertFalse(progress.isComplete)
    }

    func testTappingTheSelectedRPEChipClearsItAndOtherChipsSelectTheirValue() {
        XCTAssertEqual(RPEChipRow.selection(afterTapping: 9, current: nil), 9)
        XCTAssertEqual(RPEChipRow.selection(afterTapping: 9, current: 8.5), 9)
        XCTAssertNil(RPEChipRow.selection(afterTapping: 9, current: 9))
    }

    func testRPEChipSelectionCommitsPreparedValuesAndCompletesSet() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercises([exercise], to: session, context: context)[0]
        let set = loggedExercise.sets[0]
        set.weight = 185
        set.reps = 5
        try context.save()
        let baseline = Date(timeIntervalSince1970: 100)
        let commitDate = Date(timeIntervalSince1970: 200)
        session.updatedAt = baseline
        loggedExercise.updatedAt = baseline
        set.updatedAt = baseline
        try context.save()

        try RPEChipSelectionAction.apply(
            value: 8.5,
            preparedValues: .init(weight: 195, reps: 4),
            to: set,
            engine: engine,
            context: context,
            now: commitDate
        )

        XCTAssertEqual(set.weight, 195)
        XCTAssertEqual(set.reps, 4)
        XCTAssertEqual(set.rpe, 8.5)
        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.completedAt, commitDate)
        XCTAssertEqual(set.updatedAt, commitDate)
        XCTAssertEqual(loggedExercise.updatedAt, commitDate)
        XCTAssertEqual(session.updatedAt, commitDate)
    }

    func testSelectingExistingRPEStillCompletesIncompleteSet() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let completionDate = Date(timeIntervalSince1970: 300)
        let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: false)
        context.insert(set)
        try context.save()

        try RPEChipSelectionAction.apply(
            value: 8,
            preparedValues: .init(weight: 185, reps: 5),
            to: set,
            engine: engine,
            context: context,
            now: completionDate
        )

        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.completedAt, completionDate)
    }

    func testClearingRPEPreservesCompletionStateAndDate() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let completionDate = Date(timeIntervalSince1970: 100)
        let completedSet = LoggedSet(
            orderIndex: 0,
            rpe: 8,
            isCompleted: true,
            completedAt: completionDate
        )
        let incompleteSet = LoggedSet(orderIndex: 1, rpe: 8, isCompleted: false)
        context.insert(completedSet)
        context.insert(incompleteSet)
        try context.save()

        try RPEChipSelectionAction.apply(
            value: nil,
            to: completedSet,
            engine: engine,
            context: context
        )
        try RPEChipSelectionAction.apply(
            value: nil,
            to: incompleteSet,
            engine: engine,
            context: context
        )

        XCTAssertNil(completedSet.rpe)
        XCTAssertTrue(completedSet.isCompleted)
        XCTAssertEqual(completedSet.completedAt, completionDate)
        XCTAssertNil(incompleteSet.rpe)
        XCTAssertFalse(incompleteSet.isCompleted)
        XCTAssertNil(incompleteSet.completedAt)
    }
}
