import SwiftData
import XCTest
@testable import Baros

@MainActor
final class SyncOutboxRecorderTests: XCTestCase {
    func testBulkCreatesMatchIndividualCreatesAcrossExistingOutboxStates() throws {
        for owner in ["issuer|owner_a", nil] as [String?] {
            let singleContainer = try SwiftDataTestSupport.makeInMemoryContainer()
            let bulkContainer = try SwiftDataTestSupport.makeInMemoryContainer()
            let singleContext = singleContainer.mainContext
            let bulkContext = bulkContainer.mainContext
            let entityIDs = (0..<10).map { _ in UUID() }
            try seedCreateCoalescingCases(entityIDs: entityIDs, owner: owner, context: singleContext)
            try seedCreateCoalescingCases(entityIDs: entityIDs, owner: owner, context: bulkContext)
            let records: [SyncOutboxRecorder.CreateRecord] = [
                .init(entityKind: .workoutSession, entityID: entityIDs[0]),
                .init(entityKind: .loggedExercise, entityID: entityIDs[1]),
                .init(entityKind: .loggedSet, entityID: entityIDs[2]),
                .init(entityKind: .loggedSet, entityID: entityIDs[3]),
                .init(entityKind: .loggedSet, entityID: entityIDs[4]),
                .init(entityKind: .loggedSet, entityID: entityIDs[4]),
                .init(entityKind: .loggedSet, entityID: entityIDs[5]),
                .init(entityKind: .loggedSet, entityID: entityIDs[6]),
                .init(entityKind: .loggedSet, entityID: entityIDs[7]),
                .init(entityKind: .workoutTemplate, entityID: entityIDs[8]),
            ]
            let recorder = SyncOutboxRecorder()
            let now = Date(timeIntervalSince1970: 500)
            for record in records {
                try recorder.recordCreate(
                    entityKind: record.entityKind,
                    entityID: record.entityID,
                    ownerTokenIdentifier: owner,
                    context: singleContext,
                    now: now
                )
            }
            try recorder.recordCreates(records, ownerTokenIdentifier: owner, context: bulkContext, now: now)
            XCTAssertTrue(bulkContext.hasChanges, "The caller still owns the save")
            try singleContext.save()
            try bulkContext.save()

            XCTAssertEqual(try entryStates(singleContext), try entryStates(bulkContext))
            let entries = try fetchEntries(bulkContext)
            let repaired = try XCTUnwrap(entries.first { $0.entityID == entityIDs[3] && $0.ownerTokenIdentifier == owner })
            XCTAssertEqual(repaired.status, .pending)
            XCTAssertEqual(repaired.operation, .create)
            let delete = try XCTUnwrap(entries.first { $0.entityID == entityIDs[2] && $0.ownerTokenIdentifier == owner })
            XCTAssertEqual(delete.operation, .delete)
            XCTAssertEqual(delete.attemptCount, 3)
            XCTAssertEqual(delete.lastAttemptAt, Date(timeIntervalSince1970: 150))
            XCTAssertNil(delete.lastErrorMessage)
        }
    }

    func testBulkCreatesIgnoreEmptyAndUnsupportedInputs() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let now = Date(timeIntervalSince1970: 500)

        try recorder.recordCreates([], ownerTokenIdentifier: nil, context: context, now: now)
        try recorder.recordCreates(
            [.init(entityKind: .workoutTemplate, entityID: UUID()),
             .init(entityKind: .healthDataLink, entityID: UUID()),
             .init(entityKind: .seedMetadata, entityID: UUID())],
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: now
        )

        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testRecordCreateCreatesPendingEntry() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001001")!
        let now = Date(timeIntervalSince1970: 100)

        try recorder.recordCreate(
            entityKind: .exercise,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: now
        )
        try context.save()

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(entry.entityKind, .exercise)
        XCTAssertEqual(entry.entityID, entityID)
        XCTAssertEqual(entry.operation, .create)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.ownerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entry.createdAt, now)
        XCTAssertEqual(entry.updatedAt, now)
        XCTAssertNil(entry.lastAttemptAt)
        XCTAssertEqual(entry.attemptCount, 0)
        XCTAssertNil(entry.lastErrorMessage)
    }

    func testUpdateCoalescesIntoPendingCreate() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001002")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)

        try recorder.recordCreate(entityKind: .loggedSet, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        try recorder.recordUpdate(entityKind: .loggedSet, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: updatedAt)
        try context.save()

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(try fetchEntries(context).count, 1)
        XCTAssertEqual(entry.operation, .create)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.createdAt, createdAt)
        XCTAssertEqual(entry.updatedAt, updatedAt)
    }

    func testUnattemptedCreateDeletedBeforeSyncRemovesEntry() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001003")!

        try recorder.recordCreate(
            entityKind: .workoutSession,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try recorder.recordDelete(
            entityKind: .workoutSession,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testAttemptedCreateDeletedBeforeAckBecomesDelete() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001004")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let attemptedAt = Date(timeIntervalSince1970: 150)
        let deletedAt = Date(timeIntervalSince1970: 200)

        try recorder.recordCreate(entityKind: .exercise, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        let createdEntry = try XCTUnwrap(fetchEntries(context).first)
        recorder.markInFlight(createdEntry, now: attemptedAt)

        try recorder.recordDelete(entityKind: .exercise, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: deletedAt)
        try context.save()

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(try fetchEntries(context).count, 1)
        XCTAssertEqual(entry.operation, .delete)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.createdAt, deletedAt)
        XCTAssertEqual(entry.updatedAt, deletedAt)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertNil(entry.lastErrorMessage)
    }

    func testRemoveCompletedLeavesPendingDeleteAfterInFlightCreateChanges() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001018")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let attemptedAt = Date(timeIntervalSince1970: 150)
        let deletedAt = Date(timeIntervalSince1970: 200)

        try recorder.recordCreate(entityKind: .exercise, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        let createdEntry = try XCTUnwrap(fetchEntries(context).first)
        recorder.markInFlight(createdEntry, now: attemptedAt)
        try recorder.recordDelete(entityKind: .exercise, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: deletedAt)

        recorder.removeCompleted(createdEntry, context: context)
        try context.save()

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(try fetchEntries(context).count, 1)
        XCTAssertEqual(entry.operation, .delete)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.createdAt, deletedAt)
        XCTAssertEqual(entry.updatedAt, deletedAt)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
    }

    func testUnattemptedWorkoutGraphCreatesDeletedBeforeSyncRemoveAllEntries() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000001019")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000001020")!
        let loggedSetID = UUID(uuidString: "00000000-0000-0000-0000-000000001021")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let deletedAt = Date(timeIntervalSince1970: 200)

        try recorder.recordCreate(entityKind: .workoutSession, entityID: sessionID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        try recorder.recordCreate(entityKind: .loggedExercise, entityID: loggedExerciseID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        try recorder.recordCreate(entityKind: .loggedSet, entityID: loggedSetID, ownerTokenIdentifier: nil, context: context, now: createdAt)

        try recorder.recordDelete(entityKind: .workoutSession, entityID: sessionID, ownerTokenIdentifier: nil, context: context, now: deletedAt)
        try recorder.recordDelete(entityKind: .loggedExercise, entityID: loggedExerciseID, ownerTokenIdentifier: nil, context: context, now: deletedAt)
        try recorder.recordDelete(entityKind: .loggedSet, entityID: loggedSetID, ownerTokenIdentifier: nil, context: context, now: deletedAt)
        try context.save()

        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testAttemptedWorkoutGraphCreatesDeletedBeforeAckBecomeDeletes() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000001022")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000001023")!
        let loggedSetID = UUID(uuidString: "00000000-0000-0000-0000-000000001024")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let attemptedAt = Date(timeIntervalSince1970: 150)
        let deletedAt = Date(timeIntervalSince1970: 200)

        try recorder.recordCreate(entityKind: .workoutSession, entityID: sessionID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        try recorder.recordCreate(entityKind: .loggedExercise, entityID: loggedExerciseID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        try recorder.recordCreate(entityKind: .loggedSet, entityID: loggedSetID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        for entry in try fetchEntries(context) {
            recorder.markInFlight(entry, now: attemptedAt)
        }

        try recorder.recordDelete(entityKind: .workoutSession, entityID: sessionID, ownerTokenIdentifier: nil, context: context, now: deletedAt)
        try recorder.recordDelete(entityKind: .loggedExercise, entityID: loggedExerciseID, ownerTokenIdentifier: nil, context: context, now: deletedAt)
        try recorder.recordDelete(entityKind: .loggedSet, entityID: loggedSetID, ownerTokenIdentifier: nil, context: context, now: deletedAt)
        try context.save()

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.operation), [.delete, .delete, .delete])
        XCTAssertEqual(entries.map(\.status), [.pending, .pending, .pending])
        XCTAssertEqual(entries.map(\.attemptCount), [1, 1, 1])
        XCTAssertEqual(entries.map(\.lastAttemptAt), [attemptedAt, attemptedAt, attemptedAt])
    }

    func testUpdateUpgradesToDelete() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001005")!
        let updatedAt = Date(timeIntervalSince1970: 100)
        let deletedAt = Date(timeIntervalSince1970: 200)

        try recorder.recordUpdate(
            entityKind: .loggedExercise,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: updatedAt
        )
        try recorder.recordDelete(
            entityKind: .loggedExercise,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: deletedAt
        )
        try context.save()

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(try fetchEntries(context).count, 1)
        XCTAssertEqual(entry.operation, .delete)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.createdAt, deletedAt)
        XCTAssertEqual(entry.updatedAt, deletedAt)
    }

    func testCreateDoesNotOverwriteExistingDelete() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001017")!
        let deletedAt = Date(timeIntervalSince1970: 100)
        let recreatedAt = Date(timeIntervalSince1970: 200)

        try recorder.recordDelete(
            entityKind: .exercise,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: deletedAt
        )
        try recorder.recordCreate(
            entityKind: .exercise,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: recreatedAt
        )
        try context.save()

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(try fetchEntries(context).count, 1)
        XCTAssertEqual(entry.operation, .delete)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.createdAt, deletedAt)
        XCTAssertEqual(entry.updatedAt, recreatedAt)
    }

    func testRetryStateTransitions() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001006")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let attemptedAt = Date(timeIntervalSince1970: 200)
        let failedAt = Date(timeIntervalSince1970: 300)
        let retryAt = Date(timeIntervalSince1970: 400)

        try recorder.recordUpdate(entityKind: .userSettings, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: createdAt)
        let entry = try XCTUnwrap(fetchEntries(context).first)

        recorder.markInFlight(entry, now: attemptedAt)
        XCTAssertEqual(entry.status, .inFlight)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertEqual(entry.updatedAt, attemptedAt)
        XCTAssertNil(entry.lastErrorMessage)

        recorder.markFailed(entry, message: "offline", now: failedAt)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertEqual(entry.updatedAt, failedAt)
        XCTAssertEqual(entry.lastErrorMessage, "offline")

        recorder.markPendingForRetry(entry, now: retryAt)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertEqual(entry.updatedAt, retryAt)
        XCTAssertNil(entry.lastErrorMessage)

        recorder.markInFlight(entry, now: Date(timeIntervalSince1970: 500))
        recorder.removeCompleted(entry, context: context)
        try context.save()

        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testPendingEntriesExcludeCompletedAndInvalidEntries() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let laterPending = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000001007")!,
            operation: .update,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let earlierFailed = SyncOutboxEntry(
            entityKind: .loggedSet,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000001008")!,
            operation: .delete,
            status: .failed,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let earlierInFlight = SyncOutboxEntry(
            entityKind: .workoutSession,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000001009")!,
            operation: .create,
            status: .inFlight,
            createdAt: Date(timeIntervalSince1970: 150),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let completed = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000001010")!,
            operation: .update,
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        let invalidKind = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000001011")!,
            operation: .update,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        invalidKind.entityKindRaw = "unknownTable"
        let invalidOperation = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000001012")!,
            operation: .update,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 20),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        invalidOperation.operationRaw = "merge"
        let invalidStatus = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000001013")!,
            operation: .update,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        invalidStatus.statusRaw = "paused"
        let excludedKind = SyncOutboxEntry(
            entityKind: .workoutTemplate,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000001014")!,
            operation: .update,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 40),
            updatedAt: Date(timeIntervalSince1970: 40)
        )

        [
            laterPending,
            earlierFailed,
            earlierInFlight,
            completed,
            invalidKind,
            invalidOperation,
            invalidStatus,
            excludedKind,
        ].forEach(context.insert)
        try context.save()

        let pending = try recorder.pendingEntries(context: context)

        XCTAssertEqual(pending.map(\.id), [laterPending.id])

        recorder.markPendingForRetry(earlierFailed, now: Date(timeIntervalSince1970: 250))

        let pendingAfterRetry = try recorder.pendingEntries(context: context)
        XCTAssertEqual(pendingAfterRetry.map(\.id), [earlierFailed.id, laterPending.id])
    }

    func testDifferentOwnersDoNotCoalesce() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001015")!

        try recorder.recordCreate(
            entityKind: .exercise,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try recorder.recordUpdate(
            entityKind: .exercise,
            entityID: entityID,
            ownerTokenIdentifier: "issuer|owner_b",
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.ownerTokenIdentifier), ["issuer|owner_a", "issuer|owner_b"])
        XCTAssertEqual(entries.map(\.operation), [.create, .update])
    }

    func testEnqueueOwnedRecordsCreatesEntriesForOnlyThatOwnersV1Records() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let now = Date(timeIntervalSince1970: 1_000)
        let settings = UserSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002001")!,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002002")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let archivedExercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002012")!,
            name: "Archived Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads",
            isArchived: true,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let loggedSet = LoggedSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002005")!,
            orderIndex: 0,
            weight: 185,
            reps: 5,
            isCompleted: true,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002004")!,
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            sets: [loggedSet]
        )
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002003")!,
            title: "Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            loggedExercises: [loggedExercise]
        )
        let discardedSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002013")!,
            title: "Discarded Pull",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .discarded,
            source: .blank,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let otherOwnerExercise = Exercise(
            name: "Other Owner Row",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Back"
        )
        let ownerlessExercise = Exercise(
            name: "Ownerless Curl",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscle: "Biceps"
        )
        settings.syncOwnerTokenIdentifier = "issuer|owner_a"
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        archivedExercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        session.syncOwnerTokenIdentifier = "issuer|owner_a"
        discardedSession.syncOwnerTokenIdentifier = "issuer|owner_a"
        otherOwnerExercise.syncOwnerTokenIdentifier = "issuer|owner_b"

        context.insert(settings)
        context.insert(exercise)
        context.insert(archivedExercise)
        context.insert(otherOwnerExercise)
        context.insert(ownerlessExercise)
        context.insert(session)
        context.insert(discardedSession)
        try context.save()

        try recorder.enqueueOwnedV1SyncableRecords(ownerTokenIdentifier: "issuer|owner_a", context: context, now: now)
        try context.save()

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 7)
        try assertBootstrapEntry(entries, entityKind: .userSettings, entityID: settings.id, operation: .create, ownerTokenIdentifier: "issuer|owner_a", updatedAt: now)
        try assertBootstrapEntry(entries, entityKind: .exercise, entityID: exercise.id, operation: .create, ownerTokenIdentifier: "issuer|owner_a", updatedAt: now)
        try assertBootstrapEntry(entries, entityKind: .exercise, entityID: archivedExercise.id, operation: .create, ownerTokenIdentifier: "issuer|owner_a", updatedAt: now)
        try assertBootstrapEntry(entries, entityKind: .workoutSession, entityID: session.id, operation: .create, ownerTokenIdentifier: "issuer|owner_a", updatedAt: now)
        try assertBootstrapEntry(entries, entityKind: .workoutSession, entityID: discardedSession.id, operation: .create, ownerTokenIdentifier: "issuer|owner_a", updatedAt: now)
        try assertBootstrapEntry(entries, entityKind: .loggedExercise, entityID: loggedExercise.id, operation: .create, ownerTokenIdentifier: "issuer|owner_a", updatedAt: now)
        try assertBootstrapEntry(entries, entityKind: .loggedSet, entityID: loggedSet.id, operation: .create, ownerTokenIdentifier: "issuer|owner_a", updatedAt: now)
    }

    func testEnqueueOwnedRecordsUsesDeleteForTombstonedRecords() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let now = Date(timeIntervalSince1970: 1_100)
        let deletedAt = Date(timeIntervalSince1970: 900)
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002006")!,
            name: "Deleted Deadlift",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Back",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"

        context.insert(exercise)
        try context.save()

        try recorder.enqueueOwnedV1SyncableRecords(ownerTokenIdentifier: "issuer|owner_a", context: context, now: now)
        try context.save()

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 1)
        try assertBootstrapEntry(entries, entityKind: .exercise, entityID: exercise.id, operation: .delete, ownerTokenIdentifier: "issuer|owner_a", updatedAt: now)
    }

    func testEnqueueOwnedRecordsSkipsActiveWorkoutGraph() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let now = Date(timeIntervalSince1970: 1_200)
        let loggedSet = LoggedSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002009")!,
            orderIndex: 0,
            weight: 95,
            reps: 8,
            isCompleted: true
        )
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002008")!,
            orderIndex: 0,
            exerciseSnapshotName: "Row",
            sets: [loggedSet]
        )
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002007")!,
            title: "Active Pull",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: "issuer|owner_a",
            loggedExercises: [loggedExercise]
        )

        context.insert(session)
        try context.save()

        try recorder.enqueueOwnedV1SyncableRecords(ownerTokenIdentifier: "issuer|owner_a", context: context, now: now)
        try context.save()

        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testEnqueueOwnedRecordsDoesNotDuplicateExistingEntries() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002010")!,
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        let existingCreatedAt = Date(timeIntervalSince1970: 100)
        let existingUpdatedAt = Date(timeIntervalSince1970: 200)

        context.insert(exercise)
        context.insert(
            SyncOutboxEntry(
                entityKind: .exercise,
                entityID: exercise.id,
                operation: .update,
                ownerTokenIdentifier: "issuer|owner_a",
                createdAt: existingCreatedAt,
                updatedAt: existingUpdatedAt
            )
        )
        try context.save()

        try recorder.enqueueOwnedV1SyncableRecords(ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 1_300))
        try context.save()

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(try fetchEntries(context).count, 1)
        XCTAssertEqual(entry.entityKind, .exercise)
        XCTAssertEqual(entry.entityID, exercise.id)
        XCTAssertEqual(entry.operation, .update)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.ownerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entry.createdAt, existingCreatedAt)
        XCTAssertEqual(entry.updatedAt, existingUpdatedAt)
    }

    func testEnqueueOwnedRecordsRespectsOwnerScopeWhenFindingExistingEntries() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let now = Date(timeIntervalSince1970: 1_400)
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002011")!,
            name: "Overhead Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Shoulders"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_b"

        context.insert(exercise)
        context.insert(
            SyncOutboxEntry(
                entityKind: .exercise,
                entityID: exercise.id,
                operation: .update,
                ownerTokenIdentifier: "issuer|owner_a",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try context.save()

        try recorder.enqueueOwnedV1SyncableRecords(ownerTokenIdentifier: "issuer|owner_b", context: context, now: now)
        try context.save()

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.ownerTokenIdentifier), ["issuer|owner_a", "issuer|owner_b"])
        XCTAssertEqual(entries.map(\.operation), [.update, .create])
        try assertBootstrapEntry(entries, entityKind: .exercise, entityID: exercise.id, operation: .create, ownerTokenIdentifier: "issuer|owner_b", updatedAt: now)
    }

    func testExcludedEntityKindsAreIgnored() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000001016")!

        try recorder.recordCreate(entityKind: .workoutTemplate, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 100))
        try recorder.recordUpdate(entityKind: .healthDataLink, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 200))
        try recorder.recordDelete(entityKind: .seedMetadata, entityID: entityID, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 300))
        try context.save()

        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    private func seedCreateCoalescingCases(entityIDs: [UUID], owner: String?, context: ModelContext) throws {
        func add(
            _ kind: SyncEntityKind,
            _ index: Int,
            _ operation: SyncOperation,
            createdAt: TimeInterval = 100,
            updatedAt: TimeInterval = 200,
            status: SyncOutboxStatus = .pending
        ) -> SyncOutboxEntry {
            let entry = SyncOutboxEntry(
                entityKind: kind,
                entityID: entityIDs[index],
                operation: operation,
                status: status,
                ownerTokenIdentifier: owner,
                createdAt: Date(timeIntervalSince1970: createdAt),
                updatedAt: Date(timeIntervalSince1970: updatedAt)
            )
            context.insert(entry)
            return entry
        }

        _ = add(.workoutSession, 0, .create)
        let failed = add(.loggedExercise, 1, .update, status: .failed)
        failed.attemptCount = 2
        failed.lastAttemptAt = Date(timeIntervalSince1970: 140)
        failed.lastErrorMessage = "retry me"
        let delete = add(.loggedSet, 2, .delete, status: .inFlight)
        delete.attemptCount = 3
        delete.lastAttemptAt = Date(timeIntervalSince1970: 150)
        delete.lastErrorMessage = "preserve delete"
        add(.loggedSet, 3, .update).statusRaw = "future-status"
        // The first repeated create refreshes the oldest updatedAt; the second
        // must then select the other entry with the same oldest createdAt.
        _ = add(.loggedSet, 4, .update, createdAt: 90, updatedAt: 80)
        _ = add(.loggedSet, 4, .delete, createdAt: 90, updatedAt: 95)
        _ = add(.loggedSet, 4, .create, createdAt: 100, updatedAt: 20)
        _ = add(.loggedSet, 5, .update, createdAt: 10, status: .completed)
        add(.loggedSet, 6, .update, createdAt: 10).operationRaw = "future-operation"
        add(.loggedSet, 6, .update, createdAt: 20).operationRaw = ""
        _ = add(.workoutTemplate, 8, .update)
        _ = add(.loggedSet, 9, .update, createdAt: 1, updatedAt: 2)
        // Same ID in a different kind, plus matching IDs owned by someone else.
        _ = add(.loggedExercise, 0, .delete, createdAt: 1)
        add(.workoutSession, 0, .delete, createdAt: 1).ownerTokenIdentifier = "issuer|owner_b"
        add(.loggedSet, 2, .update, createdAt: 1).ownerTokenIdentifier = owner == nil ? "issuer|owner_a" : nil
        try context.save()
    }

    /// Compare every persisted field other than newly generated outbox row IDs.
    private func entryStates(_ context: ModelContext) throws -> [[String]] {
        try fetchEntries(context).map { entry in
            [entry.entityKindRaw, entry.entityID.uuidString, entry.operationRaw,
             entry.statusRaw, entry.ownerTokenIdentifier ?? "<nil>",
             String(entry.createdAt.timeIntervalSince1970), String(entry.updatedAt.timeIntervalSince1970),
             entry.lastAttemptAt.map { String($0.timeIntervalSince1970) } ?? "<nil>",
             String(entry.attemptCount), entry.lastErrorMessage ?? "<nil>"]
        }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    private func fetchEntries(_ context: ModelContext) throws -> [SyncOutboxEntry] {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func assertBootstrapEntry(
        _ entries: [SyncOutboxEntry],
        entityKind: SyncEntityKind,
        entityID: UUID,
        operation: SyncOperation,
        ownerTokenIdentifier: String?,
        updatedAt: Date
    ) throws {
        let entry = try XCTUnwrap(
            entries.first {
                $0.entityKind == entityKind
                    && $0.entityID == entityID
                    && $0.ownerTokenIdentifier == ownerTokenIdentifier
            }
        )
        XCTAssertEqual(entry.operation, operation)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.createdAt, updatedAt)
        XCTAssertEqual(entry.updatedAt, updatedAt)
    }
}
