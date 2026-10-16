import SwiftData
import XCTest
@testable import Baros

@MainActor
final class ActiveWorkoutStructureRecoveryTests: XCTestCase {
    func testFailedAddExercisePreservesWorkoutAndUnrelatedDirtyEdits() throws {
        let (container, context, session, exercise) = try makeReadOnlyWorkout()
        _ = container
        let engine = ActiveWorkoutEngine()
        let originalExercises = session.sortedLoggedExercises.map(\.id)
        let originalUpdatedAt = session.updatedAt
        session.notes = "Keep this unsaved workout note"
        exercise.notes = "Keep this unsaved library note"

        XCTAssertThrowsError(try engine.addExercise(exercise, to: session, context: context))

        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), originalExercises)
        XCTAssertEqual(session.updatedAt, originalUpdatedAt)
        XCTAssertEqual(session.notes, "Keep this unsaved workout note")
        XCTAssertEqual(exercise.notes, "Keep this unsaved library note")
        XCTAssertTrue(context.hasChanges)
    }

    func testFailedReorderPreservesOrderTimestampsAndUnrelatedDirtyEdits() throws {
        let (container, context, session, exercise) = try makeReadOnlyWorkout()
        _ = container
        let engine = ActiveWorkoutEngine()
        let originals = session.sortedLoggedExercises
        let originalIDs = originals.map(\.id)
        let originalDates = originals.map(\.updatedAt)
        let originalSessionDate = session.updatedAt
        session.notes = "Keep this unsaved workout note"
        exercise.notes = "Keep this unsaved library note"

        for _ in 0..<2 {
            XCTAssertThrowsError(try engine.reorderLoggedExercises(
                in: session, orderedIDs: originalIDs.reversed(), context: context,
                now: Date(timeIntervalSince1970: 500)
            ))
            XCTAssertEqual(session.sortedLoggedExercises.map(\.id), originalIDs)
            XCTAssertEqual(originals.map(\.orderIndex), [0, 1])
            XCTAssertEqual(originals.map(\.updatedAt), originalDates)
            XCTAssertEqual(session.updatedAt, originalSessionDate)
        }
        XCTAssertEqual(session.notes, "Keep this unsaved workout note")
        XCTAssertEqual(exercise.notes, "Keep this unsaved library note")
        XCTAssertTrue(context.hasChanges)
    }

    func testAddingExerciseAfterTransientSaveFailureAddsOnlyOneGraphAndKeepsOtherEdits() throws {
        enum SaveFailure: Error { case expected }
        let schema = Schema([WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
                             Exercise.self, UserSettings.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench", category: .strength, equipment: .barbell,
                                primaryMuscleGroup: .chest)
        let previous = WorkoutSession(title: "Previous", startedAt: .distantPast,
            status: .completed, source: .blank, loggedExercises: [
                LoggedExercise(orderIndex: 0, exercise: exercise, sets: [
                    LoggedSet(orderIndex: 0, kind: .warmup, isCompleted: true),
                    LoggedSet(orderIndex: 1, kind: .working, isCompleted: true)
                ])
            ])
        context.insert(previous)
        try context.save()
        session.notes = "Keep this unsaved workout note"
        exercise.notes = "Keep this unsaved library note"
        let unrelated = Exercise(name: "Unsaved exercise", category: .strength,
                                 equipment: .dumbbell, primaryMuscleGroup: .chest)
        context.insert(unrelated)

        XCTAssertThrowsError(try engine.addExercise(exercise, to: session, context: context,
            save: { _ in throw SaveFailure.expected }))
        XCTAssertTrue(session.sortedLoggedExercises.isEmpty)
        XCTAssertEqual(session.notes, "Keep this unsaved workout note")
        XCTAssertEqual(exercise.notes, "Keep this unsaved library note")
        XCTAssertNotNil(unrelated.modelContext)

        let added = try engine.addExercise(exercise, to: session, context: context)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [added.id])
        XCTAssertEqual(added.sortedSets.map(\.kind), [.warmup, .working])
        let restored = ModelContext(container)
        let savedSession = try XCTUnwrap(restored.fetch(FetchDescriptor<WorkoutSession>())
            .first { $0.id == session.id })
        XCTAssertEqual(savedSession.sortedLoggedExercises.map(\.id), [added.id])
        XCTAssertEqual(savedSession.notes, "Keep this unsaved workout note")
        XCTAssertEqual(try restored.fetch(FetchDescriptor<LoggedExercise>()).count, 2)
        XCTAssertEqual(try restored.fetch(FetchDescriptor<LoggedSet>()).count, 4)
        let savedExercises = try restored.fetch(FetchDescriptor<Exercise>())
        XCTAssertTrue(savedExercises.contains { $0.id == unrelated.id })
        XCTAssertEqual(savedExercises.first { $0.id == exercise.id }?.notes, "Keep this unsaved library note")
    }

    func testReorderAfterTransientSaveFailurePersistsDesiredOrderAndKeepsOtherEdits() throws {
        enum SaveFailure: Error { case expected }
        let schema = Schema([WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
                             Exercise.self, UserSettings.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let first = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench",
                                   sets: [LoggedSet(orderIndex: 0)])
        let second = LoggedExercise(orderIndex: 1, exerciseSnapshotName: "Squat")
        let unchanged = LoggedExercise(orderIndex: 2, exerciseSnapshotName: "Press")
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active,
                                     source: .blank, loggedExercises: [first, second, unchanged])
        context.insert(session)
        try context.save()
        session.notes = "Keep this unsaved workout note"
        first.sets[0].reps = 8
        let unchangedDate = unchanged.updatedAt
        let engine = ActiveWorkoutEngine()
        let desired = [second.id, first.id, unchanged.id]
        XCTAssertThrowsError(try engine.reorderLoggedExercises(in: session,
            orderedIDs: desired, context: context, save: { _ in throw SaveFailure.expected }))
        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [first.id, second.id, unchanged.id])
        XCTAssertEqual(first.sets[0].reps, 8)

        try engine.reorderLoggedExercises(in: session, orderedIDs: desired, context: context)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), desired)
        XCTAssertEqual(unchanged.updatedAt, unchangedDate)
        let restored = ModelContext(container)
        let saved = try XCTUnwrap(restored.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(saved.sortedLoggedExercises.map(\.id), desired)
        XCTAssertEqual(saved.notes, "Keep this unsaved workout note")
        XCTAssertEqual(saved.sortedLoggedExercises[1].sets[0].reps, 8)
    }

    private func makeReadOnlyWorkout() throws -> (ModelContainer, ModelContext, WorkoutSession, Exercise) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        let schema = Schema([WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
                             Exercise.self, UserSettings.self])
        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let exercise = Exercise(name: "Bench", category: .strength, equipment: .barbell,
                                    primaryMuscleGroup: .chest)
            let first = LoggedExercise(orderIndex: 0, exercise: exercise,
                                       sets: [LoggedSet(orderIndex: 0)])
            let second = LoggedExercise(orderIndex: 1, exerciseSnapshotName: "Squat")
            let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active,
                                         source: .blank, loggedExercises: [first, second])
            context.insert(session)
            try context.save()
        }
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(url: url, allowsSave: false))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first)
        return (container, context, session, exercise)
    }
}
