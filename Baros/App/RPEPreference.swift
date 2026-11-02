import Foundation
import SwiftData

/// RPE entry is off until someone chooses it, unless they already have ratings:
/// those on this device are checked once ever, and synced ones turn it on as they
/// arrive. A choice in Settings is never overridden.
enum RPEPreference {
    static let storageKey = "Baros.RPE.enabled"
    private static let didCheckExistingRatingsKey = "Baros.RPE.didCheckExistingRatings"

    static func checkExistingRatingsOnce(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: didCheckExistingRatingsKey) else { return }
        var descriptor = FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.rpe != nil && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        // A failed read tries again next launch.
        guard let ratedSets = try? context.fetch(descriptor) else { return }
        if !ratedSets.isEmpty {
            enableIfUndecided(defaults: defaults)
        }
        defaults.set(true, forKey: didCheckExistingRatingsKey)
    }

    static func enableIfUndecided(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: storageKey) == nil else { return }
        defaults.set(true, forKey: storageKey)
    }

    static func applyUITestingOverrides(arguments: [String], defaults: UserDefaults = .standard) {
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
