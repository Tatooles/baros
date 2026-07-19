import Foundation

@MainActor
final class FirstRunExperienceStore {
    private enum Key {
        // Preserve the existing defaults namespace so an in-place rebrand does not
        // replay onboarding or What's New for current installations.
        static let hasSeenWelcome = "LiftingLog.FirstRunExperience.hasSeenWelcome"
        static let lastSeenWhatsNewVersion = "LiftingLog.FirstRunExperience.lastSeenWhatsNewVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSeenWelcome: Bool {
        defaults.bool(forKey: Key.hasSeenWelcome)
    }

    var lastSeenWhatsNewVersion: String? {
        defaults.string(forKey: Key.lastSeenWhatsNewVersion)
    }

    func shouldShowWelcome() -> Bool {
        !hasSeenWelcome
    }

    func shouldShowWhatsNew(for release: WhatsNewRelease) -> Bool {
        hasSeenWelcome &&
            release.shouldAutoShow &&
            lastSeenWhatsNewVersion != release.version
    }

    func markWelcomeSeen(currentWhatsNewVersion: String) {
        defaults.set(true, forKey: Key.hasSeenWelcome)
        defaults.set(currentWhatsNewVersion, forKey: Key.lastSeenWhatsNewVersion)
    }

    func markWhatsNewSeen(version: String) {
        defaults.set(version, forKey: Key.lastSeenWhatsNewVersion)
    }

    static func resetForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--uitest-reset-first-run-experience") else {
            return
        }

        defaults.removeObject(forKey: Key.hasSeenWelcome)
        defaults.removeObject(forKey: Key.lastSeenWhatsNewVersion)
    }

    static func markSeenForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--uitest-skip-first-run-experience") else {
            return
        }
        guard !arguments.contains("--uitest-reset-first-run-experience") else {
            return
        }

        FirstRunExperienceStore(defaults: defaults).markWelcomeSeen(
            currentWhatsNewVersion: WhatsNewContent.current().version
        )
    }
}
