import SwiftData
import SwiftUI

/// An unset preference follows visible workout data, including data restored by sync.
/// Only an explicit choice is saved, so an early empty store cannot lock RPE off.
@MainActor
@propertyWrapper
struct RPEPreference: DynamicProperty {
    @AppStorage("Baros.RPE.preference") private var selection = "automatic"
    @Environment(CurrentOwnerCoordinator.self) private var owner
    @Query(filter: #Predicate<LoggedSet> { $0.rpe != nil && $0.deletedAt == nil })
    private var ratedSets: [LoggedSet]

    var wrappedValue: Bool {
        get {
            return RPEPreferencePolicy.isEnabled(selection: selection, hasLoggedRPE: ratedSets.contains {
                RPEPreferencePolicy.isVisibleRatedSet(
                    $0, ownerTokenIdentifier: owner.localDataOwnerTokenIdentifier
                )
            })
        }
        nonmutating set { selection = newValue ? "on" : "off" }
    }

    var projectedValue: Binding<Bool> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

enum RPEPreferencePolicy {
    static func isEnabled(selection: String, hasLoggedRPE: Bool) -> Bool {
        switch selection {
        case "on": true
        case "off": false
        default: hasLoggedRPE
        }
    }

    static func isVisibleRatedSet(_ set: LoggedSet, ownerTokenIdentifier: String?) -> Bool {
        guard set.deletedAt == nil,
              WorkoutNumericInputPolicy.validatedRPE(set.rpe) != nil,
              let exercise = set.loggedExercise, exercise.deletedAt == nil,
              let session = exercise.session, !session.isDeleted,
              session.status == .active || session.status == .completed else { return false }
        return session.allowsHistoryMutation(ownerTokenIdentifier: ownerTokenIdentifier)
    }
}
