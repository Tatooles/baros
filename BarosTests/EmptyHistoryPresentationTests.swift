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

    func testResolvingShowsSyncingOnlyWhileAuthenticationRecoveryIsRunning() {
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

    func testResolvingWithoutKnownOwnerShowsOrdinaryEmptyWhileAuthenticationLoads() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .resolving(ownerTokenIdentifier: nil),
                isSyncing: false,
                isRecoveringAuthentication: true
            ),
            .ordinaryEmpty
        )
    }

    func testActiveOwnerShowsSyncingOnlyWhileRecoveryIsRunning() {
        XCTAssertEqual(
            EmptyHistoryPresentation.make(
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner"),
                isSyncing: false,
                isRecoveringAuthentication: true
            ),
            .syncing
        )

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
}
