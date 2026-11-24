import SwiftData
import XCTest
@testable import BarosCore

@MainActor
final class WorkoutExerciseListTests: XCTestCase {
    func testDraftProtectsUncheckedValuesAndCompletedSetsButNotBlankSuggestions() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let session = try fixture(in: container.mainContext)
        let first = session.sortedLoggedExercises[0]
        let sets = first.sortedSets
        sets[0].weight = 0
        sets[1].reps = 5
        sets[2].isCompleted = true
        var draft = WorkoutExerciseListDraft(session: session)
        draft.orderedIDs.removeFirst()
        XCTAssertEqual(draft.removedExercises[0].loggedSetCount, 3)
        XCTAssertTrue(draft.pendingSetLoss == (3, 1))
        XCTAssertEqual(draft.lossyRemovedExerciseNames, [draft.removedExercises[0].name])
        XCTAssertEqual(session.sortedLoggedExercises.count, 3, "A draft cannot mutate the live workout")

        draft = WorkoutExerciseListDraft(session: session)
        draft.orderedIDs.removeLast()
        XCTAssertEqual(draft.removedExercises[0].loggedSetCount, 0)
        XCTAssertTrue(draft.pendingSetLoss == (0, 0), "Removing an empty exercise loses nothing")

        // Unchecking a set keeps its RPE, so an RPE alone still counts as entered.
        session.sortedLoggedExercises[2].sortedSets[0].rpe = 8
        draft = WorkoutExerciseListDraft(session: session)
        draft.orderedIDs.removeLast()
        XCTAssertTrue(draft.pendingSetLoss == (1, 1))
    }

    func testCombinedSaveSoftDeletesAndReordersOnceWithoutDeletingLibraryOrOldTombstones() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let exercises = session.sortedLoggedExercises
        let removed = exercises[1]
        let oldSet = removed.sortedSets[0]
        let oldDate = afterFixtureCreation(10)
        oldSet.markDeleted(now: oldDate)
        try context.save()
        let baseline = WorkoutExerciseListSnapshot(session: session)
        let engine = ActiveWorkoutEngine()
        var saves = 0
        let now = afterFixtureCreation(200)
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
        exercise.sortedSets[0].reps = 8
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

    func testDraftPreviewAndSavedSetsUseTheSameHistoryPlan() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        let kinds: [SetKind] = [.warmup, .working, .working]
        let logged = LoggedExercise(orderIndex: 0, exercise: library,
                                    sets: kinds.enumerated().map { LoggedSet(orderIndex: $0.offset, kind: $0.element, isCompleted: true) })
        let history = WorkoutSession(title: "Past", startedAt: .now.addingTimeInterval(-3600),
                                     status: .completed, source: .blank, loggedExercises: [logged])
        context.insert(history)
        try context.save()
        let engine = ActiveWorkoutEngine()
        var draft = WorkoutExerciseListDraft(session: session)
        draft.append([library]) { engine.initialSetKinds(for: $0, ownerTokenIdentifier: nil, sessions: [history]) }
        XCTAssertEqual(draft.exercises.last?.progressText, "0/3 sets")
        XCTAssertTrue(draft.exercises.last?.accessibilityValue.contains("New") == true)
        logged.sets.forEach { $0.isCompleted = false }
        try context.save()
        try engine.applyExerciseListChanges(in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline,
                                             additions: draft.additions, context: context)
        XCTAssertEqual(session.sortedLoggedExercises.last?.sortedSets.map(\.kind), kinds)
    }

    func testDraftRejectsLibraryAdditionsThatAreNoLongerVisible() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(library)
        try context.save()
        let engine = ActiveWorkoutEngine()
        var draft = WorkoutExerciseListDraft(session: session)
        draft.append([library])
        XCTAssertEqual(draft.exercises.last?.progressText, "0/1 sets")
        for state in 0..<3 {
            library.isArchived = state == 0
            library.deletedAt = state == 1 ? .now : nil
            library.syncOwnerTokenIdentifier = state == 2 ? "another-owner" : nil
            try context.save()
            var saves = 0
            XCTAssertThrowsError(try engine.applyExerciseListChanges(in: session, orderedIDs: draft.orderedIDs,
                baseline: draft.baseline, additions: draft.additions, context: context, save: { _ in saves += 1 }))
            XCTAssertEqual(saves, 0)
            XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), draft.baseline)
        }
    }

    func testAddRefusesWhatEditWorkoutRefusesWithAnAddMessage() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(library)
        try context.save()
        let baseline = WorkoutExerciseListSnapshot(session: session)
        let engine = ActiveWorkoutEngine()
        for state in 0..<4 {
            library.isArchived = state == 0
            library.deletedAt = state == 1 ? .now : nil
            library.syncOwnerTokenIdentifier = state == 2 ? "another-owner" : nil
            session.status = state == 3 ? .completed : .active
            try context.save()
            var saves = 0
            XCTAssertThrowsError(try engine.addExercises([library], to: session, context: context,
                                                         save: { _ in saves += 1 })) { error in
                XCTAssertEqual(error as? ActiveWorkoutEngineError, .exercisesUnavailableToAdd, "state \(state)")
            }
            XCTAssertEqual(saves, 0)
            session.status = .active
            XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), baseline)
        }
        let message = try XCTUnwrap(ActiveWorkoutEngineError.exercisesUnavailableToAdd.errorDescription)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("try"), "Retrying can't fix a refused add")
    }

    func testAddWaitsForAPendingSetSaveLikeOtherStructuralChanges() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = try fixture(in: context)
        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(library)
        try context.save()
        let engine = ActiveWorkoutEngine()
        let set = session.sortedLoggedExercises[0].sortedSets[0]
        XCTAssertThrowsError(try engine.toggleSetCompletion(set, context: context,
                                                             save: { _ in throw CocoaError(.fileWriteUnknown) }))
        XCTAssertTrue(engine.hasPendingSetSave)
        let baseline = WorkoutExerciseListSnapshot(session: session)

        XCTAssertThrowsError(try engine.addExercises([library], to: session, context: context)) { error in
            XCTAssertEqual(error as? ActiveWorkoutEngineError, .structuralChangeUnavailable)
        }
        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), baseline)
        try engine.retrySetSave(in: session, context: context)
        XCTAssertEqual(try engine.addExercises([library], to: session, context: context).count, 1)
    }

    /// Synced workouts can hold positions with gaps, a superset left with one member, or a
    /// superset split by another exercise. Adding must not tidy those rows, or the add would
    /// re-upload exercises the user never touched.
    func testAddLeavesExistingRowsAsTheyAreEvenWhenTheirOrderAndSupersetsAreUntidy() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let (session, before) = try untidyFixture(in: context)
        let picks = ["Curl", "Fly"].map { Exercise(name: $0, category: .strength, equipment: .dumbbell, primaryMuscleGroup: .chest) }
        picks.forEach { context.insert($0) }

        let added = try ActiveWorkoutEngine().addExercises(picks, to: session, asSuperset: true, context: context)

        XCTAssertEqual(rowStates(session).prefix(3).map { $0 }, before)
        XCTAssertEqual(added.map(\.exerciseSnapshotName), ["Curl", "Fly"])
        XCTAssertEqual(added.map(\.orderIndex), [8, 9])
        let group = try XCTUnwrap(added[0].supersetGroupID)
        XCTAssertEqual(added[1].supersetGroupID, group)
        XCTAssertFalse(before.contains { $0.group == group })
        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName),
                       ["Bench Press", "Barbell Row", "Back Squat", "Curl", "Fly"])
    }

    func testEditWorkoutSaveThatOnlyAddsLeavesExistingRowsAsTheyAre() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let (session, before) = try untidyFixture(in: context)
        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(library)
        var draft = WorkoutExerciseListDraft(session: session)
        draft.append([library])

        try ActiveWorkoutEngine().applyExerciseListChanges(
            in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline, additions: draft.additions,
            supersetGroupIDs: draft.supersetGroupIDs, context: context
        )

        XCTAssertEqual(rowStates(session).prefix(3).map { $0 }, before)
        XCTAssertEqual(session.sortedLoggedExercises.last?.exerciseSnapshotName, "Curl")
        XCTAssertEqual(session.sortedLoggedExercises.last?.orderIndex, 8)
        XCTAssertNil(session.sortedLoggedExercises.last?.supersetGroupID)
    }

    func testEditWorkoutSaveThatAlsoMovesARowStillRenumbersAndTidies() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let (session, _) = try untidyFixture(in: context)
        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(library)
        var draft = WorkoutExerciseListDraft(session: session)
        draft.append([library])
        draft.orderedIDs.swapAt(0, 2)

        try ActiveWorkoutEngine().applyExerciseListChanges(
            in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline, additions: draft.additions,
            supersetGroupIDs: draft.supersetGroupIDs, context: context
        )

        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1, 2, 3])
        XCTAssertTrue(session.sortedLoggedExercises.allSatisfy { $0.supersetGroupID == nil })
    }

    private struct RowState: Equatable {
        let id: UUID
        let orderIndex: Int
        let group: UUID?
        let hasLocalSupersetChange: Bool
        let updatedAt: Date
    }

    private func rowStates(_ session: WorkoutSession) -> [RowState] {
        session.sortedLoggedExercises.map {
            RowState(id: $0.id, orderIndex: $0.orderIndex, group: $0.supersetGroupID,
                     hasLocalSupersetChange: $0.hasLocalSupersetChange, updatedAt: $0.updatedAt)
        }
    }

    /// Positions 0, 3, 7, with the first and last sharing a superset id across a single.
    private func untidyFixture(in context: ModelContext) throws -> (WorkoutSession, [RowState]) {
        let session = try fixture(in: context)
        let split = UUID()
        let stamp = Date(timeIntervalSince1970: 1_000_000)
        for (logged, (orderIndex, group)) in zip(session.sortedLoggedExercises, [(0, split), (3, nil), (7, split)]) {
            logged.orderIndex = orderIndex
            logged.supersetGroupID = group
            logged.updatedAt = stamp
        }
        try context.save()
        let before = rowStates(session)
        XCTAssertEqual(before.map(\.orderIndex), [0, 3, 7])
        return (session, before)
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
