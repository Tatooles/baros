import SwiftData
import XCTest
@testable import BarosCore

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
