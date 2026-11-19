import XCTest
@testable import Baros
@testable import BarosCore

final class LaunchExperienceCoordinatorTests: XCTestCase {
    func testActiveWorkoutAlwaysDefersLaunchPresentation() {
        for currentOwnerState in [
            CurrentOwnerCoordinator.State.resolving(ownerTokenIdentifier: "issuer|owner"),
            .active(ownerTokenIdentifier: "issuer|owner"),
            .localOnly,
        ] {
            XCTAssertEqual(
                LaunchExperienceCoordinator.decision(
                    currentOwnerState: currentOwnerState,
                    activeWorkoutID: UUID()
                ),
                .skipForActiveWorkout
            )
        }
    }

    func testSignedInLaunchWithoutCompletedOnboardingCompletesSilently() {
        let incomplete = LaunchExperienceState(
            hasCompletedOnboarding: false,
            lastProcessedAppVersion: nil,
            lastSeenWhatsNewVersion: nil
        )

        for currentOwnerState in [
            CurrentOwnerCoordinator.State.active(ownerTokenIdentifier: "issuer|owner"),
            .resolving(ownerTokenIdentifier: "issuer|owner"),
        ] {
            XCTAssertTrue(
                LaunchExperienceCoordinator.shouldCompleteOnboardingSilently(
                    state: incomplete,
                    currentOwnerState: currentOwnerState
                )
            )
        }
    }
}
