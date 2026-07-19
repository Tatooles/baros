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
    func testFreshInstallShowsWelcomeOnly() {
        let store = FirstRunExperienceStore(defaults: defaults)
        let release = WhatsNewRelease(
            version: "1.0",
            title: "What's New in 1.0",
            summary: "Initial release notes.",
            items: [
                WhatsNewItem(id: "sync", systemImage: "icloud", title: "Cloud sync", detail: "Completed workouts sync after sign in."),
            ],
            shouldAutoShow: true
        )

        XCTAssertTrue(store.shouldShowWelcome())
        XCTAssertFalse(store.shouldShowWhatsNew(for: release))
    }

    @MainActor
    func testMarkWelcomeSeenSuppressesCurrentWhatsNewVersion() {
        let store = FirstRunExperienceStore(defaults: defaults)
        let release = WhatsNewRelease(
            version: "1.0",
            title: "What's New in 1.0",
            summary: "Initial release notes.",
            items: [
                WhatsNewItem(id: "sync", systemImage: "icloud", title: "Cloud sync", detail: "Completed workouts sync after sign in."),
            ],
            shouldAutoShow: true
        )

        store.markWelcomeSeen(currentWhatsNewVersion: release.version)

        XCTAssertFalse(store.shouldShowWelcome())
        XCTAssertFalse(store.shouldShowWhatsNew(for: release))
        XCTAssertEqual(store.lastSeenWhatsNewVersion, "1.0")
    }

    @MainActor
    func testExistingUserSeesAutoShownNewVersionOnce() {
        let store = FirstRunExperienceStore(defaults: defaults)
        store.markWelcomeSeen(currentWhatsNewVersion: "1.0")
        let release = WhatsNewRelease(
            version: "1.1",
            title: "What's New in 1.1",
            summary: "Update release notes.",
            items: [
                WhatsNewItem(id: "export", systemImage: "square.and.arrow.up", title: "Export", detail: "Workout export is easier to find."),
            ],
            shouldAutoShow: true
        )

        XCTAssertTrue(store.shouldShowWhatsNew(for: release))

        store.markWhatsNewSeen(version: release.version)

        XCTAssertFalse(store.shouldShowWhatsNew(for: release))
    }

    @MainActor
    func testReleaseCanOptOutOfAutomaticWhatsNewPresentation() {
        let store = FirstRunExperienceStore(defaults: defaults)
        store.markWelcomeSeen(currentWhatsNewVersion: "1.0")
        let release = WhatsNewRelease(
            version: "1.1",
            title: "What's New in 1.1",
            summary: "Small fixes.",
            items: [
                WhatsNewItem(id: "fixes", systemImage: "checkmark.circle", title: "Fixes", detail: "A few details work better."),
            ],
            shouldAutoShow: false
        )

        XCTAssertFalse(store.shouldShowWhatsNew(for: release))
    }

    @MainActor
    func testResetForUITestingClearsStoredValues() {
        let store = FirstRunExperienceStore(defaults: defaults)
        store.markWelcomeSeen(currentWhatsNewVersion: "1.0")

        FirstRunExperienceStore.resetForUITestingIfRequested(
            arguments: ["--uitest-reset-first-run-experience"],
            defaults: defaults
        )

        XCTAssertTrue(store.shouldShowWelcome())
        XCTAssertNil(store.lastSeenWhatsNewVersion)
    }

    @MainActor
    func testMarkSeenForUITestingSkipsFirstRunExperience() {
        let store = FirstRunExperienceStore(defaults: defaults)

        FirstRunExperienceStore.markSeenForUITestingIfRequested(
            arguments: ["--uitest-skip-first-run-experience"],
            defaults: defaults
        )

        XCTAssertFalse(store.shouldShowWelcome())
        XCTAssertEqual(store.lastSeenWhatsNewVersion, WhatsNewContent.current().version)
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

        XCTAssertTrue(store.shouldShowWelcome())
        XCTAssertNil(store.lastSeenWhatsNewVersion)
    }
}
