import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class SyncOutboxRecorderTests: XCTestCase {
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
        XCTAssertEqual(entry.createdAt, createdAt)
        XCTAssertEqual(entry.updatedAt, deletedAt)
        XCTAssertEqual(entry.lastAttemptAt, attemptedAt)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertNil(entry.lastErrorMessage)
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
        XCTAssertEqual(entry.createdAt, updatedAt)
        XCTAssertEqual(entry.updatedAt, deletedAt)
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

        XCTAssertEqual(pending.map(\.id), [earlierInFlight.id, earlierFailed.id, laterPending.id])
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

    private func fetchEntries(_ context: ModelContext) throws -> [SyncOutboxEntry] {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            .sorted { $0.createdAt < $1.createdAt }
    }
}
