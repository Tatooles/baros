import XCTest
@testable import Baros

final class EmptyHistoryPresentationTests: XCTestCase {
    func testLocalOnlyShowsSignInRecoveryPrompt() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .localOnly,
                isSyncing: false
            ),
            .signInRecovery
        )
    }

    func testResolvingShowsSyncingWithoutFlashingSignInOrEmptyState() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .resolving(ownerTokenIdentifier: nil),
                isSyncing: false
            ),
            .syncing
        )

        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .resolving(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: false
            ),
            .syncing
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
                hasVisibleCompletedWorkouts: true
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
}
