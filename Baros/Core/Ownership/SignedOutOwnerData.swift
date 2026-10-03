import Foundation
import SwiftData

/// Local data that still belongs to an owner while the app is local-only. Its
/// presence means someone has signed in on this iPhone before, so Baros offers
/// to sign back in instead of treating them as a new user. Deliberate sign-out
/// and an expired session look the same here, so the copy stays neutral.
struct SignedOutOwnerData: Equatable {
    /// The owner whose workouts reappear after signing back in, or nil when
    /// several owners left data here and Baros can't tell which one signed out.
    let ownerTokenIdentifier: String?
    let completedWorkoutCount: Int

    var signInMessage: String {
        switch completedWorkoutCount {
        case 0:
            "Sign in to see the workouts saved to your account."
        case 1:
            "Your workout is safe. Sign in to see it again."
        default:
            "Your \(completedWorkoutCount) workouts are safe. Sign in to see them again."
        }
    }

    /// Scopes the count to the owner who signed out: the first preferred owner
    /// with local data, otherwise the only owner on this iPhone. Never adds up
    /// workouts across owners, because signing in reveals only one of them.
    static func find(
        in context: ModelContext,
        preferredOwnerTokenIdentifiers: [String?],
        localOwnerTokenIdentifiers: () -> Set<String>
    ) -> SignedOutOwnerData? {
        for case let ownerTokenIdentifier? in preferredOwnerTokenIdentifiers
        where hasRecords(ownedBy: ownerTokenIdentifier, in: context) {
            return makeScoped(to: ownerTokenIdentifier, in: context)
        }

        let localOwners = localOwnerTokenIdentifiers()
        if localOwners.count == 1, let ownerTokenIdentifier = localOwners.first {
            return makeScoped(to: ownerTokenIdentifier, in: context)
        }
        return localOwners.isEmpty
            ? nil
            : SignedOutOwnerData(ownerTokenIdentifier: nil, completedWorkoutCount: 0)
    }

    private static func makeScoped(to ownerTokenIdentifier: String, in context: ModelContext) -> SignedOutOwnerData {
        let optionalOwnerTokenIdentifier: String? = ownerTokenIdentifier
        let completedWorkoutCount = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.syncOwnerTokenIdentifier == optionalOwnerTokenIdentifier
                    && session.statusRaw == "completed"
                    && session.deletedAt == nil
            }
        ))) ?? 0
        return SignedOutOwnerData(
            ownerTokenIdentifier: ownerTokenIdentifier,
            completedWorkoutCount: completedWorkoutCount
        )
    }

    private static func hasRecords(ownedBy ownerTokenIdentifier: String, in context: ModelContext) -> Bool {
        let optionalOwnerTokenIdentifier: String? = ownerTokenIdentifier
        return containsAny(FetchDescriptor<SyncCursorState>(
            predicate: #Predicate { cursor in
                cursor.ownerTokenIdentifier == ownerTokenIdentifier
            }
        ), in: context)
            || containsAny(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.syncOwnerTokenIdentifier == optionalOwnerTokenIdentifier
                        && session.deletedAt == nil
                }
            ), in: context)
            || containsAny(FetchDescriptor<Exercise>(
                predicate: #Predicate { exercise in
                    exercise.syncOwnerTokenIdentifier == optionalOwnerTokenIdentifier
                        && exercise.deletedAt == nil
                }
            ), in: context)
            || containsAny(FetchDescriptor<UserSettings>(
                predicate: #Predicate { settings in
                    settings.syncOwnerTokenIdentifier == optionalOwnerTokenIdentifier
                        && settings.deletedAt == nil
                }
            ), in: context)
    }

    private static func containsAny<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>,
        in context: ModelContext
    ) -> Bool {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}

enum SignedOutReminderPresentation {
    /// The dismissible reminder only appears once the app has settled into
    /// local-only mode, never while a signed-in owner is still resolving.
    static func bannerData(
        currentOwnerState: CurrentOwnerCoordinator.State,
        signedOutOwnerData: SignedOutOwnerData?,
        isDismissed: Bool
    ) -> SignedOutOwnerData? {
        guard currentOwnerState == .localOnly, !isDismissed else { return nil }
        return signedOutOwnerData
    }
}

/// Persists the signed-out reminder until the next sign-in: which owner signed
/// out (the last-known owner is cleared on sign-out) and whether it was dismissed.
@MainActor
final class SignedOutReminderStore {
    static let standardKeyPrefix = "signedOutReminder"
    static let standard = SignedOutReminderStore()

    private let userDefaults: UserDefaults
    private let dismissedKey: String
    private let ownerKey: String

    init(userDefaults: UserDefaults = .standard, keyPrefix: String = standardKeyPrefix) {
        self.userDefaults = userDefaults
        dismissedKey = "\(keyPrefix).dismissed"
        ownerKey = "\(keyPrefix).ownerTokenIdentifier"
    }

    var isDismissed: Bool {
        get { userDefaults.bool(forKey: dismissedKey) }
        set {
            if newValue {
                userDefaults.set(true, forKey: dismissedKey)
            } else {
                userDefaults.removeObject(forKey: dismissedKey)
            }
        }
    }

    var ownerTokenIdentifier: String? {
        get { userDefaults.string(forKey: ownerKey) }
        set {
            guard let newValue, !newValue.isEmpty else {
                userDefaults.removeObject(forKey: ownerKey)
                return
            }
            userDefaults.set(newValue, forKey: ownerKey)
        }
    }

    func clear() {
        isDismissed = false
        ownerTokenIdentifier = nil
    }

    static func resetForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--uitest-reset-signed-out-reminder") else {
            return
        }

        SignedOutReminderStore(userDefaults: defaults).clear()
    }
}
