import SwiftData
import XCTest
@testable import Baros

/// Rollback ownership: whichever layer performs the save owns the matching
/// rollback. `SyncOutboxTransaction` rolls back the owner-scoped path and
/// restores in-flight outbox bookkeeping; the domain modules roll back their
/// local-only path. Callers never roll back on top of either, because a second
/// `rollback()` discards the restored bookkeeping.
@MainActor
final class SyncOutboxRollbackOwnershipTests: XCTestCase {

    // MARK: - Active Workout edits survive a suppressed save failure

    func testSuppressedActiveWorkoutTitleSaveFailureLeavesNoDirtyDomainState() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            title: "Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank
        )
        context.insert(session)
        try context.save()
        let engine = ActiveWorkoutEngine(save: { _ in throw RollbackOwnershipTestError.saveFailed })

        XCTAssertThrowsError(
            try engine.commitWorkoutTitle("Leg Day", session: session, context: context)
        ) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try persistedWorkout(in: container).title, "Workout")
    }

    func testSuppressedActiveWorkoutSetSaveFailureLeavesNoDirtyDomainState() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let (session, _, set) = makeActiveWorkoutGraph()
        context.insert(session)
        try context.save()
        let engine = ActiveWorkoutEngine(save: { _ in throw RollbackOwnershipTestError.saveFailed })

        XCTAssertThrowsError(
            try engine.updateSet(set, weight: 225, reps: 5, rpe: nil, context: context)
        ) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertFalse(context.hasChanges)
        let persistedSet = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<LoggedSet>()).first
        )
        XCTAssertNil(persistedSet.weight)
        XCTAssertNil(persistedSet.reps)
    }

    /// The Finish sheet and the set rows suppress save failures with `try?`. If
    /// such a failure left the edited models dirty, the transaction preflight
    /// would treat the workout's own pending edits as unrelated state, roll them
    /// back, and refuse to finish with `unexpectedUnsavedDomainChanges`.
    func testFinishingSucceedsAfterASuppressedActiveWorkoutSaveFailure() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let (session, _, set) = makeActiveWorkoutGraph(ownerTokenIdentifier: ownerTokenIdentifier)
        context.insert(session)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(modelContext: context, syncScheduler: scheduler)
        let failingEngine = ActiveWorkoutEngine(save: { _ in throw RollbackOwnershipTestError.saveFailed })
        let engine = ActiveWorkoutEngine()

        // Exactly what `SetRowView` and `FinishWorkoutSheet` do on a failed commit.
        try? failingEngine.updateSet(set, weight: 225, reps: 5, rpe: nil, context: context)
        try? failingEngine.commitWorkoutTitle("Leg Day", session: session, context: context)

        try engine.finishWorkout(
            session,
            ownerTokenIdentifier: ownerTokenIdentifier,
            syncOutboxTransaction: transaction,
            context: context,
            now: Date(timeIntervalSince1970: 300)
        )

        let verificationContext = ModelContext(container)
        let persisted = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WorkoutSession>()).first
        )
        XCTAssertEqual(persisted.status, .completed)
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertFalse(try fetchOutboxEntries(in: verificationContext).isEmpty)
    }

    // MARK: - Every rollback owner preserves concurrent outbox bookkeeping

    /// A rollback owner shares the app's one `ModelContext` with `pushPendingEntries`,
    /// which leaves in-flight bookkeeping unsaved while suspended at its network
    /// `await`. A bare `rollback()` would revert that bookkeeping to pending and
    /// push a remote mutation that already succeeded a second time.
    func testFailedActiveWorkoutSavePreservesConcurrentInFlightBookkeeping() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            title: "Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank
        )
        context.insert(session)
        let (recorder, entry, attemptedAt) = try makeSuspendedInFlightEntry(in: context)
        let engine = ActiveWorkoutEngine(save: { _ in throw RollbackOwnershipTestError.saveFailed })
        _ = recorder

        XCTAssertThrowsError(
            try engine.commitWorkoutTitle("Leg Day", session: session, context: context)
        ) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        try assertInFlightBookkeepingSurvivesTheNextSave(
            entry: entry,
            attemptedAt: attemptedAt,
            context: context,
            container: container
        )
    }

    func testFailedLocalOnlyMutationPreservesConcurrentInFlightBookkeeping() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let (session, _, _) = makeLoggedWorkoutGraph(ownerTokenIdentifier: nil)
        context.insert(session)
        let (recorder, entry, attemptedAt) = try makeSuspendedInFlightEntry(in: context)
        let service = WorkoutHistoryMutationService(save: { _ in throw RollbackOwnershipTestError.saveFailed })
        _ = recorder

        XCTAssertThrowsError(try service.deleteWorkoutHistory(session, context: context)) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        try assertInFlightBookkeepingSurvivesTheNextSave(
            entry: entry,
            attemptedAt: attemptedAt,
            context: context,
            container: container
        )
    }

    /// The consequence the snapshot exists to prevent: a bare `rollback()` clears
    /// the entry's dirty flag, so the next save persists nothing and the store
    /// still holds `pending` — the already-pushed mutation runs again.
    private func assertInFlightBookkeepingSurvivesTheNextSave(
        entry: SyncOutboxEntry,
        attemptedAt: Date,
        context: ModelContext,
        container: ModelContainer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(context.hasChanges, "rollback discarded the unsaved bookkeeping", file: file, line: line)
        try context.save()

        let persisted = try XCTUnwrap(
            fetchOutboxEntries(in: ModelContext(container)).first { $0.id == entry.id },
            file: file,
            line: line
        )
        XCTAssertEqual(persisted.status, .inFlight, file: file, line: line)
        XCTAssertEqual(persisted.attemptCount, 1, file: file, line: line)
        XCTAssertEqual(persisted.lastAttemptAt, attemptedAt, file: file, line: line)
    }

    // MARK: - The transaction is the sole rollback owner of the owner-scoped path

    /// A foreground transaction can fail while `pushPendingEntries` is suspended
    /// at a network `await`. The transaction restores that unsaved in-flight
    /// bookkeeping; a caller that rolled back again would discard the
    /// restoration and push an already-completed intent a second time.
    func testFailedOwnedSettingsUpdateLeavesInFlightBookkeepingRestoredForTheCaller() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let settings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(settings)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(
            entityKind: .userSettings,
            entityID: settings.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()
        let entry = try XCTUnwrap(fetchOutboxEntries(in: context).first)
        let attemptedAt = Date(timeIntervalSince1970: 150)
        recorder.markInFlight(entry, now: attemptedAt)
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler,
            save: { _ in throw RollbackOwnershipTestError.saveFailed }
        )
        let service = SettingsMutationService(syncOutboxTransaction: transaction)

        XCTAssertThrowsError(
            try service.updateWeightUnit(.kilograms, settings: settings, context: context)
        ) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertEqual(entry.status, .inFlight)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testFailedOwnedExerciseRemovalLeavesInFlightBookkeepingRestoredForTheCaller() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(exercise)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()
        let entry = try XCTUnwrap(fetchOutboxEntries(in: context).first)
        let attemptedAt = Date(timeIntervalSince1970: 150)
        recorder.markInFlight(entry, now: attemptedAt)
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler,
            save: { _ in throw RollbackOwnershipTestError.saveFailed }
        )
        let service = ExerciseMutationService(syncOutboxTransaction: transaction)

        XCTAssertThrowsError(try service.removeExercise(exercise, context: context)) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertEqual(entry.status, .inFlight)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testFailedOwnedWorkoutHistoryDeleteLeavesInFlightBookkeepingRestoredForTheCaller() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let (session, _, _) = makeLoggedWorkoutGraph(ownerTokenIdentifier: ownerTokenIdentifier)
        context.insert(session)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(
            entityKind: .workoutSession,
            entityID: session.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()
        let entry = try XCTUnwrap(fetchOutboxEntries(in: context).first)
        let attemptedAt = Date(timeIntervalSince1970: 150)
        recorder.markInFlight(entry, now: attemptedAt)
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler,
            save: { _ in throw RollbackOwnershipTestError.saveFailed }
        )
        let service = WorkoutHistoryMutationService(syncOutboxTransaction: transaction)

        XCTAssertThrowsError(try service.deleteWorkoutHistory(session, context: context)) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertEqual(entry.status, .inFlight)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    // MARK: - Domain modules roll back their own local-only path

    func testFailedLocalOnlyExerciseCreateRollsBackInsideTheService() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let service = ExerciseMutationService(save: { _ in throw RollbackOwnershipTestError.saveFailed })

        XCTAssertThrowsError(
            try service.createExercise(
                name: "Bench Press",
                category: .strength,
                equipment: .barbell,
                primaryMuscle: "Chest",
                notes: "",
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
    }

    func testFailedLocalOnlyExerciseUpdateRollsBackInsideTheService() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(exercise)
        try context.save()
        let service = ExerciseMutationService(save: { _ in throw RollbackOwnershipTestError.saveFailed })

        XCTAssertThrowsError(
            try service.updateExercise(
                exercise,
                name: "Incline Bench Press",
                category: .strength,
                equipment: .barbell,
                primaryMuscle: "Chest",
                notes: "",
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(
            try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Exercise>()).first).name,
            "Bench Press"
        )
    }

    func testFailedLocalOnlySettingsUpdateRollsBackInsideTheService() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(defaultRestTimerSeconds: 90)
        context.insert(settings)
        try context.save()
        let service = SettingsMutationService(save: { _ in throw RollbackOwnershipTestError.saveFailed })

        XCTAssertThrowsError(
            try service.updateDefaultRestTimerSeconds(120, settings: settings, context: context)
        ) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(
            try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<UserSettings>()).first)
                .defaultRestTimerSeconds,
            90
        )
    }

    func testFailedUnclaimedWorkoutHistoryDeleteRollsBackInsideTheService() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let (session, _, _) = makeLoggedWorkoutGraph(ownerTokenIdentifier: nil)
        context.insert(session)
        try context.save()
        let service = WorkoutHistoryMutationService(save: { _ in throw RollbackOwnershipTestError.saveFailed })

        XCTAssertThrowsError(try service.deleteWorkoutHistory(session, context: context)) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertNil(try persistedWorkout(in: container).deletedAt)
    }

    func testFailedUnclaimedWorkoutHistoryEditRollsBackInsideTheService() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let (session, _, _) = makeLoggedWorkoutGraph(ownerTokenIdentifier: nil)
        context.insert(session)
        try context.save()
        let service = WorkoutHistoryMutationService(save: { _ in throw RollbackOwnershipTestError.saveFailed })
        var draft = CompletedWorkoutEditDraft(session: session)
        draft.title = "Leg Day"

        XCTAssertThrowsError(
            try service.saveCompletedWorkoutEdit(draft, for: session, context: context)
        ) { error in
            XCTAssertEqual(error as? RollbackOwnershipTestError, .saveFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try persistedWorkout(in: container).title, "Push Day")
    }

    // MARK: - Helpers

    /// Models a sync suspended at its network `await`: the entry is saved as
    /// pending, then marked in-flight without saving, exactly as
    /// `pushPendingEntries` leaves it while the request is outstanding.
    private func makeSuspendedInFlightEntry(
        in context: ModelContext
    ) throws -> (SyncOutboxRecorder, SyncOutboxEntry, Date) {
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(
            entityKind: .exercise,
            entityID: UUID(),
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()
        let entry = try XCTUnwrap(fetchOutboxEntries(in: context).first)
        let attemptedAt = Date(timeIntervalSince1970: 150)
        recorder.markInFlight(entry, now: attemptedAt)
        return (recorder, entry, attemptedAt)
    }

    /// `rollback()` discards the context's pending changes but leaves the
    /// already-registered model objects holding their assigned values, so the
    /// persisted state has to be read back through a fresh context.
    private func persistedWorkout(in container: ModelContainer) throws -> WorkoutSession {
        try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<WorkoutSession>()).first)
    }

    private func fetchOutboxEntries(in context: ModelContext) throws -> [SyncOutboxEntry] {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>())
    }

    private func makeActiveWorkoutGraph(
        ownerTokenIdentifier: String? = nil
    ) -> (WorkoutSession, LoggedExercise, LoggedSet) {
        makeWorkoutGraph(status: .active, ownerTokenIdentifier: ownerTokenIdentifier)
    }

    private func makeLoggedWorkoutGraph(
        ownerTokenIdentifier: String?
    ) -> (WorkoutSession, LoggedExercise, LoggedSet) {
        makeWorkoutGraph(status: .completed, ownerTokenIdentifier: ownerTokenIdentifier)
    }

    private func makeWorkoutGraph(
        status: WorkoutSessionStatus,
        ownerTokenIdentifier: String?
    ) -> (WorkoutSession, LoggedExercise, LoggedSet) {
        let session = WorkoutSession(
            title: "Push Day",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: status == .completed ? Date(timeIntervalSince1970: 200) : nil,
            status: status,
            source: .blank,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let set = LoggedSet(orderIndex: 0)
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        return (session, loggedExercise, set)
    }
}

private enum RollbackOwnershipTestError: Error, Equatable {
    case saveFailed
}
