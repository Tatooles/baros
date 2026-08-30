import XCTest
@testable import Baros

final class AppAppearancePreferenceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppAppearancePreferenceStoreTests-\(UUID().uuidString)"
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
    func testFreshStoreDefaultsToDark() {
        let store = AppAppearancePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.appearance, .dark)
    }

    @MainActor
    func testSelectionPersistsAcrossStoreInstances() {
        let store = AppAppearancePreferenceStore(defaults: defaults)

        store.appearance = .light

        XCTAssertEqual(AppAppearancePreferenceStore(defaults: defaults).appearance, .light)
    }

    @MainActor
    func testStoredSystemSelectionDecodes() {
        let key = "test.app-appearance"
        defaults.set("system", forKey: key)

        let store = AppAppearancePreferenceStore(defaults: defaults, key: key)

        XCTAssertEqual(store.appearance, .system)
    }

    @MainActor
    func testInvalidStoredValueFallsBackToDark() {
        let key = "test.app-appearance"
        defaults.set("sepia", forKey: key)

        let store = AppAppearancePreferenceStore(defaults: defaults, key: key)

        XCTAssertEqual(store.appearance, .dark)
    }

    func testAppearancesMapToEffectiveColorSchemes() {
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
    }

    func testAppearanceOptionsExposeLabelsAndRowSymbols() {
        XCTAssertEqual(AppAppearance.allCases.map(\.displayName), ["Dark", "Light", "System"])
        XCTAssertEqual(
            AppAppearance.allCases.map(\.systemImage),
            ["moon.fill", "sun.max.fill", "circle.lefthalf.filled"]
        )
    }

    @MainActor
    func testUITestResetArgumentClearsStoredSelection() {
        let key = "test.app-appearance"
        AppAppearancePreferenceStore(defaults: defaults, key: key).appearance = .light

        AppAppearancePreferenceStore.resetForUITestingIfRequested(
            arguments: ["--uitest-reset-app-appearance"],
            defaults: defaults,
            key: key
        )

        XCTAssertEqual(
            AppAppearancePreferenceStore(defaults: defaults, key: key).appearance,
            .dark
        )
    }
}
