import Foundation
import SwiftData

enum SyncOutboxClaimEligibility {
    static func canClaim(
        entry: SyncOutboxEntry,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> Bool {
        let entityID = entry.entityID
        switch entry.entityKind {
        case .userSettings:
            guard let settings = try context.fetch(FetchDescriptor<UserSettings>(
                predicate: #Predicate { $0.id == entityID }
            )).first else {
                return false
            }
            return settings.syncOwnerTokenIdentifier == nil
                || settings.syncOwnerTokenIdentifier == ownerTokenIdentifier
        case .exercise:
            guard let exercise = try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.id == entityID }
            )).first else {
                return false
            }
            return exercise.syncOwnerTokenIdentifier == nil
                || exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier
        case .workoutSession:
            guard let session = try context.fetch(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.id == entityID }
            )).first else {
                return false
            }
            return canClaim(
                entry: entry,
                session: session,
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        case .loggedExercise:
            guard let session = try context.fetch(FetchDescriptor<LoggedExercise>(
                predicate: #Predicate { $0.id == entityID }
            )).first?.session else {
                return false
            }
            return canClaim(
                entry: entry,
                session: session,
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        case .loggedSet:
            guard let session = try context.fetch(FetchDescriptor<LoggedSet>(
                predicate: #Predicate { $0.id == entityID }
            )).first?.loggedExercise?.session else {
                return false
            }
            return canClaim(
                entry: entry,
                session: session,
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        default:
            return false
        }
    }

    private static func canClaim(
        entry: SyncOutboxEntry,
        session: WorkoutSession,
        ownerTokenIdentifier: String
    ) -> Bool {
        if session.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            return true
        }
        return session.syncOwnerTokenIdentifier == nil && entry.isActive
    }
}
