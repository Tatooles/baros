import SwiftData
import XCTest
@testable import Baros

@MainActor
final class WorkoutExerciseListTests: XCTestCase {
    func testDraftProtectsUncheckedValuesAndCompletedSetsButNotBlankSuggestions() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let session = try fixture(in: container.mainContext)
        let first = session.sortedLoggedExercises[0]
        let sets = first.sortedSets
        sets[0].weight = 0 // An explicitly entered bodyweight value still counts.
        sets[1].reps = 5
        sets[2].isCompleted = true
        // Suggestions are display-only, never assigned to the fourth blank row.
        var draft = WorkoutExerciseListDraft(session: session)
        draft.orderedIDs.removeFirst()
        XCTAssertTrue(draft.needsRemovalConfirmation)
        XCTAssertEqual(draft.removedExercises[0].loggedSetCount, 3)
        XCTAssertEqual(draft.removedExercises[0].loggedSetsText, "3 logged sets")
        XCTAssertEqual(session.sortedLoggedExercises.count, 3, "A draft cannot mutate the live workout")

        draft = WorkoutExerciseListDraft(session: session)
        draft.orderedIDs.removeLast()
        XCTAssertFalse(draft.needsRemovalConfirmation)
    }

    func testCombinedSaveSoftDeletesAndReordersOnceWithoutDeletingLibraryOrOldTombstones() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let exercises = session.sortedLoggedExercises
        let removed = exercises[1]
        let oldSet = removed.sortedSets[0]
        let oldDate = Date(timeIntervalSince1970: 10)
        oldSet.markDeleted(now: oldDate)
        try context.save()
        let baseline = WorkoutExerciseListSnapshot(session: session)
        let engine = ActiveWorkoutEngine()
        var saves = 0
        let now = Date(timeIntervalSince1970: 200)
        try engine.applyExerciseListChanges(
            in: session, orderedIDs: [exercises[2].id, exercises[0].id], baseline: baseline,
            context: context, now: now, save: { saves += 1; try $0.save() }
        )
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [exercises[2].id, exercises[0].id])
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1])
        XCTAssertEqual(removed.deletedAt, now)
        XCTAssertTrue(removed.sets.allSatisfy(\.isDeleted))
        XCTAssertEqual(oldSet.deletedAt, oldDate)
        XCTAssertEqual(oldSet.updatedAt, oldDate)
        XCTAssertFalse(try XCTUnwrap(removed.exercise).isDeleted)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 3)
    }

    func testFailedSaveRestoresDiskGraphAndTimerAndRetrySucceeds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: directory.appendingPathComponent("test.store"))
        let context = container.mainContext
        context.autosaveEnabled = false
        let session = try fixture(in: context)
        let exercises = session.sortedLoggedExercises
        let baseline = WorkoutExerciseListSnapshot(session: session)
        let sessionUpdatedAt = session.updatedAt
        let timer = RestTimerCoordinator(schedulesTasks: false)
        let engine = ActiveWorkoutEngine(restTimer: timer)
        let starter = exercises[1].sortedSets[0]
        timer.start(sessionID: session.id, setID: starter.id, duration: 120)
        session.notes = "Unrelated unsaved note"
        XCTAssertThrowsError(try engine.applyExerciseListChanges(
            in: session, orderedIDs: [exercises[2].id, exercises[0].id], baseline: baseline,
            context: context, save: { _ in throw CocoaError(.fileWriteUnknown) }
        ))
        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), baseline)
        XCTAssertEqual(session.updatedAt, sessionUpdatedAt)
        XCTAssertEqual(session.notes, "Unrelated unsaved note")
        XCTAssertEqual(timer.current?.rest.setID, starter.id)
        // A later unrelated save must not accidentally persist failed tombstones.
        try context.save()
        let fresh = ModelContext(container)
        let persisted = try XCTUnwrap(fresh.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(WorkoutExerciseListSnapshot(session: persisted), baseline)
        try engine.applyExerciseListChanges(
            in: session, orderedIDs: [exercises[2].id, exercises[0].id], baseline: baseline,
            context: context
        )
        XCTAssertNil(timer.current)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [exercises[2].id, exercises[0].id])
    }

    func testStaleDraftRejectsAddedExerciseAndNewUncheckedDataBeforeAnySave() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let engine = ActiveWorkoutEngine()
        let baseline = WorkoutExerciseListSnapshot(session: session)
        let ids = session.sortedLoggedExercises.map(\.id)
        let exercise = session.sortedLoggedExercises[0]
        exercise.sortedSets[0].reps = 8 // Does not change the exercise timestamp.
        XCTAssertThrowsError(try engine.applyExerciseListChanges(
            in: session, orderedIDs: Array(ids.dropFirst()), baseline: baseline,
            context: context, save: { _ in XCTFail("Stale edits must not save") }
        ))
        XCTAssertFalse(exercise.isDeleted)
        XCTAssertEqual(exercise.sortedSets[0].reps, 8)

        let refreshed = WorkoutExerciseListSnapshot(session: session)
        let newExercise = LoggedExercise(orderIndex: 3, exerciseSnapshotName: "New from sync")
        session.loggedExercises.append(newExercise)
        XCTAssertThrowsError(try engine.applyExerciseListChanges(
            in: session, orderedIDs: ids, baseline: refreshed,
            context: context, save: { _ in XCTFail("New exercises must not be silently removed") }
        ))
        XCTAssertFalse(newExercise.isDeleted)
        // A freshly reviewed draft is usable, rather than stuck in a retry loop.
        try engine.applyExerciseListChanges(
            in: session, orderedIDs: session.sortedLoggedExercises.map(\.id),
            baseline: WorkoutExerciseListSnapshot(session: session), context: context
        )
    }

    func testDuplicateOrForeignIDsAreRejectedWithoutMutations() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let session = try fixture(in: container.mainContext)
        let baseline = WorkoutExerciseListSnapshot(session: session)
        let id = session.sortedLoggedExercises[0].id
        for ids in [[id, id], [UUID()]] {
            XCTAssertThrowsError(try ActiveWorkoutEngine().applyExerciseListChanges(
                in: session, orderedIDs: ids, baseline: baseline, context: container.mainContext
            ))
            XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), baseline)
        }
    }

    func testCanSaveOneOrZeroRemainingExercisesAndUnchangedDraftDoesNotSave() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let engine = ActiveWorkoutEngine()
        let first = session.sortedLoggedExercises[0]
        try engine.applyExerciseListChanges(
            in: session, orderedIDs: [first.id], baseline: .init(session: session), context: context
        )
        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [first.id])
        try engine.applyExerciseListChanges(
            in: session, orderedIDs: [], baseline: .init(session: session), context: context
        )
        XCTAssertTrue(session.sortedLoggedExercises.isEmpty)
        XCTAssertEqual(session.status, .active)
        XCTAssertFalse(session.isDeleted)
        try engine.applyExerciseListChanges(
            in: session, orderedIDs: [], baseline: .init(session: session), context: context,
            save: { _ in XCTFail("Unchanged draft must not save") }
        )
    }

    func testAppendBatchFailureRestoresWorkoutAndRetryPreservesTapOrder() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let baseline = WorkoutExerciseListSnapshot(session: session)
        let additions = ["Curl", "Fly"].map { Exercise(name: $0, category: .strength, equipment: .dumbbell, primaryMuscleGroup: .chest) }
        additions.forEach { context.insert($0) }
        let engine = ActiveWorkoutEngine()
        XCTAssertThrowsError(try engine.addExercises(additions, to: session, context: context, save: { _ in throw CocoaError(.fileWriteUnknown) }))
        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), baseline)
        try engine.addExercises(additions, to: session, context: context)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName), ["Bench Press", "Barbell Row", "Back Squat", "Curl", "Fly"])
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1, 2, 3, 4])
    }

    func testDraftAppendsInTapOrderEvenWithLoggedSets() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let session = try fixture(in: container.mainContext)
        session.sortedLoggedExercises[0].sets[0].isCompleted = true
        var draft = WorkoutExerciseListDraft(session: session)
        let picks = ["Curl", "Fly"].map { Exercise(name: $0, category: .strength, equipment: .dumbbell, primaryMuscleGroup: .chest) }
        draft.append(picks)
        XCTAssertEqual(draft.exercises.map(\.name), ["Bench Press", "Barbell Row", "Back Squat", "Curl", "Fly"])
        XCTAssertTrue(draft.exercises.suffix(2).allSatisfy(\.isNew))
        XCTAssertEqual(session.sortedLoggedExercises.count, 3)
    }

    func testDraftAddRemoveAndReorderSaveOnceAndKeepDraftForRetry() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(library)
        try context.save()
        let baseline = WorkoutExerciseListSnapshot(session: session)
        var draft = WorkoutExerciseListDraft(session: session)
        let addition = WorkoutExerciseListDraft.Addition(exercise: library)
        draft.additions.append(addition)
        draft.orderedIDs = [baseline.exercises[2].id, addition.id, baseline.exercises[0].id]
        XCTAssertTrue(draft.exercises[1].isNew)
        XCTAssertEqual(session.sortedLoggedExercises.count, 3)
        let engine = ActiveWorkoutEngine()
        XCTAssertThrowsError(try engine.applyExerciseListChanges(in: session, orderedIDs: draft.orderedIDs, baseline: baseline, additions: draft.additions, context: context, save: { _ in throw CocoaError(.fileWriteUnknown) }))
        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), baseline)
        var saves = 0
        try engine.applyExerciseListChanges(in: session, orderedIDs: draft.orderedIDs, baseline: baseline, additions: draft.additions, context: context, save: { saves += 1; try $0.save() })
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName), ["Back Squat", "Curl", "Bench Press"])
        XCTAssertFalse(session.sortedLoggedExercises[1].sortedSets.isEmpty)
    }

    private func fixture(in context: ModelContext) throws -> WorkoutSession {
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active, source: .blank)
        for (index, name) in ["Bench Press", "Barbell Row", "Back Squat"].enumerated() {
            let exercise = Exercise(name: name, category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
            let logged = LoggedExercise(orderIndex: index, exercise: exercise,
                                        sets: (0..<4).map { LoggedSet(orderIndex: $0) })
            session.loggedExercises.append(logged)
            logged.session = session
        }
        context.insert(session)
        try context.save()
        return session
    }
}
