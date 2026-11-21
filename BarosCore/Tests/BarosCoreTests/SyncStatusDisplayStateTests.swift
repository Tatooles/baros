import Foundation
import XCTest
@testable import BarosCore

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

    func testNetworkUnavailableInterruptionMapsToWaitingForConnection() {
        for networkAvailability in [NetworkAvailability.unknown, .available] {
            let state = SyncStatusDisplayState.make(
                ownerTokenIdentifier: "issuer|owner_a",
                isSyncing: false,
                networkAvailability: networkAvailability,
                transientCondition: .networkUnavailable,
                lastSyncedAt: nil,
                lastFailureMessage: nil,
                pendingCount: 0,
                failedCount: 0,
                now: Date(timeIntervalSince1970: 1_000)
            )

            XCTAssertEqual(state.kind, .waitingForConnection, "\(networkAvailability)")
            XCTAssertEqual(
                state.subtitle,
                "Waiting for connection. Your data is saved on this iPhone.",
                "\(networkAvailability)"
            )
            XCTAssertEqual(state.trailingText, "Retry", "\(networkAvailability)")
            XCTAssertTrue(state.canRetry, "\(networkAvailability)")
            XCTAssertFalse(state.showsGlobalFailureNotice, "\(networkAvailability)")
        }
    }

    func testTimedOutPullDoesNotAppearUpToDate() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            transientCondition: .requestTimedOut,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 0,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .waiting)
        XCTAssertEqual(state.subtitle, "Cloud sync was interrupted. Your data is saved on this iPhone.")
        XCTAssertEqual(state.trailingText, "Retry")
        XCTAssertTrue(state.canRetry)
        XCTAssertFalse(state.showsGlobalFailureNotice)
    }

    func testQueuedSchedulerRequestMapsToWaiting() {
        for networkAvailability in [NetworkAvailability.unknown, .available] {
            let state = SyncStatusDisplayState.make(
                ownerTokenIdentifier: "issuer|owner_a",
                isSyncing: false,
                networkAvailability: networkAvailability,
                hasQueuedSyncRequest: true,
                lastSyncedAt: nil,
                lastFailureMessage: nil,
                pendingCount: 0,
                failedCount: 0,
                now: Date(timeIntervalSince1970: 1_000)
            )

            XCTAssertEqual(state.kind, .waiting, "\(networkAvailability)")
            XCTAssertEqual(state.subtitle, "Cloud sync is waiting to resume.", "\(networkAvailability)")
            XCTAssertEqual(state.trailingText, "Waiting", "\(networkAvailability)")
            XCTAssertTrue(state.canRetry, "\(networkAvailability)")
        }
    }

    func testDurableFailureWinsOverTransientInterruption() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            transientCondition: .networkUnavailable,
            lastSyncedAt: nil,
            lastFailureMessage: "Cloud sync could not finish.",
            lastFailureReason: .failedOutboxPush,
            pendingCount: 0,
            failedCount: 1,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .needsAttention)
        XCTAssertTrue(state.showsGlobalFailureNotice)
    }

    func testUnavailableNetworkMapsActiveSyncToWaitingForConnection() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: true,
            networkAvailability: .unavailable,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 1,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .waitingForConnection)
        XCTAssertEqual(state.subtitle, "Waiting for connection. Your data is saved on this iPhone.")
        XCTAssertEqual(state.detailText, "1 waiting.")
        XCTAssertEqual(state.trailingText, "Offline")
        XCTAssertEqual(state.tint, .secondary)
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.showsGlobalFailureNotice)
    }

    func testUnavailableNetworkKeepsPendingWorkWaitingAfterSyncAttemptSettles() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            networkAvailability: .unavailable,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 1,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .waitingForConnection)
        XCTAssertEqual(state.subtitle, "Waiting for connection. Your data is saved on this iPhone.")
        XCTAssertEqual(state.detailText, "1 waiting.")
        XCTAssertEqual(state.trailingText, "Offline")
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.showsGlobalFailureNotice)
    }

    func testUnavailableNetworkKeepsQueuedSchedulerWorkWaiting() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            networkAvailability: .unavailable,
            hasQueuedSyncRequest: true,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 0,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .waitingForConnection)
        XCTAssertEqual(state.trailingText, "Offline")
        XCTAssertFalse(state.canRetry)
    }

    func testUnavailableNetworkWithoutUnfinishedWorkShowsOfflineInsteadOfUpToDate() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            networkAvailability: .unavailable,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 0,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .waitingForConnection)
        XCTAssertEqual(state.subtitle, "Waiting for connection. Your data is saved on this iPhone.")
        XCTAssertEqual(state.trailingText, "Offline")
        XCTAssertEqual(state.systemImage, "icloud.slash")
        XCTAssertEqual(state.tint, .secondary)
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.showsGlobalFailureNotice)
    }

    func testRequiresConnectionKeepsManualRetryAvailable() {
        let cases: [(transientCondition: SyncStableErrorCode?, pendingCount: Int)] = [
            (nil, 0),
            (.networkUnavailable, 1),
        ]
        for testCase in cases {
            let state = SyncStatusDisplayState.make(
                ownerTokenIdentifier: "issuer|owner_a",
                isSyncing: false,
                networkAvailability: .requiresConnection,
                transientCondition: testCase.transientCondition,
                lastSyncedAt: nil,
                lastFailureMessage: nil,
                pendingCount: testCase.pendingCount,
                failedCount: 0,
                now: Date(timeIntervalSince1970: 1_000)
            )

            XCTAssertEqual(state.kind, .waitingForConnection, "\(testCase)")
            XCTAssertEqual(state.trailingText, "Retry", "\(testCase)")
            XCTAssertTrue(state.canRetry, "\(testCase)")
        }
    }

    func testUnavailableNetworkMapsTimedOutPullWithoutOutboxWorkToOffline() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            networkAvailability: .unavailable,
            transientCondition: .requestTimedOut,
            lastSyncedAt: nil,
            lastFailureMessage: nil,
            pendingCount: 0,
            failedCount: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .waitingForConnection)
        XCTAssertEqual(state.subtitle, "Waiting for connection. Your data is saved on this iPhone.")
        XCTAssertEqual(state.trailingText, "Offline")
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.showsGlobalFailureNotice)
    }

    func testUnavailableNetworkKeepsDurableSyncFailureInNeedsAttention() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: false,
            networkAvailability: .unavailable,
            lastSyncedAt: nil,
            lastFailureMessage: "Cloud sync could not finish.",
            lastFailureReason: .failedOutboxPush,
            pendingCount: 0,
            failedCount: 1,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .needsAttention)
        XCTAssertEqual(state.detailText, "1 failed.")
        XCTAssertEqual(state.trailingText, "Retry")
        XCTAssertTrue(state.canRetry)
        XCTAssertTrue(state.showsGlobalFailureNotice)
    }

    func testUnavailableNetworkKeepsDurableFailureVisibleDuringRetry() {
        let state = SyncStatusDisplayState.make(
            ownerTokenIdentifier: "issuer|owner_a",
            isSyncing: true,
            networkAvailability: .unavailable,
            lastSyncedAt: nil,
            lastFailureMessage: "Cloud sync could not finish.",
            lastFailureReason: .failedOutboxPush,
            pendingCount: 0,
            failedCount: 1,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(state.kind, .needsAttention)
        XCTAssertEqual(state.trailingText, "Retry")
        XCTAssertTrue(state.showsGlobalFailureNotice)
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
        XCTAssertEqual(state.tint, .destructive)
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

    func testLocalChangeSyncCycleKeepsOneSecondaryLine() {
        let lastSyncedAt = Date(timeIntervalSince1970: 700)
        let now = Date(timeIntervalSince1970: 1_000)
        let states = [
            SyncStatusDisplayState.make(
                ownerTokenIdentifier: "issuer|owner_a", isSyncing: false, lastSyncedAt: lastSyncedAt,
                lastFailureMessage: nil, pendingCount: 0, failedCount: 0, now: now
            ),
            SyncStatusDisplayState.make(
                ownerTokenIdentifier: "issuer|owner_a", isSyncing: false, lastSyncedAt: lastSyncedAt,
                lastFailureMessage: nil, pendingCount: 1, failedCount: 0, now: now
            ),
            SyncStatusDisplayState.make(
                ownerTokenIdentifier: "issuer|owner_a", isSyncing: false, hasQueuedSyncRequest: true,
                lastSyncedAt: lastSyncedAt, lastFailureMessage: nil, pendingCount: 0, failedCount: 0, now: now
            ),
            SyncStatusDisplayState.make(
                ownerTokenIdentifier: "issuer|owner_a", isSyncing: true, lastSyncedAt: lastSyncedAt,
                lastFailureMessage: nil, pendingCount: 1, failedCount: 0, now: now
            ),
        ]

        XCTAssertEqual(states.map(\.kind), [.upToDate, .waiting, .waiting, .syncing])
        for state in states {
            XCTAssertNil(state.detailText, "\(state.kind)")
        }
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
