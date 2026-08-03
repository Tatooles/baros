import Foundation

@MainActor
final class FirstRunExperienceStore {
    private enum Key {
        // The beta rebrand intentionally uses a new defaults namespace so current
        // installations see the Baros onboarding experience. Keep the original
        // key value so users who completed the welcome remain completed.
        static let hasCompletedOnboarding = "Baros.FirstRunExperience.hasSeenWelcome"
        static let lastProcessedAppVersion = "Baros.FirstRunExperience.lastProcessedAppVersion"
        static let lastSeenWhatsNewVersion = "Baros.FirstRunExperience.lastSeenWhatsNewVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var state: LaunchExperienceState {
        LaunchExperienceState(
            hasCompletedOnboarding: defaults.bool(forKey: Key.hasCompletedOnboarding),
            lastProcessedAppVersion: defaults.string(forKey: Key.lastProcessedAppVersion),
            lastSeenWhatsNewVersion: defaults.string(forKey: Key.lastSeenWhatsNewVersion)
        )
    }

    func markOnboardingCompleted(currentRelease: AppReleaseDefinition) {
        defaults.set(true, forKey: Key.hasCompletedOnboarding)
        markAppVersionProcessed(currentRelease.version)
        if let currentWhatsNew = currentRelease.whatsNew {
            defaults.set(currentWhatsNew.version, forKey: Key.lastSeenWhatsNewVersion)
        }
    }

    func markAppVersionProcessed(_ version: String) {
        defaults.set(version, forKey: Key.lastProcessedAppVersion)
    }

    func markWhatsNewSeen(version: String) {
        defaults.set(version, forKey: Key.lastSeenWhatsNewVersion)
    }

    static func resetForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--uitest-reset-first-run-experience") else {
            return
        }

        defaults.removeObject(forKey: Key.hasCompletedOnboarding)
        defaults.removeObject(forKey: Key.lastProcessedAppVersion)
        defaults.removeObject(forKey: Key.lastSeenWhatsNewVersion)
    }

    static func markSeenForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
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
