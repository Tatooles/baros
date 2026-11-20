import Foundation

@MainActor
public final class FirstRunExperienceStore {
    private enum Key {
        static let hasSeenWelcome = "Baros.FirstRunExperience.hasSeenWelcome"
        static let lastProcessedAppVersion = "Baros.FirstRunExperience.lastProcessedAppVersion"
        static let lastSeenWhatsNewVersion = "Baros.FirstRunExperience.lastSeenWhatsNewVersion"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var state: LaunchExperienceState {
        LaunchExperienceState(
            hasCompletedOnboarding: defaults.bool(forKey: Key.hasSeenWelcome),
            lastProcessedAppVersion: defaults.string(forKey: Key.lastProcessedAppVersion),
            lastSeenWhatsNewVersion: defaults.string(forKey: Key.lastSeenWhatsNewVersion)
        )
    }

    public func markOnboardingCompleted(currentRelease: AppReleaseDefinition) {
        defaults.set(true, forKey: Key.hasSeenWelcome)
        markAppVersionProcessed(currentRelease.version)
        if let currentWhatsNew = currentRelease.whatsNew {
            defaults.set(currentWhatsNew.version, forKey: Key.lastSeenWhatsNewVersion)
        }
    }

    public func markAppVersionProcessed(_ version: String) {
        defaults.set(version, forKey: Key.lastProcessedAppVersion)
    }

    public func markWhatsNewSeen(version: String) {
        defaults.set(version, forKey: Key.lastSeenWhatsNewVersion)
    }

    public static func resetForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--uitest-reset-first-run-experience") else {
            return
        }

        defaults.removeObject(forKey: Key.hasSeenWelcome)
        defaults.removeObject(forKey: Key.lastProcessedAppVersion)
        defaults.removeObject(forKey: Key.lastSeenWhatsNewVersion)
    }

    public static func markSeenForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--uitest-skip-first-run-experience") else {
            return
        }
        guard !arguments.contains("--uitest-reset-first-run-experience") else {
            return
        }

        FirstRunExperienceStore(defaults: defaults).markOnboardingCompleted(
            currentRelease: AppReleaseCatalog.definition(for: AppBuildInfo.current.version)
        )
    }
}
