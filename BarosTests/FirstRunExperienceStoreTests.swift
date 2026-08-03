import XCTest
@testable import Baros

final class FirstRunExperienceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "FirstRunExperienceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func testStoreStartsWithIncompleteOnboardingAndNoSeenRelease() {
        let store = FirstRunExperienceStore(defaults: defaults)

        XCTAssertEqual(
            store.state,
            LaunchExperienceState(
                hasCompletedOnboarding: false,
                lastProcessedAppVersion: nil,
                lastSeenWhatsNewVersion: nil
            )
        )
    }

    @MainActor
    func testCompletingOnboardingConsumesCurrentReleaseHighlights() throws {
        let store = FirstRunExperienceStore(defaults: defaults)
        let release = try XCTUnwrap(AppReleaseCatalog.whatsNew(for: "1.0"))

        store.markOnboardingCompleted(
            currentRelease: try XCTUnwrap(AppReleaseCatalog.release(for: release.version))
        )

        XCTAssertEqual(
            store.state,
            LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: "1.0",
                lastSeenWhatsNewVersion: "1.0"
            )
        )
        XCTAssertNil(
            LaunchExperienceCoordinator.nextPresentation(
                state: store.state,
                currentRelease: try XCTUnwrap(AppReleaseCatalog.release(for: "1.0"))
            )
        )
    }

    @MainActor
    func testExistingUserSeesNewReleaseHighlightsOnce() throws {
        let store = FirstRunExperienceStore(defaults: defaults)
        store.markOnboardingCompleted(
            currentRelease: try XCTUnwrap(AppReleaseCatalog.release(for: "1.0"))
        )
        let release = makeRelease(version: "1.2")
        let whatsNew = try XCTUnwrap(release.whatsNew)

        XCTAssertEqual(
            LaunchExperienceCoordinator.nextPresentation(
                state: store.state,
                currentRelease: release
            ),
            .whatsNew(whatsNew)
        )

        store.markWhatsNewSeen(version: whatsNew.version)
        store.markAppVersionProcessed("1.2")

        XCTAssertNil(
            LaunchExperienceCoordinator.nextPresentation(
                state: store.state,
                currentRelease: release
            )
        )
    }

    @MainActor
    func testExistingUserHasNoPresentationForReleaseWithoutHighlights() throws {
        let store = FirstRunExperienceStore(defaults: defaults)
        store.markOnboardingCompleted(
            currentRelease: try XCTUnwrap(AppReleaseCatalog.release(for: "1.0"))
        )

        XCTAssertNil(
            LaunchExperienceCoordinator.nextPresentation(
                state: store.state,
                currentRelease: try XCTUnwrap(AppReleaseCatalog.release(for: "1.1"))
            )
        )

        store.markAppVersionProcessed("1.1")

        XCTAssertEqual(store.state.lastProcessedAppVersion, "1.1")
    }

    @MainActor
    func testResetForUITestingClearsStoredValues() throws {
        let store = FirstRunExperienceStore(defaults: defaults)
        store.markOnboardingCompleted(
            currentRelease: try XCTUnwrap(AppReleaseCatalog.release(for: "1.0"))
        )

        FirstRunExperienceStore.resetForUITestingIfRequested(
            arguments: ["--uitest-reset-first-run-experience"],
            defaults: defaults
        )

        XCTAssertEqual(
            store.state,
            LaunchExperienceState(
                hasCompletedOnboarding: false,
                lastProcessedAppVersion: nil,
                lastSeenWhatsNewVersion: nil
            )
        )
    }

    @MainActor
    func testMarkSeenForUITestingSkipsFirstRunExperience() {
        let store = FirstRunExperienceStore(defaults: defaults)

        FirstRunExperienceStore.markSeenForUITestingIfRequested(
            arguments: ["--uitest-skip-first-run-experience"],
            defaults: defaults
        )

        XCTAssertEqual(
            store.state,
            LaunchExperienceState(
                hasCompletedOnboarding: true,
                lastProcessedAppVersion: AppBuildInfo.current.version,
                lastSeenWhatsNewVersion: nil
            )
        )
    }

    @MainActor
    func testResetForUITestingTakesPrecedenceOverSkip() {
        let store = FirstRunExperienceStore(defaults: defaults)

        FirstRunExperienceStore.resetForUITestingIfRequested(
            arguments: ["--uitest-reset-first-run-experience", "--uitest-skip-first-run-experience"],
            defaults: defaults
        )
        FirstRunExperienceStore.markSeenForUITestingIfRequested(
            arguments: ["--uitest-reset-first-run-experience", "--uitest-skip-first-run-experience"],
            defaults: defaults
        )

        XCTAssertEqual(
            store.state,
            LaunchExperienceState(
                hasCompletedOnboarding: false,
                lastProcessedAppVersion: nil,
                lastSeenWhatsNewVersion: nil
            )
        )
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
