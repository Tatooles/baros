import SwiftData
import XCTest
@testable import Baros

@MainActor
final class SyncOutboxEntryTests: XCTestCase {
    func testSyncEntityKindRawValuesMatchConvexTablesForV1Scope() {
        XCTAssertEqual(SyncEntityKind.userSettings.rawValue, "userSettings")
        XCTAssertEqual(SyncEntityKind.exercise.rawValue, "exercises")
        XCTAssertEqual(SyncEntityKind.workoutSession.rawValue, "workoutSessions")
        XCTAssertEqual(SyncEntityKind.loggedExercise.rawValue, "loggedExercises")
        XCTAssertEqual(SyncEntityKind.loggedSet.rawValue, "loggedSets")
        XCTAssertEqual(SyncEntityKind.workoutTemplate.rawValue, "workoutTemplates")
        XCTAssertEqual(SyncEntityKind.healthDataLink.rawValue, "healthDataLinks")
        XCTAssertEqual(SyncEntityKind.seedMetadata.rawValue, "seedMetadata")
    }

    func testOutboxEntryPersistsRequiredMetadata() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let attemptedAt = Date(timeIntervalSince1970: 300)
        let entry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: entityID,
            operation: .update,
            status: .failed,
            ownerTokenIdentifier: "issuer|user_123",
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastAttemptAt: attemptedAt,
            attemptCount: 2,
            lastErrorMessage: "offline"
        )

        context.insert(entry)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(fetched.entityKind, .exercise)
        XCTAssertEqual(fetched.entityID, entityID)
        XCTAssertEqual(fetched.operation, .update)
        XCTAssertEqual(fetched.status, .failed)
        XCTAssertEqual(fetched.ownerTokenIdentifier, "issuer|user_123")
        XCTAssertEqual(fetched.createdAt, createdAt)
        XCTAssertEqual(fetched.updatedAt, updatedAt)
        XCTAssertEqual(fetched.lastAttemptAt, attemptedAt)
        XCTAssertEqual(fetched.attemptCount, 2)
        XCTAssertEqual(fetched.lastErrorMessage, "offline")
    }

    func testOutboxEntryDefaultsToPendingCreateWithoutOwner() {
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let now = Date(timeIntervalSince1970: 400)
        let entry = SyncOutboxEntry(entityKind: .userSettings, entityID: entityID, operation: .create, now: now)

        XCTAssertEqual(entry.entityKind, .userSettings)
        XCTAssertEqual(entry.operation, .create)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertNil(entry.ownerTokenIdentifier)
        XCTAssertEqual(entry.createdAt, now)
        XCTAssertEqual(entry.updatedAt, now)
        XCTAssertNil(entry.lastAttemptAt)
        XCTAssertEqual(entry.attemptCount, 0)
        XCTAssertNil(entry.lastErrorMessage)
    }

    func testInvalidRawValuesDoNotProduceTypedOutboxWork() {
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
        let now = Date(timeIntervalSince1970: 500)
        let entry = SyncOutboxEntry(entityKind: .exercise, entityID: entityID, operation: .update, now: now)

        entry.entityKindRaw = "unknownTable"
        entry.operationRaw = "merge"
        entry.statusRaw = "paused"

        XCTAssertNil(entry.entityKind)
        XCTAssertNil(entry.operation)
        XCTAssertNil(entry.status)
        XCTAssertFalse(entry.isActive)
        XCTAssertFalse(entry.hasBeenAttempted)
    }

    func testOutboxEntryStateHelpersReflectStatusAndAttempts() {
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000000904")!
        let createdAt = Date(timeIntervalSince1970: 600)
        let attemptedAt = Date(timeIntervalSince1970: 700)
        let refreshedAt = Date(timeIntervalSince1970: 800)
        let entry = SyncOutboxEntry(
            entityKind: .loggedSet,
            entityID: entityID,
            operation: .delete,
            status: .completed,
            createdAt: createdAt,
            updatedAt: createdAt,
            lastAttemptAt: attemptedAt,
            attemptCount: 1,
            lastErrorMessage: "timeout"
        )

        XCTAssertFalse(entry.isActive)
        XCTAssertTrue(entry.hasBeenAttempted)

        entry.refreshPending(now: refreshedAt)

        XCTAssertEqual(entry.status, .pending)
        XCTAssertTrue(entry.isActive)
        XCTAssertTrue(entry.hasBeenAttempted)
        XCTAssertEqual(entry.updatedAt, refreshedAt)
        XCTAssertNil(entry.lastErrorMessage)
    }
}
