import XCTest
@testable import Baros

final class LaunchExperienceCoordinatorTests: XCTestCase {
    func testLaunchPresentationWaitsForOwnerScopeResolution() {
        XCTAssertEqual(
            LaunchExperienceCoordinator.decision(
                currentOwnerState: .resolving(ownerTokenIdentifier: nil),
                activeWorkoutID: nil
            ),
            .deferUntilOwnerScopeResolves
        )
        XCTAssertEqual(
            LaunchExperienceCoordinator.decision(
                currentOwnerState: .resolving(ownerTokenIdentifier: "issuer|owner"),
                activeWorkoutID: nil
            ),
            .evaluateStore
        )
        XCTAssertEqual(
            LaunchExperienceCoordinator.decision(
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner"),
                activeWorkoutID: nil
            ),
            .evaluateStore
        )
        XCTAssertEqual(
            LaunchExperienceCoordinator.decision(
                currentOwnerState: .localOnly,
                activeWorkoutID: nil
            ),
            .evaluateStore
        )
    }

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

    func testNewUserReceivesOnboardingInsteadOfCurrentReleaseHighlights() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.release(for: "1.0"))

        let presentation = LaunchExperienceCoordinator.nextPresentation(
            state: LaunchExperienceState(
                hasCompletedOnboarding: false,
                lastProcessedAppVersion: nil,
                lastSeenWhatsNewVersion: nil
            ),
            currentRelease: release
        )

        XCTAssertEqual(presentation, .onboarding)
    }

    func testExistingOneOneUserReceivesUnseenOneTwoReleaseHighlights() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.release(for: "1.2"))

        let presentation = LaunchExperienceCoordinator.nextPresentation(
            state: LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: "1.1",
                lastSeenWhatsNewVersion: nil
            ),
            currentRelease: release
        )

        XCTAssertEqual(presentation, .whatsNew(try XCTUnwrap(release.whatsNew)))
    }

    func testExistingUserDoesNotReceiveSeenReleaseHighlights() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.release(for: "1.0"))

        let presentation = LaunchExperienceCoordinator.nextPresentation(
            state: LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: "0.9",
                lastSeenWhatsNewVersion: "1.0"
            ),
            currentRelease: release
        )

        XCTAssertNil(presentation)
    }

    func testExistingUserDoesNotReceiveOnboardingOrHighlightsForReleaseWithoutContent() {
        let presentation = LaunchExperienceCoordinator.nextPresentation(
            state: LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: "1.0",
                lastSeenWhatsNewVersion: "1.0"
            ),
            currentRelease: AppReleaseDefinition(version: "1.1", whatsNewSheet: nil)
        )

        XCTAssertNil(presentation)
    }

    func testExistingOneZeroUserWithoutProcessedVersionSkipsOneOneHighlights() throws {
        let presentation = LaunchExperienceCoordinator.nextPresentation(
            state: LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: nil,
                lastSeenWhatsNewVersion: "1.0"
            ),
            currentRelease: try XCTUnwrap(AppReleaseCatalog.release(for: "1.1"))
        )

        XCTAssertNil(presentation)
    }

    func testExistingUserDoesNotReceiveHighlightsAddedWithinSameAppVersion() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.release(for: "1.0"))

        let presentation = LaunchExperienceCoordinator.nextPresentation(
            state: LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: "1.0",
                lastSeenWhatsNewVersion: nil
            ),
            currentRelease: release
        )

        XCTAssertNil(presentation)
    }
}
