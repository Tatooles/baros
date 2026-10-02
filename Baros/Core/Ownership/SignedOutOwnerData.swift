import Foundation
import SwiftData

/// Local data that still belongs to an owner while the app is local-only. Its
/// presence means someone has signed in on this iPhone before, so Baros offers
/// to sign back in instead of treating them as a new user. Deliberate sign-out
/// and an expired session look the same here, so the copy stays neutral.
struct SignedOutOwnerData: Equatable {
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

    static func find(in context: ModelContext) -> SignedOutOwnerData? {
        let completedWorkoutCount = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.syncOwnerTokenIdentifier != nil
                    && session.statusRaw == "completed"
                    && session.deletedAt == nil
            }
        ))) ?? 0
        guard completedWorkoutCount > 0 || containsOwnerScopedRecords(in: context) else {
            return nil
        }
        return SignedOutOwnerData(completedWorkoutCount: completedWorkoutCount)
    }

    private static func containsOwnerScopedRecords(in context: ModelContext) -> Bool {
        containsAny(FetchDescriptor<SyncCursorState>(), in: context)
            || containsAny(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.syncOwnerTokenIdentifier != nil && session.deletedAt == nil
                }
            ), in: context)
            || containsAny(FetchDescriptor<Exercise>(
                predicate: #Predicate { exercise in
                    exercise.syncOwnerTokenIdentifier != nil && exercise.deletedAt == nil
                }
            ), in: context)
            || containsAny(FetchDescriptor<UserSettings>(
                predicate: #Predicate { settings in
                    settings.syncOwnerTokenIdentifier != nil && settings.deletedAt == nil
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

/// Remembers that the signed-out reminder was dismissed until the next sign-in.
@MainActor
final class SignedOutReminderDismissalStore {
    static let standardKey = "signedOutReminderDismissed"
    static let standard = SignedOutReminderDismissalStore()

    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = standardKey) {
        self.userDefaults = userDefaults
        self.key = key
    }

    var isDismissed: Bool {
        get { userDefaults.bool(forKey: key) }
        set {
            if newValue {
                userDefaults.set(true, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }
    }

    static func resetForUITestingIfRequested(
        arguments: [String],
        defaults: UserDefaults = .standard,
        key: String = standardKey
    ) {
        guard arguments.contains("--uitest-reset-signed-out-reminder") else {
            return
        }

        defaults.removeObject(forKey: key)
    }
}
