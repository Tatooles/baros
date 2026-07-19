import SwiftData

enum BarosSchema {
    static let models: [any PersistentModel.Type] = [
        Exercise.self,
        WorkoutTemplate.self,
        WorkoutSession.self,
        LoggedExercise.self,
        LoggedSet.self,
        UserSettings.self,
        HealthDataLink.self,
        SeedMetadata.self,
        SyncOutboxEntry.self,
        SyncCursorState.self
    ]
}
