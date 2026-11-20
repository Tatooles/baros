import Foundation
import SwiftData

public enum RPEPreference {
    public static let storageKey = "Baros.RPE.enabled"
    private static let didCheckExistingRatingsKey = "Baros.RPE.didCheckExistingRatings"

    public static func checkExistingRatingsOnce(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: didCheckExistingRatingsKey) else { return }
        var descriptor = FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.rpe != nil && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        guard let ratedSets = try? context.fetch(descriptor) else { return }
        if !ratedSets.isEmpty {
            enableIfUndecided(defaults: defaults)
        }
        defaults.set(true, forKey: didCheckExistingRatingsKey)
    }

    static func choose(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: storageKey)
    }

    static func enableIfUndecided(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: storageKey) == nil else { return }
        defaults.set(true, forKey: storageKey)
    }

    public static func applyUITestingOverrides(arguments: [String], defaults: UserDefaults = .standard) {
        if arguments.contains("--uitest-reset-rpe") {
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: didCheckExistingRatingsKey)
        } else if arguments.contains("--uitest-disable-rpe") {
            defaults.set(false, forKey: storageKey)
        } else if arguments.contains("--uitest-enable-rpe") {
            defaults.set(true, forKey: storageKey)
        }
    }
}
