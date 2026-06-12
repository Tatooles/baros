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

struct WorkoutSessionSyncPayload: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let title: String
    let startedAt: Double
    let endedAt: Double?
    let durationSeconds: Int
    let notes: String
    let referenceNotes: String?
    let statusRaw: String
    let sourceRaw: String
    let sourceSessionID: String?
    let healthLinkID: String?
}

struct LoggedExerciseSyncPayload: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let sessionClientId: String
    let exerciseClientId: String?
    let orderIndex: Int
    let exerciseSnapshotName: String
    let exerciseSnapshotEquipmentRaw: String
    let exerciseSnapshotPrimaryMuscleGroupRaw: String
    let hasSnapshotMetadata: Bool
    let notes: String
    let referenceNotes: String?
}

struct LoggedSetSyncPayload: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let loggedExerciseClientId: String
    let orderIndex: Int
    let weight: Double?
    let reps: Int?
    let rpe: Double?
    let placeholderWeight: Double?
    let placeholderReps: Int?
    let placeholderRPE: Double?
    let kindRaw: String
    let isCompleted: Bool
    let completedAt: Double?
    let notes: String
    let healthLinkID: String?
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

    static func workoutSessionPayload(from session: WorkoutSession) -> WorkoutSessionSyncPayload {
        WorkoutSessionSyncPayload(
            clientId: session.id.uuidString.lowercased(),
            createdAt: session.createdAt.timeIntervalSince1970,
            updatedAt: session.updatedAt.timeIntervalSince1970,
            deletedAt: session.deletedAt?.timeIntervalSince1970,
            title: session.title,
            startedAt: session.startedAt.timeIntervalSince1970,
            endedAt: session.endedAt?.timeIntervalSince1970,
            durationSeconds: session.durationSeconds,
            notes: session.notes,
            referenceNotes: session.referenceNotes,
            statusRaw: session.statusRaw,
            sourceRaw: session.sourceRaw,
            sourceSessionID: session.sourceSessionID?.uuidString.lowercased(),
            healthLinkID: session.healthLinkID?.uuidString.lowercased()
        )
    }

    static func loggedExercisePayload(from loggedExercise: LoggedExercise) -> LoggedExerciseSyncPayload {
        LoggedExerciseSyncPayload(
            clientId: loggedExercise.id.uuidString.lowercased(),
            createdAt: loggedExercise.createdAt.timeIntervalSince1970,
            updatedAt: loggedExercise.updatedAt.timeIntervalSince1970,
            deletedAt: loggedExercise.deletedAt?.timeIntervalSince1970,
            sessionClientId: loggedExercise.session?.id.uuidString.lowercased() ?? "",
            exerciseClientId: loggedExercise.exercise?.id.uuidString.lowercased(),
            orderIndex: loggedExercise.orderIndex,
            exerciseSnapshotName: loggedExercise.exerciseSnapshotName,
            exerciseSnapshotEquipmentRaw: loggedExercise.effectiveSnapshotEquipmentRaw,
            exerciseSnapshotPrimaryMuscleGroupRaw: loggedExercise.effectiveSnapshotPrimaryMuscleGroupRaw,
            hasSnapshotMetadata: loggedExercise.hasSnapshotMetadata,
            notes: loggedExercise.notes,
            referenceNotes: loggedExercise.referenceNotes
        )
    }

    static func loggedSetPayload(from set: LoggedSet) -> LoggedSetSyncPayload {
        LoggedSetSyncPayload(
            clientId: set.id.uuidString.lowercased(),
            createdAt: set.createdAt.timeIntervalSince1970,
            updatedAt: set.updatedAt.timeIntervalSince1970,
            deletedAt: set.deletedAt?.timeIntervalSince1970,
            loggedExerciseClientId: set.loggedExercise?.id.uuidString.lowercased() ?? "",
            orderIndex: set.orderIndex,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
            placeholderWeight: set.placeholderWeight,
            placeholderReps: set.placeholderReps,
            placeholderRPE: set.placeholderRPE,
            kindRaw: set.kindRaw,
            isCompleted: set.isCompleted,
            completedAt: set.completedAt?.timeIntervalSince1970,
            notes: set.notes,
            healthLinkID: set.healthLinkID?.uuidString.lowercased()
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

struct WorkoutSessionSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let title: String
    let startedAt: Double
    let endedAt: Double?
    let durationSeconds: Int
    let notes: String
    let referenceNotes: String?
    let statusRaw: String
    let sourceRaw: String
    let sourceSessionID: String?
    let healthLinkID: String?
}

struct LoggedExerciseSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let sessionClientId: String
    let exerciseClientId: String?
    let orderIndex: Int
    let exerciseSnapshotName: String
    let exerciseSnapshotEquipmentRaw: String
    let exerciseSnapshotPrimaryMuscleGroupRaw: String
    let hasSnapshotMetadata: Bool
    let notes: String
    let referenceNotes: String?
}

struct LoggedSetSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let loggedExerciseClientId: String
    let orderIndex: Int
    let weight: Double?
    let reps: Int?
    let rpe: Double?
    let placeholderWeight: Double?
    let placeholderReps: Int?
    let placeholderRPE: Double?
    let kindRaw: String
    let isCompleted: Bool
    let completedAt: Double?
    let notes: String
    let healthLinkID: String?
}

struct SyncFetchChangesResponse: Codable, Equatable {
    let userSettings: [UserSettingsSyncRecord]
    let exercises: [ExerciseSyncRecord]
    let workoutSessions: [WorkoutSessionSyncRecord]
    let loggedExercises: [LoggedExerciseSyncRecord]
    let loggedSets: [LoggedSetSyncRecord]
    let cursors: SyncChangeCursors
    let hasMore: SyncHasMore
}

struct SyncMutationResult: Codable, Equatable {
    let status: String
    let serverUpdatedAt: Double?
}

struct AccountDataDeletionCounts: Codable, Equatable {
    let loggedSets: Int
    let loggedExercises: Int
    let workoutSessions: Int
    let exercises: Int
    let userSettings: Int
}

struct AccountDataDeletionResult: Codable, Equatable {
    let status: String
    let deletedCounts: AccountDataDeletionCounts
}

struct AccountDeletionCancellationResult: Codable, Equatable {
    let status: String
}
