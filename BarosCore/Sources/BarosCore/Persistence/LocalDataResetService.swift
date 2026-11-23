import Foundation
import SwiftData

/// Told around a local-data reset, so device-local state that mirrors the store (the Apple Health
/// ledger, ADR 0005) is cleared before rows go. Both calls must return without throwing or waiting.
@MainActor
public protocol LocalDataResetObserving: AnyObject {
    func localDataResetWillBegin()
    /// Called after the reset succeeds or rolls back.
    func localDataResetDidEnd()
}

@MainActor
public struct LocalDataResetService {
    private weak var observer: (any LocalDataResetObserving)?

    public init(observer: (any LocalDataResetObserving)? = nil) {
        self.observer = observer
    }

    func reset(context: ModelContext) throws {
        observer?.localDataResetWillBegin()
        defer { observer?.localDataResetDidEnd() }
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
