import XCTest
@testable import Baros

final class SyncConflictResolverTests: XCTestCase {
    func testV1SyncScopeIncludesWorkoutGraphAndSettingsOnly() {
        XCTAssertEqual(
            SyncEntityKind.v1Synced,
            [.userSettings, .exercise, .workoutSession, .loggedExercise, .loggedSet]
        )
        XCTAssertEqual(
            SyncEntityKind.v1Excluded,
            [.workoutTemplate, .healthDataLink, .seedMetadata]
        )
    }

    func testWorkoutTemplateRemainsExcludedFromV1SyncScope() {
        XCTAssertFalse(SyncEntityKind.v1Synced.contains(.workoutTemplate))
        XCTAssertTrue(SyncEntityKind.v1Excluded.contains(.workoutTemplate))
    }

    func testLatestIncomingUpdateAppliesWhenNewerThanLocal() {
        let decision = SyncConflictResolver.decision(
            localUpdatedAt: Date(timeIntervalSince1970: 100),
            localDeletedAt: nil,
            incomingUpdatedAt: Date(timeIntervalSince1970: 200),
            incomingDeletedAt: nil
        )

        XCTAssertEqual(decision, .applyIncoming)
    }

    func testOlderIncomingUpdateDoesNotReplaceLocalTombstone() {
        let decision = SyncConflictResolver.decision(
            localUpdatedAt: Date(timeIntervalSince1970: 300),
            localDeletedAt: Date(timeIntervalSince1970: 300),
            incomingUpdatedAt: Date(timeIntervalSince1970: 200),
            incomingDeletedAt: nil
        )

        XCTAssertEqual(decision, .keepLocal)
    }

    func testNewerIncomingDeleteAppliesOverLocalActiveRecord() {
        let decision = SyncConflictResolver.decision(
            localUpdatedAt: Date(timeIntervalSince1970: 100),
            localDeletedAt: nil,
            incomingUpdatedAt: Date(timeIntervalSince1970: 200),
            incomingDeletedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(decision, .applyIncoming)
    }

    func testNewerIncomingActiveRecordDoesNotRestoreLocalTombstoneUnlessAllowed() {
        let localUpdatedAt = Date(timeIntervalSince1970: 100)
        let localDeletedAt = Date(timeIntervalSince1970: 100)
        let incomingUpdatedAt = Date(timeIntervalSince1970: 200)

        XCTAssertEqual(
            SyncConflictResolver.decision(
                localUpdatedAt: localUpdatedAt,
                localDeletedAt: localDeletedAt,
                incomingUpdatedAt: incomingUpdatedAt,
                incomingDeletedAt: nil,
                allowsIncomingRestore: false
            ),
            .keepLocal
        )
        XCTAssertEqual(
            SyncConflictResolver.decision(
                localUpdatedAt: localUpdatedAt,
                localDeletedAt: localDeletedAt,
                incomingUpdatedAt: incomingUpdatedAt,
                incomingDeletedAt: nil,
                allowsIncomingRestore: true
            ),
            .applyIncoming
        )
    }
}
