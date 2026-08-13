import XCTest
@testable import Baros

final class EmptyHistoryPresentationTests: XCTestCase {
    func testRecoveryActivityStartsWhenConfirmedSignOutTransitionsToResolving() {
        var activity = EmptyHistoryRecoveryActivity()

        activity.currentOwnerStateDidChange(
            from: .localOnly,
            to: .resolving(ownerTokenIdentifier: "issuer|owner"),
            isRecoveringAuthentication: true
        )

        XCTAssertTrue(activity.isAwaitingInitialRecovery)
    }

    func testRecoveryActivityDoesNotStartForIdleResolvingTransition() {
        var activity = EmptyHistoryRecoveryActivity()

        activity.currentOwnerStateDidChange(
            from: .localOnly,
            to: .resolving(ownerTokenIdentifier: "issuer|owner"),
            isRecoveringAuthentication: false
        )

        XCTAssertFalse(activity.isAwaitingInitialRecovery)
    }

    func testRecoveryActivityEndsWhenAuthenticationReturnsToIdleResolving() {
        var activity = EmptyHistoryRecoveryActivity()
        activity.currentOwnerStateDidChange(
            from: .localOnly,
            to: .resolving(ownerTokenIdentifier: "issuer|owner"),
            isRecoveringAuthentication: true
        )

        activity.authenticationRecoveryDidChange(
            from: true,
            to: false,
            currentOwnerState: .resolving(ownerTokenIdentifier: "issuer|owner"),
            isSyncing: false
        )

        XCTAssertFalse(activity.isAwaitingInitialRecovery)
    }

    func testLocalOnlyShowsSignInRecoveryPrompt() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .localOnly,
                isSyncing: false
            ),
            .signInRecovery
        )
    }

    func testResolvingShowsSyncingOnlyWhileAuthenticationRecoveryIsRunning() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .resolving(ownerTokenIdentifier: nil),
                isSyncing: false,
                isRecoveringAuthentication: true
            ),
            .syncing
        )

        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .resolving(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: false,
                isRecoveringAuthentication: true
            ),
            .syncing
        )

        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .resolving(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: false,
                isRecoveringAuthentication: false
            ),
            .ordinaryEmpty
        )
    }

    func testActiveOwnerShowsSyncingOnlyWhileRecoveryIsRunning() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: true
            ),
            .syncing
        )

        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: false
            ),
            .ordinaryEmpty
        )
    }

    func testVisibleCompletedWorkoutKeepsOrdinaryExerciseEmptyStateWhileLocalOnly() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .localOnly,
                isSyncing: false,
                hasVisibleCompletedWorkouts: true
            ),
            .ordinaryEmpty
        )
    }

    func testVisibleCompletedWorkoutDoesNotHideRecoveryProgress() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .resolving(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: false,
                hasVisibleCompletedWorkouts: true,
                isRecoveringAuthentication: true
            ),
            .syncing
        )

        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: true,
                hasVisibleCompletedWorkouts: true
            ),
            .syncing
        )
    }

    func testInitialRecoveryHandoffDoesNotFlashOrdinaryEmptyStateBeforeSyncStarts() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: false,
                isAwaitingInitialRecovery: true
            ),
            .syncing
        )
    }

    func testPostSignInResolvingDoesNotFlashOrdinaryEmptyStateBeforeSyncStarts() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .resolving(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: false,
                isRecoveringAuthentication: false,
                isAwaitingInitialRecovery: true
            ),
            .syncing
        )
    }
}
