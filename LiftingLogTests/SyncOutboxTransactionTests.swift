import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class SyncOutboxTransactionTests: XCTestCase {
    func testZeroActionTransactionDoesNotSaveOrRequestSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let bookkeepingEntry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(),
            operation: .update,
            ownerTokenIdentifier: ownerTokenIdentifier,
            now: Date(timeIntervalSince1970: 100)
        )
        context.insert(bookkeepingEntry)
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { _ in }

        XCTAssertTrue(context.hasChanges)
        XCTAssertTrue(try fetchOutboxEntries(in: ModelContext(container)).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testCurrentOwnerMismatchRejectsBeforeRunningOperation() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )
        var operationRan = false

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: "issuer|owner_a") { _ in
                operationRan = true
            }
        ) { error in
            XCTAssertEqual(error as? SyncOutboxTransactionError, .currentOwnerMismatch)
        }

        XCTAssertFalse(operationRan)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testTargetOwnerMismatchRollsBackTheWholeOperation() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let settings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let otherOwnersExercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: "issuer|owner_b"
        )
        context.insert(settings)
        context.insert(otherOwnersExercise)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
                try actions.update(.userSettings(settings)) { _ in
                    settings.defaultRestTimerSeconds = 120
                }
                try actions.update(.exerciseLibraryEntry(otherOwnersExercise)) { _ in
                    otherOwnersExercise.name = "Incline Bench Press"
                }
            }
        ) { error in
            XCTAssertEqual(error as? SyncOutboxTransactionError, .targetOwnerMismatch)
        }

        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try XCTUnwrap(verificationContext.fetch(FetchDescriptor<UserSettings>()).first)
                .defaultRestTimerSeconds,
            90
        )
        XCTAssertEqual(
            try XCTUnwrap(verificationContext.fetch(FetchDescriptor<Exercise>()).first).name,
            "Bench Press"
        )
        XCTAssertTrue(try fetchOutboxEntries(in: verificationContext).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testFailedTransactionPreservesPreexistingUnsavedOutboxBookkeeping() throws {
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
            syncScheduler: scheduler
        )

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
                try actions.update(.exerciseLibraryEntry(exercise)) { _ in
                    exercise.name = "Incline Bench Press"
                    throw TestMutationError.expected
                }
            }
        ) { error in
            XCTAssertEqual(error as? TestMutationError, .expected)
        }

        XCTAssertEqual(entry.status, .inFlight)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(scheduler.requestCount, 0)

        let verificationContext = ModelContext(container)
        let persistedEntry = try XCTUnwrap(fetchOutboxEntries(in: verificationContext).first)
        XCTAssertEqual(persistedEntry.status, .pending)
        XCTAssertEqual(persistedEntry.attemptCount, 0)
        XCTAssertEqual(
            try XCTUnwrap(verificationContext.fetch(FetchDescriptor<Exercise>()).first).name,
            "Bench Press"
        )
    }

    func testSaveFailureRollsBackAndRethrowsOriginalPersistenceError() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let settings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(settings)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler,
            save: { _ in throw TestPersistenceError.expected }
        )

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
                try actions.update(.userSettings(settings)) { _ in
                    settings.defaultRestTimerSeconds = 120
                }
            }
        ) { error in
            XCTAssertEqual(error as? TestPersistenceError, .expected)
        }

        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try XCTUnwrap(verificationContext.fetch(FetchDescriptor<UserSettings>()).first)
                .defaultRestTimerSeconds,
            90
        )
        XCTAssertTrue(try fetchOutboxEntries(in: verificationContext).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testOwnedUserSettingsCreatePersistsWithCreateIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let settings = UserSettings(syncOwnerTokenIdentifier: ownerTokenIdentifier)
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.create(.userSettings(settings)) { context in
                context.insert(settings)
            }
        }

        let entry = try XCTUnwrap(fetchOutboxEntries(in: ModelContext(container)).first)
        XCTAssertEqual(entry.entityKind, .userSettings)
        XCTAssertEqual(entry.entityID, settings.id)
        XCTAssertEqual(entry.operation, .create)
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testOwnedSettingsUpdatePersistsWithOutboxIntentAndRequestsSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let now = Date(timeIntervalSince1970: 200)
        let settings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(settings)
        try context.save()

        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.update(.userSettings(settings), now: now) { _ in
                settings.defaultRestTimerSeconds = 120
                settings.touch(now: now)
            }
        }

        context.rollback()
        let entry = try XCTUnwrap(fetchOutboxEntries(in: context).first)
        XCTAssertEqual(settings.defaultRestTimerSeconds, 120)
        XCTAssertEqual(entry.entityKind, .userSettings)
        XCTAssertEqual(entry.entityID, settings.id)
        XCTAssertEqual(entry.operation, .update)
        XCTAssertEqual(entry.ownerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testOwnedExerciseLibraryEntryCreatePersistsWithCreateIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let now = Date(timeIntervalSince1970: 200)
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            createdAt: now,
            updatedAt: now
        )
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.create(.exerciseLibraryEntry(exercise), now: now) { context in
                context.insert(exercise)
            }
        }

        context.rollback()
        let entry = try XCTUnwrap(fetchOutboxEntries(in: context).first)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(\.id), [exercise.id])
        XCTAssertEqual(entry.entityKind, .exercise)
        XCTAssertEqual(entry.entityID, exercise.id)
        XCTAssertEqual(entry.operation, .create)
        XCTAssertEqual(entry.ownerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testOwnedExerciseLibraryEntryDeletePersistsWithDeleteIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let now = Date(timeIntervalSince1970: 200)
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(exercise)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.delete(.exerciseLibraryEntry(exercise), now: now) { _ in
                exercise.markDeleted(now: now)
            }
        }

        context.rollback()
        let entry = try XCTUnwrap(fetchOutboxEntries(in: context).first)
        XCTAssertEqual(exercise.deletedAt, now)
        XCTAssertEqual(entry.entityKind, .exercise)
        XCTAssertEqual(entry.entityID, exercise.id)
        XCTAssertEqual(entry.operation, .delete)
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testLoggedWorkoutGraphPersistsTogetherAndRequestsSyncOnce() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let now = Date(timeIntervalSince1970: 200)
        let session = WorkoutSession(
            title: "Push Day",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: now,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            createdAt: now,
            updatedAt: now
        )
        let set = LoggedSet(
            orderIndex: 0,
            weight: 225,
            reps: 5,
            isCompleted: true,
            createdAt: now,
            updatedAt: now
        )
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.create(.loggedWorkout(session), now: now) { context in
                context.insert(session)
            }
            try actions.create(.loggedExercise(loggedExercise), now: now) { context in
                context.insert(loggedExercise)
            }
            try actions.create(.loggedSet(set), now: now) { context in
                context.insert(set)
            }
        }

        context.rollback()
        let entries = try fetchOutboxEntries(in: context)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.contains { $0.entityKind == .workoutSession && $0.entityID == session.id })
        XCTAssertTrue(entries.contains { $0.entityKind == .loggedExercise && $0.entityID == loggedExercise.id })
        XCTAssertTrue(entries.contains { $0.entityKind == .loggedSet && $0.entityID == set.id })
        XCTAssertTrue(entries.allSatisfy { $0.operation == .create })
        XCTAssertTrue(entries.allSatisfy { $0.ownerTokenIdentifier == ownerTokenIdentifier })
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testUpdateAndDeleteMapEverySupportedTargetToTheCorrectIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let now = Date(timeIntervalSince1970: 200)
        let settings = UserSettings(syncOwnerTokenIdentifier: ownerTokenIdentifier)
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let (session, loggedExercise, set) = makeCompletedWorkoutGraph(
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(settings)
        context.insert(exercise)
        context.insert(session)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.update(.userSettings(settings), now: now) { _ in settings.touch(now: now) }
            try actions.update(.exerciseLibraryEntry(exercise), now: now) { _ in exercise.touch(now: now) }
            try actions.update(.loggedWorkout(session), now: now) { _ in session.touch(now: now) }
            try actions.update(.loggedExercise(loggedExercise), now: now) { _ in loggedExercise.touch(now: now) }
            try actions.update(.loggedSet(set), now: now) { _ in set.touch(now: now) }
        }

        assertEntries(
            try fetchOutboxEntries(in: ModelContext(container)),
            haveOperation: .update,
            for: [
                (.userSettings, settings.id),
                (.exercise, exercise.id),
                (.workoutSession, session.id),
                (.loggedExercise, loggedExercise.id),
                (.loggedSet, set.id),
            ]
        )

        for entry in try fetchOutboxEntries(in: context) {
            context.delete(entry)
        }
        try context.save()

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.delete(.userSettings(settings), now: now) { _ in settings.markDeleted(now: now) }
            try actions.delete(.exerciseLibraryEntry(exercise), now: now) { _ in exercise.markDeleted(now: now) }
            try actions.delete(.loggedWorkout(session), now: now) { _ in session.markDeleted(now: now) }
            try actions.delete(.loggedExercise(loggedExercise), now: now) { _ in loggedExercise.markDeleted(now: now) }
            try actions.delete(.loggedSet(set), now: now) { _ in set.markDeleted(now: now) }
        }

        assertEntries(
            try fetchOutboxEntries(in: ModelContext(container)),
            haveOperation: .delete,
            for: [
                (.userSettings, settings.id),
                (.exercise, exercise.id),
                (.workoutSession, session.id),
                (.loggedExercise, loggedExercise.id),
                (.loggedSet, set.id),
            ]
        )
        XCTAssertEqual(scheduler.requestCount, 2)
    }

    func testActiveWorkoutDataIsRejectedAndRolledBack() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let session = WorkoutSession(
            title: "In Progress",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(session)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
                try actions.update(.loggedWorkout(session)) { _ in
                    session.title = "Should Not Save"
                }
            }
        ) { error in
            XCTAssertEqual(error as? SyncOutboxTransactionError, .targetIsNotLoggedWorkoutData)
        }

        let verificationContext = ModelContext(container)
        let persistedSession = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WorkoutSession>()).first
        )
        XCTAssertEqual(persistedSession.title, "In Progress")
        XCTAssertTrue(try fetchOutboxEntries(in: context).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testActiveLoggedExerciseAndSetAreRejected() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let session = WorkoutSession(
            title: "In Progress",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let set = LoggedSet(orderIndex: 0, weight: 225, reps: 5)
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        context.insert(session)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
                try actions.update(.loggedExercise(loggedExercise)) { _ in
                    loggedExercise.notes = "Should not save"
                }
            }
        ) { error in
            XCTAssertEqual(error as? SyncOutboxTransactionError, .targetIsNotLoggedWorkoutData)
        }
        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
                try actions.update(.loggedSet(set)) { _ in
                    set.notes = "Should not save"
                }
            }
        ) { error in
            XCTAssertEqual(error as? SyncOutboxTransactionError, .targetIsNotLoggedWorkoutData)
        }

        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try XCTUnwrap(verificationContext.fetch(FetchDescriptor<LoggedExercise>()).first).notes,
            ""
        )
        XCTAssertEqual(
            try XCTUnwrap(verificationContext.fetch(FetchDescriptor<LoggedSet>()).first).notes,
            ""
        )
        XCTAssertTrue(try fetchOutboxEntries(in: verificationContext).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testMatchingOwnerTransactionPersistsWhileCloudSyncIsPaused() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let settings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(settings)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        scheduler.pauseCloudSync()
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.update(.userSettings(settings)) { _ in
                settings.defaultRestTimerSeconds = 120
            }
        }

        XCTAssertEqual(
            try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<UserSettings>()).first)
                .defaultRestTimerSeconds,
            120
        )
        XCTAssertEqual(try fetchOutboxEntries(in: ModelContext(container)).count, 1)
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testLaterActionFailureRollsBackEarlierDomainAndOutboxChanges() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let settings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(settings)
        context.insert(exercise)
        try context.save()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
                try actions.update(.userSettings(settings)) { _ in
                    settings.defaultRestTimerSeconds = 120
                }
                try actions.update(.exerciseLibraryEntry(exercise)) { _ in
                    exercise.name = "Incline Bench Press"
                    throw TestMutationError.expected
                }
            }
        ) { error in
            XCTAssertEqual(error as? TestMutationError, .expected)
        }

        let verificationContext = ModelContext(container)
        let persistedSettings = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<UserSettings>()).first
        )
        let persistedExercise = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<Exercise>()).first
        )
        XCTAssertEqual(persistedSettings.defaultRestTimerSeconds, 90)
        XCTAssertEqual(persistedExercise.name, "Bench Press")
        XCTAssertTrue(try fetchOutboxEntries(in: verificationContext).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testUnexpectedUnsavedDomainChangesAreRejectedAndRestored() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_a"
        let settings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(settings)
        try context.save()
        settings.defaultRestTimerSeconds = 120
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { _ in }
        ) { error in
            XCTAssertEqual(error as? SyncOutboxTransactionError, .unexpectedUnsavedDomainChanges)
        }

        let verificationContext = ModelContext(container)
        let persistedSettings = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<UserSettings>()).first
        )
        XCTAssertEqual(persistedSettings.defaultRestTimerSeconds, 90)
        XCTAssertTrue(try fetchOutboxEntries(in: verificationContext).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testUnexpectedUnsavedDomainChangesDoNotDiscardOutboxBookkeeping() throws {
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
        settings.defaultRestTimerSeconds = 120
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )

        XCTAssertThrowsError(
            try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { _ in }
        ) { error in
            XCTAssertEqual(error as? SyncOutboxTransactionError, .unexpectedUnsavedDomainChanges)
        }

        XCTAssertEqual(entry.status, .inFlight)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(scheduler.requestCount, 0)

        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try XCTUnwrap(verificationContext.fetch(FetchDescriptor<UserSettings>()).first)
                .defaultRestTimerSeconds,
            90
        )
        XCTAssertEqual(
            try XCTUnwrap(fetchOutboxEntries(in: verificationContext).first).status,
            .pending
        )
    }

    func testUpdateDuringInFlightSyncReturnsNewerIntentToPending() throws {
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
        recorder.markInFlight(entry, now: Date(timeIntervalSince1970: 150))
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let transaction = SyncOutboxTransaction(
            modelContext: context,
            syncScheduler: scheduler
        )
        let updatedAt = Date(timeIntervalSince1970: 200)

        try transaction.perform(ownerTokenIdentifier: ownerTokenIdentifier) { actions in
            try actions.update(.exerciseLibraryEntry(exercise), now: updatedAt) { _ in
                exercise.name = "Paused Bench Press"
                exercise.touch(now: updatedAt)
            }
        }
        recorder.removeCompleted(entry, context: context)
        try context.save()

        let verificationContext = ModelContext(container)
        let persistedEntry = try XCTUnwrap(fetchOutboxEntries(in: verificationContext).first)
        let persistedExercise = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<Exercise>()).first
        )
        XCTAssertEqual(persistedExercise.name, "Paused Bench Press")
        XCTAssertEqual(persistedEntry.status, .pending)
        XCTAssertEqual(persistedEntry.operation, .update)
        XCTAssertEqual(persistedEntry.updatedAt, updatedAt)
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    private func fetchOutboxEntries(in context: ModelContext) throws -> [SyncOutboxEntry] {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>())
    }

    private func makeCompletedWorkoutGraph(
        ownerTokenIdentifier: String
    ) -> (WorkoutSession, LoggedExercise, LoggedSet) {
        let session = WorkoutSession(
            title: "Push Day",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press"
        )
        let set = LoggedSet(orderIndex: 0, weight: 225, reps: 5, isCompleted: true)
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        return (session, loggedExercise, set)
    }

    private func assertEntries(
        _ entries: [SyncOutboxEntry],
        haveOperation operation: SyncOperation,
        for expectedTargets: [(SyncEntityKind, UUID)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(entries.count, expectedTargets.count, file: file, line: line)
        for (entityKind, entityID) in expectedTargets {
            XCTAssertTrue(
                entries.contains {
                    $0.entityKind == entityKind
                        && $0.entityID == entityID
                        && $0.operation == operation
                },
                "Missing \(operation) intent for \(entityKind) \(entityID)",
                file: file,
                line: line
            )
        }
    }
}

private enum TestMutationError: Error, Equatable {
    case expected
}

private enum TestPersistenceError: Error, Equatable {
    case expected
}
