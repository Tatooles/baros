import Foundation

public struct UserSettingsSyncPayload: Codable, Equatable, Sendable {
    public let clientId: String
    public let createdAt: Double
    public let updatedAt: Double
    public let deletedAt: Double?
    public let weightUnitRaw: String
    public let defaultRestTimerSeconds: Int
    public let hasCompletedOnboarding: Bool
    /// The server version this edit started from (`syncBaseUpdatedAt`), or
    /// nil for a record never synced. Always sent, as null when nil.
    public var baseUpdatedAt: Double? = nil
}

public struct ExerciseSyncPayload: Codable, Equatable, Sendable {
    public let clientId: String
    public let createdAt: Double
    public let updatedAt: Double
    public let deletedAt: Double?
    public let seedIdentifier: String?
    public let name: String
    public let categoryRaw: String
    public let equipmentRaw: String
    public let primaryMuscleRaw: String
    public let primaryMuscleGroupRaw: String
    public let notes: String
    public let isArchived: Bool
    public let isSeeded: Bool
    /// Left out of the upload when nil, so the server keeps its value.
    public var trackingMethodRaw: String? = nil
    /// The server version this edit started from (`syncBaseUpdatedAt`), or
    /// nil for a record never synced. Always sent, as null when nil.
    public var baseUpdatedAt: Double? = nil
}

public struct WorkoutSessionSyncPayload: Codable, Equatable, Sendable {
    public let clientId: String
    public let createdAt: Double
    public let updatedAt: Double
    public let deletedAt: Double?
    public let title: String
    public let startedAt: Double
    public let endedAt: Double?
    public let durationSeconds: Int
    public let notes: String
    public let referenceNotes: String?
    public let statusRaw: String
    public let sourceRaw: String
    public let sourceSessionID: String?
    public let healthLinkID: String?
    public var sourceTemplateID: String? = nil
    /// The server version this edit started from (`syncBaseUpdatedAt`), or
    /// nil for a record never synced. Always sent, as null when nil.
    public var baseUpdatedAt: Double? = nil
}

public struct LoggedExerciseSyncPayload: Codable, Equatable, Sendable {
    public let clientId: String
    public let createdAt: Double
    public let updatedAt: Double
    public let deletedAt: Double?
    public let sessionClientId: String
    public let exerciseClientId: String?
    public let orderIndex: Int
    public let exerciseSnapshotName: String
    public let exerciseSnapshotEquipmentRaw: String
    public let exerciseSnapshotPrimaryMuscleGroupRaw: String
    public let hasSnapshotMetadata: Bool
    public let notes: String
    public let referenceNotes: String?
    public let sourceLoggedExerciseID: String?
    public var supersetGroupID: String? = nil
    /// Omitted uploads keep the server's grouping, as for older builds. Null is
    /// sent only for a removal made on this device.
    public var sendsSupersetGroupID = false
    /// Left out of the upload when nil, so the server keeps its value.
    public var trackingMethodRaw: String? = nil
    /// The server version this edit started from (`syncBaseUpdatedAt`), or
    /// nil for a record never synced. Always sent, as null when nil.
    public var baseUpdatedAt: Double? = nil
}

public struct LoggedSetSyncPayload: Codable, Equatable, Sendable {
    public let clientId: String
    public let createdAt: Double
    public let updatedAt: Double
    public let deletedAt: Double?
    public let loggedExerciseClientId: String
    public let orderIndex: Int
    public let weight: Double?
    public let reps: Int?
    public let rpe: Double?
    public let kindRaw: String
    public let isCompleted: Bool
    public let completedAt: Double?
    public let notes: String
    public let healthLinkID: String?
    public let sourceLoggedSetID: String?
    public var durationSeconds: Int? = nil
    /// Omitted uploads keep the server's time, as for older builds. Null is
    /// sent only when this device knows the exercise's tracking method.
    public var sendsDurationSeconds = false
    /// The server version this edit started from (`syncBaseUpdatedAt`), or
    /// nil for a record never synced. Always sent, as null when nil.
    public var baseUpdatedAt: Double? = nil
}

public struct WorkoutTemplateEntrySyncPayload: Codable, Equatable, Sendable {
    public let id: String
    public let exerciseClientId: String?
    public let exerciseSnapshotName: String
    public let exerciseSnapshotEquipmentRaw: String
    public let exerciseSnapshotPrimaryMuscleGroupRaw: String
    public let supersetGroupID: String?
}

public struct WorkoutTemplateSyncPayload: Codable, Equatable, Sendable {
    public let clientId: String
    public let createdAt: Double
    public let updatedAt: Double
    public let deletedAt: Double?
    public let name: String
    public let entries: [WorkoutTemplateEntrySyncPayload]
    /// The server version this edit started from (`syncBaseUpdatedAt`), or
    /// nil for a record never synced. Always sent, as null when nil.
    public var baseUpdatedAt: Double? = nil
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
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            baseUpdatedAt: settings.syncBaseUpdatedAt
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
            isSeeded: exercise.isSeeded,
            trackingMethodRaw: exercise.trackingMethodRaw,
            baseUpdatedAt: exercise.syncBaseUpdatedAt
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
            healthLinkID: session.healthLinkID?.uuidString.lowercased(),
            sourceTemplateID: session.sourceTemplateID?.uuidString.lowercased(),
            baseUpdatedAt: session.syncBaseUpdatedAt
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
            referenceNotes: loggedExercise.referenceNotes,
            sourceLoggedExerciseID: loggedExercise.sourceLoggedExerciseID?.uuidString.lowercased(),
            supersetGroupID: loggedExercise.supersetGroupID?.uuidString.lowercased(),
            sendsSupersetGroupID: loggedExercise.supersetGroupID != nil || loggedExercise.hasLocalSupersetChange,
            trackingMethodRaw: loggedExercise.trackingMethodRaw,
            baseUpdatedAt: loggedExercise.syncBaseUpdatedAt
        )
    }

    static func workoutTemplatePayload(from template: WorkoutTemplate) -> WorkoutTemplateSyncPayload {
        WorkoutTemplateSyncPayload(
            clientId: template.id.uuidString.lowercased(),
            createdAt: template.createdAt.timeIntervalSince1970,
            updatedAt: template.updatedAt.timeIntervalSince1970,
            deletedAt: template.deletedAt?.timeIntervalSince1970,
            name: template.name,
            entries: template.entries.map { entry in
                WorkoutTemplateEntrySyncPayload(
                    id: entry.id.uuidString.lowercased(),
                    exerciseClientId: entry.exerciseID?.uuidString.lowercased(),
                    exerciseSnapshotName: entry.exerciseSnapshotName,
                    exerciseSnapshotEquipmentRaw: entry.exerciseSnapshotEquipmentRaw,
                    exerciseSnapshotPrimaryMuscleGroupRaw: entry.exerciseSnapshotPrimaryMuscleGroupRaw,
                    supersetGroupID: entry.supersetGroupID?.uuidString.lowercased()
                )
            },
            baseUpdatedAt: template.syncBaseUpdatedAt
        )
    }

    static func loggedSetPayload(from set: LoggedSet) -> LoggedSetSyncPayload {
        let duration = WorkoutNumericInputPolicy.validatedDuration(set.durationSeconds)
        return LoggedSetSyncPayload(
            clientId: set.id.uuidString.lowercased(),
            createdAt: set.createdAt.timeIntervalSince1970,
            updatedAt: set.updatedAt.timeIntervalSince1970,
            deletedAt: set.deletedAt?.timeIntervalSince1970,
            loggedExerciseClientId: set.loggedExercise?.id.uuidString.lowercased() ?? "",
            orderIndex: set.orderIndex,
            weight: WorkoutNumericInputPolicy.validatedWeight(set.weight),
            reps: WorkoutNumericInputPolicy.validatedReps(set.reps),
            rpe: WorkoutNumericInputPolicy.validatedRPE(set.rpe),
            kindRaw: set.kindRaw,
            isCompleted: set.isCompleted,
            completedAt: set.completedAt?.timeIntervalSince1970,
            notes: set.notes,
            healthLinkID: set.healthLinkID?.uuidString.lowercased(),
            sourceLoggedSetID: set.sourceLoggedSetID?.uuidString.lowercased(),
            durationSeconds: duration,
            sendsDurationSeconds: duration != nil
                || (set.knowsDuration == true && set.loggedExercise?.trackingMethodRaw != nil),
            baseUpdatedAt: set.syncBaseUpdatedAt
        )
    }
}

public struct SyncChangeCursors: Codable, Equatable {
    public var userSettings: Double
    public var exercises: Double
    public var workoutSessions: Double = 0
    public var loggedExercises: Double = 0
    public var loggedSets: Double = 0
    /// Sent only by builds with templates; older servers reject it.
    public var workoutTemplates: Double? = nil
}

struct SyncHasMore: Codable, Equatable {
    var userSettings: Bool
    var exercises: Bool
    var workoutSessions: Bool = false
    var loggedExercises: Bool = false
    var loggedSets: Bool = false
    var workoutTemplates: Bool? = nil
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
    var trackingMethodRaw: String? = nil
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
    var sourceTemplateID: String? = nil
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
    let sourceLoggedExerciseID: String?
    var supersetGroupID: String? = nil
    var trackingMethodRaw: String? = nil
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
    let kindRaw: String
    let isCompleted: Bool
    let completedAt: Double?
    let notes: String
    let healthLinkID: String?
    let sourceLoggedSetID: String?
    var durationSeconds: Int? = nil
}

struct WorkoutTemplateSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let name: String
    let entries: [WorkoutTemplateEntrySyncPayload]
}

public struct SyncFetchChangesResponse: Codable, Equatable {
    let userSettings: [UserSettingsSyncRecord]
    let exercises: [ExerciseSyncRecord]
    let workoutSessions: [WorkoutSessionSyncRecord]
    let loggedExercises: [LoggedExerciseSyncRecord]
    let loggedSets: [LoggedSetSyncRecord]
    /// Present only when the request sent a template cursor.
    var workoutTemplates: [WorkoutTemplateSyncRecord]? = nil
    let cursors: SyncChangeCursors
    let hasMore: SyncHasMore
}

public struct SyncMutationResult: Codable, Equatable {
    let status: String
    let serverUpdatedAt: Double?
    /// The stored version after an upsert, the base of the next edit. Absent
    /// from tombstone results and from servers older than `baseUpdatedAt`.
    var updatedAt: Double? = nil
}

public struct AccountDataDeletionCounts: Codable, Equatable {
    let loggedSets: Int
    let loggedExercises: Int
    let workoutSessions: Int
    let exercises: Int
    let userSettings: Int

    public init(loggedSets: Int, loggedExercises: Int, workoutSessions: Int, exercises: Int, userSettings: Int) {
        self.loggedSets = loggedSets
        self.loggedExercises = loggedExercises
        self.workoutSessions = workoutSessions
        self.exercises = exercises
        self.userSettings = userSettings
    }
}

public struct AccountDataDeletionResult: Codable, Equatable {
    let status: String
    let deletedCounts: AccountDataDeletionCounts

    public init(status: String, deletedCounts: AccountDataDeletionCounts) {
        self.status = status
        self.deletedCounts = deletedCounts
    }
}

public struct AccountDeletionCancellationResult: Codable, Equatable {
    let status: String
}
