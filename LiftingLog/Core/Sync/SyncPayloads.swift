import Foundation

struct UserSettingsSyncPayload: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let weightUnitRaw: String
    let defaultRestTimerSeconds: Int
    let hasCompletedOnboarding: Bool
}

struct ExerciseSyncPayload: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let seedIdentifier: String?
    let name: String
    let categoryRaw: String
    let equipmentRaw: String
    let primaryMuscleRaw: String
    let primaryMuscleGroupRaw: String
    let notes: String
    let isArchived: Bool
    let isSeeded: Bool
}

enum SyncPayloadMapper {
    static func userSettingsPayload(from settings: UserSettings) -> UserSettingsSyncPayload {
        UserSettingsSyncPayload(
            clientId: settings.id.uuidString.lowercased(),
            createdAt: settings.createdAt.timeIntervalSince1970,
            updatedAt: settings.updatedAt.timeIntervalSince1970,
            deletedAt: settings.deletedAt?.timeIntervalSince1970,
            weightUnitRaw: settings.weightUnitRaw,
            defaultRestTimerSeconds: settings.defaultRestTimerSeconds,
            hasCompletedOnboarding: settings.hasCompletedOnboarding
        )
    }

    static func exercisePayload(from exercise: Exercise) -> ExerciseSyncPayload {
        ExerciseSyncPayload(
            clientId: exercise.id.uuidString.lowercased(),
            createdAt: exercise.createdAt.timeIntervalSince1970,
            updatedAt: exercise.updatedAt.timeIntervalSince1970,
            deletedAt: exercise.deletedAt?.timeIntervalSince1970,
            seedIdentifier: exercise.seedIdentifier,
            name: exercise.name,
            categoryRaw: exercise.categoryRaw,
            equipmentRaw: exercise.equipmentRaw,
            primaryMuscleRaw: exercise.primaryMuscleRaw,
            primaryMuscleGroupRaw: exercise.primaryMuscleGroupRaw,
            notes: exercise.notes,
            isArchived: exercise.isArchived,
            isSeeded: exercise.isSeeded
        )
    }
}

struct SyncChangeCursors: Codable, Equatable {
    var userSettings: Double
    var exercises: Double
    var workoutSessions: Double = 0
    var loggedExercises: Double = 0
    var loggedSets: Double = 0
}

struct SyncHasMore: Codable, Equatable {
    var userSettings: Bool
    var exercises: Bool
    var workoutSessions: Bool = false
    var loggedExercises: Bool = false
    var loggedSets: Bool = false
}

struct UserSettingsSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let weightUnitRaw: String
    let defaultRestTimerSeconds: Int
    let hasCompletedOnboarding: Bool
}

struct ExerciseSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let seedIdentifier: String?
    let name: String
    let categoryRaw: String
    let equipmentRaw: String
    let primaryMuscleRaw: String
    let primaryMuscleGroupRaw: String
    let notes: String
    let isArchived: Bool
    let isSeeded: Bool
}

struct SyncFetchChangesResponse: Codable, Equatable {
    let userSettings: [UserSettingsSyncRecord]
    let exercises: [ExerciseSyncRecord]
    let cursors: SyncChangeCursors
    let hasMore: SyncHasMore
}

struct SyncMutationResult: Codable, Equatable {
    let status: String
    let serverUpdatedAt: Double?
}
