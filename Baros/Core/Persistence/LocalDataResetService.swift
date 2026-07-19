import SwiftData

@MainActor
struct LocalDataResetService {
    func reset(context: ModelContext) throws {
        try deleteAll(SyncOutboxEntry.self, context: context)
        try deleteAll(SyncCursorState.self, context: context)
        try deleteAll(HealthDataLink.self, context: context)
        try deleteAll(LoggedSet.self, context: context)
        try deleteAll(LoggedExercise.self, context: context)
        try deleteAll(WorkoutSession.self, context: context)
        try deleteAll(WorkoutTemplate.self, context: context)
        try deleteAll(Exercise.self, context: context)
        try deleteAll(UserSettings.self, context: context)
        try deleteAll(SeedMetadata.self, context: context)

        try SeedDataService.seedIfNeeded(context: context)
    }

    private func deleteAll<T: PersistentModel>(_ modelType: T.Type, context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<T>()) {
            context.delete(model)
        }
    }
}
