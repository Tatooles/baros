import SwiftData

enum OwnerlessWorkoutGraphBootstrapPolicy {
    static func canBootstrap(ownerTokenIdentifier: String, context: ModelContext) throws -> Bool {
        let cursorStates = try context.fetch(FetchDescriptor<SyncCursorState>())
        if cursorStates.contains(where: { $0.ownerTokenIdentifier != ownerTokenIdentifier }) {
            return false
        }

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        if settings.contains(where: { $0.syncOwnerTokenIdentifier != nil && $0.syncOwnerTokenIdentifier != ownerTokenIdentifier }) {
            return false
        }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        if exercises.contains(where: { $0.syncOwnerTokenIdentifier != nil && $0.syncOwnerTokenIdentifier != ownerTokenIdentifier }) {
            return false
        }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        if sessions.contains(where: { $0.syncOwnerTokenIdentifier != nil && $0.syncOwnerTokenIdentifier != ownerTokenIdentifier }) {
            return false
        }

        return true
    }
}
