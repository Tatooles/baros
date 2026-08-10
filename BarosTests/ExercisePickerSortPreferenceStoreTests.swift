import XCTest
@testable import Baros

final class ExercisePickerSortPreferenceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ExercisePickerSortPreferenceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshStoreDefaultsToRecentAndPersistsSelection() {
        let store = ExercisePickerSortPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.sortOrder, .recent)

        store.sortOrder = .mostPerformed

        XCTAssertEqual(ExercisePickerSortPreferenceStore(defaults: defaults).sortOrder, .mostPerformed)
    }

    func testInvalidStoredValueFallsBackToRecent() {
        let key = "test.exercise-picker-sort"
        defaults.set("not-a-sort-order", forKey: key)

        let store = ExercisePickerSortPreferenceStore(defaults: defaults, key: key)

        XCTAssertEqual(store.sortOrder, .recent)
    }

    func testUITestResetArgumentClearsStoredSelection() {
        let key = "test.exercise-picker-sort"
        ExercisePickerSortPreferenceStore(
            defaults: defaults,
            key: key
        ).sortOrder = .name

        ExercisePickerSortPreferenceStore.resetForUITestingIfRequested(
            arguments: ["--uitest-reset-exercise-picker-sort"],
            defaults: defaults,
            key: key
        )

        XCTAssertEqual(
            ExercisePickerSortPreferenceStore(defaults: defaults, key: key).sortOrder,
            .recent
        )
    }
}
