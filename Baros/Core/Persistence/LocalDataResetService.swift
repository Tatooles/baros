import Foundation
import SwiftData

@MainActor
struct LocalDataResetService {
    func reset(context: ModelContext) throws {
        // Keep destructive changes out of the shared context until the store
        // accepts them. A failed reset must leave its pending edits untouched.
        let resetContext = ModelContext(context.container)
        resetContext.autosaveEnabled = false
        do {
            try deleteAll(SyncOutboxEntry.self, context: resetContext)
            try deleteAll(SyncCursorState.self, context: resetContext)
            try deleteAll(HealthDataLink.self, context: resetContext)
            try deleteAll(LoggedSet.self, context: resetContext)
            try deleteAll(LoggedExercise.self, context: resetContext)
            try deleteAll(WorkoutSession.self, context: resetContext)
            try deleteAll(WorkoutTemplate.self, context: resetContext)
            try deleteAll(Exercise.self, context: resetContext)
            try deleteAll(UserSettings.self, context: resetContext)
            try deleteAll(SeedMetadata.self, context: resetContext)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitest-in-memory-store"),
               ProcessInfo.processInfo.arguments.contains("--uitest-fail-local-reset-once"),
               !Self.didInjectResetFailure {
                Self.didInjectResetFailure = true
                throw CocoaError(.fileWriteNoPermission)
            }
            #endif
            try SeedDataService.seedIfNeeded(context: resetContext)
        } catch {
            resetContext.rollback()
            throw error
        }
        // A successful reset intentionally clears all local data, including
        // changes that had not yet been saved by the shared context.
        context.rollback()
        context.undoManager?.removeAllActions()
    }

    #if DEBUG
    private static var didInjectResetFailure = false
    #endif

    private func deleteAll<T: PersistentModel>(_ modelType: T.Type, context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<T>()) {
            context.delete(model)
        }
    }
}
