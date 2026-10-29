import Foundation
import SwiftData

/// Durable recovery policy: only explicit discard terminalizes an inaccessible
/// workout. Merely observing authentication or relaunching never writes it.
@MainActor
enum WorkoutRecovery {
    static func activeSessions(in sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.filter { $0.status == .active && !$0.isDeleted }.sorted {
            if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.startedAt < $1.startedAt
        }
    }

    static func hiddenSessions(in sessions: [WorkoutSession], owner: String?) -> [WorkoutSession] {
        activeSessions(in: sessions).filter { !$0.allowsHistoryMutation(ownerTokenIdentifier: owner) }
    }

    static func discard(id: UUID?, expectedOwner: String?, currentOwner: String?,
                        engine: ActiveWorkoutEngine, context: ModelContext,
                        save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard expectedOwner == currentOwner,
              let session = activeSessions(in: try context.fetch(FetchDescriptor<WorkoutSession>()))
                .first(where: { $0.id == id }) else {
            throw RecoveryError.changed
        }
        try engine.discardWorkout(session, context: context, save: save)
    }

    private enum RecoveryError: LocalizedError {
        case changed
        var errorDescription: String? { "The account or workout changed. Review the current state and try again." }
    }
}
