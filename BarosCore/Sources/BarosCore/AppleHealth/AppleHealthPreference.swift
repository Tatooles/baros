import Foundation

/// The **Save Workouts to Apple Health** setting. Off by default; device-local, never synced.
public enum AppleHealthPreference {
    public static let storageKey = "Baros.AppleHealth.saveWorkouts"

    public static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: storageKey)
    }

    public static func setEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: storageKey)
    }
}
