import XCTest
@testable import Baros

final class LaunchExperienceCoordinatorTests: XCTestCase {
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

    func testExistingUserReceivesUnseenCurrentReleaseHighlights() throws {
        let release = makeRelease(version: "1.2")

        let presentation = LaunchExperienceCoordinator.nextPresentation(
            state: LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: "1.0",
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
            currentRelease: AppReleaseDefinition(version: "1.1", whatsNewContent: nil)
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

    private func makeRelease(version: String) -> AppReleaseDefinition {
        AppReleaseDefinition(
            version: version,
            whatsNewContent: WhatsNewContent(
                title: "What's New in \(version)",
                summary: "Release notes.",
                items: [
                    LaunchExperienceItem(
                        id: "release-\(version)",
                        systemImage: "sparkles",
                        title: "Highlights",
                        detail: "The latest improvements."
                    ),
                ]
            )
        )
    }
}
