import Foundation

public final class ExercisePickerSortPreferenceStore {
    @usableFromInline static let standardKey = "Baros.ExercisePicker.sortOrder"

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = ExercisePickerSortPreferenceStore.standardKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public var sortOrder: ExercisePickerSortOrder {
        get {
            guard let rawValue = defaults.string(forKey: key) else {
                return .recent
            }

            return ExercisePickerSortOrder(rawValue: rawValue) ?? .recent
        }
        set {
            defaults.set(newValue.rawValue, forKey: key)
        }
    }

    public static func resetForUITestingIfRequested(
        arguments: [String],
        defaults: UserDefaults = .standard,
        key: String = standardKey
    ) {
        guard arguments.contains("--uitest-reset-exercise-picker-sort") else {
            return
        }

        defaults.removeObject(forKey: key)
    }
}
