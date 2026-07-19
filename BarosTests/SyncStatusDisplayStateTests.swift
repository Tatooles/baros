import Foundation
import XCTest
@testable import Baros

final class SyncStatusDisplayStateTests: XCTestCase {
    func testSignedOutMapsToLocalOnly() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: nil,
            isSyncing: false,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 0,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .localOnly)
        XCTAssertEqual(state.title, "Sync Status")
        XCTAssertEqual(state.subtitle, "Cloud sync starts after you sign in.")
        XCTAssertEqual(state.trailingText, "Local only")
        XCTAssertEqual(state.tint, .secondary)
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.showsGlobalFailureNotice)
    }

    func testSyncingStateWinsOverQueuedWork() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: true,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 3,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .syncing)
        XCTAssertEqual(state.subtitle, "Sending and receiving changes.")
        XCTAssertEqual(state.trailingText, "Syncing")
        XCTAssertEqual(state.tint, .attention)
        XCTAssertFalse(state.canRetry)
    }

    func testFailedEntriesMapToNeedsAttentionAndGlobalNotice() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            lastSyncedAt: Date(timeIntervalSince1970: 940),
            lastFailureMessage: "Convex function sync:fetchChanges failed for token issuer|owner_a",
            pendingCount: 2,
            failedCount: 1,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .needsAttention)
        XCTAssertEqual(state.subtitle, "Cloud sync could not finish. Your data is saved on this iPhone.")
        XCTAssertEqual(state.detailText, "1 failed, 2 waiting. Last synced 1 min ago.")
        XCTAssertEqual(state.trailingText, "Retry")
        XCTAssertEqual(state.tint, .attention)
        XCTAssertTrue(state.canRetry)
        XCTAssertTrue(state.showsGlobalFailureNotice)
        XCTAssertEqual(state.userVisibleFailureMessage, "Cloud sync could not finish. Your data is saved on this iPhone.")
    }

    func testPendingWorkMapsToWaitingToSync() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 4,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .waiting)
        XCTAssertEqual(state.subtitle, "4 changes waiting for cloud sync.")
        XCTAssertEqual(state.trailingText, "Waiting")
        XCTAssertEqual(state.tint, .secondary)
        XCTAssertTrue(state.canRetry)
        XCTAssertFalse(state.showsGlobalFailureNotice)
    }

    func testLastSyncedUsesRelativeMinutes() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            lastSyncedAt: Date(timeIntervalSince1970: 700),
            lastFailureMessage: nil,
            pendingCount: 0,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .upToDate)
        XCTAssertEqual(state.subtitle, "Last synced 5 min ago.")
        XCTAssertEqual(state.trailingText, "Up to date")
        XCTAssertEqual(state.tint, .success)
        XCTAssertFalse(state.canRetry)
    }

    func testKnownOfflineErrorUsesShortReason() {
        XCTAssertEqual(
            SyncStatusDisplayState.sanitizedFailureReason(from: "The Internet connection appears to be offline."),
            "The network appears to be offline."
        )
    }

    func testFailureMessageWithoutCountsUsesSanitizedDetailText() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            lastSyncedAt: nil,
            lastFailureMessage: "offline",
            pendingCount: 0,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .needsAttention)
        XCTAssertEqual(state.detailText, "The network appears to be offline.")
    }

    func testFailedOutboxPushWithCloudSyncCopyDoesNotUseIncompleteWorkoutWarning() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            lastSyncedAt: nil,
            lastFailureMessage: "Cloud sync could not finish.",
            lastFailureReason: .failedOutboxPush,
            pendingCount: 0,
            failedCount: 1,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .needsAttention)
        XCTAssertEqual(state.title, "Sync Status")
        XCTAssertEqual(state.subtitle, "Cloud sync could not finish. Your data is saved on this iPhone.")
        XCTAssertEqual(state.userVisibleFailureMessage, "Cloud sync could not finish. Your data is saved on this iPhone.")
    }

    func testIncompleteRemotePullUsesWorkoutDataWarningCopy() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            lastSyncedAt: nil,
            lastFailureMessage: "Cloud sync could not finish.",
            lastFailureReason: .incompleteRemotePull,
            pendingCount: 0,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .needsAttention)
        XCTAssertEqual(state.title, "Cloud sync could not finish")
        XCTAssertEqual(state.subtitle, "Some cloud workout data is incomplete. Your local data is still available.")
        XCTAssertNil(state.detailText)
        XCTAssertEqual(state.trailingText, "Retry")
        XCTAssertTrue(state.canRetry)
        XCTAssertTrue(state.showsGlobalFailureNotice)
        XCTAssertEqual(state.failureNoticeTitle, "Cloud sync could not finish")
        XCTAssertEqual(state.failureNoticeMessage, "Some cloud workout data is incomplete. Your local data is still available.")
        XCTAssertEqual(state.userVisibleFailureMessage, "Some cloud workout data is incomplete. Your local data is still available.")
    }
}
