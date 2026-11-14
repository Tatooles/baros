import XCTest
@testable import BarosCore

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

    func testNewUserReceivesOnboardingInsteadOfCurrentReleaseHighlights() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.release(for: "1.5"))

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

    func testExistingUserReceivesUnseenReleaseHighlightsAfterUpgrade() throws {
        // The 1.1 user never saw a What's New sheet; the 1.4 user saw the previous one.
        let upgrades: [(current: String, lastProcessed: String, lastSeen: String?)] = [
            ("1.2", "1.1", nil),
            ("1.5", "1.4", "1.4"),
        ]

        for upgrade in upgrades {
            let release = try XCTUnwrap(AppReleaseCatalog.release(for: upgrade.current), upgrade.current)

            let presentation = LaunchExperienceCoordinator.nextPresentation(
                state: LaunchExperienceState(
                    hasCompletedOnboarding: true,
                    lastProcessedAppVersion: upgrade.lastProcessed,
                    lastSeenWhatsNewVersion: upgrade.lastSeen
                ),
                currentRelease: release
            )

            XCTAssertEqual(presentation, .whatsNew(try XCTUnwrap(release.whatsNew)), upgrade.current)
        }
    }

    func testExistingUserDoesNotReceiveSeenReleaseHighlights() throws {
        let release = try XCTUnwrap(AppReleaseCatalog.release(for: "1.5"))

        let presentation = LaunchExperienceCoordinator.nextPresentation(
            state: LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: "1.4",
                lastSeenWhatsNewVersion: "1.5"
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

    func testSignedOutLaunchStillPresentsOnboarding() {
        let incomplete = LaunchExperienceState(
            hasCompletedOnboarding: false,
            lastProcessedAppVersion: nil,
            lastSeenWhatsNewVersion: nil
        )

        XCTAssertFalse(
            LaunchExperienceCoordinator.shouldCompleteOnboardingSilently(
                state: incomplete,
                currentOwnerState: .localOnly
            )
        )
    }

    func testCompletedOnboardingIsNotCompletedAgainForSignedInLaunch() {
        let completed = LaunchExperienceState(
            hasCompletedOnboarding: true,
            lastProcessedAppVersion: "1.2",
            lastSeenWhatsNewVersion: "1.2"
        )

        XCTAssertFalse(
            LaunchExperienceCoordinator.shouldCompleteOnboardingSilently(
                state: completed,
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner")
            )
        )
    }
}
