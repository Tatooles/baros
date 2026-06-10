import Combine
import ConvexMobile
import Foundation

struct ConvexSyncClient: SyncClient, @unchecked Sendable {
    private let client: ConvexClientWithAuth<String>

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult {
        let args = ConvexSyncArgumentMapper.upsertUserSettingsArgs(record)
        return try await client.mutation(
            "sync:upsertUserSettings",
            with: args
        )
    }

    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult {
        let args = ConvexSyncArgumentMapper.upsertExerciseArgs(record)
        return try await client.mutation(
            "sync:upsertExercise",
            with: args
        )
    }

    func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult {
        try await client.mutation(
            "sync:upsertWorkoutSession",
            with: ConvexSyncArgumentMapper.upsertWorkoutSessionArgs(record)
        )
    }

    func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult {
        try await client.mutation(
            "sync:upsertLoggedExercise",
            with: ConvexSyncArgumentMapper.upsertLoggedExerciseArgs(record)
        )
    }

    func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult {
        try await client.mutation(
            "sync:upsertLoggedSet",
            with: ConvexSyncArgumentMapper.upsertLoggedSetArgs(record)
        )
    }

    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult {
        return try await client.mutation(
            "sync:tombstone",
            with: [
                "entityKind": entityKind.rawValue,
                "clientId": clientId.uuidString.lowercased(),
                "deletedAt": deletedAt.timeIntervalSince1970,
            ]
        )
    }

    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse {
        let publisher = client.subscribe(
            to: "sync:fetchChanges",
            with: ConvexSyncArgumentMapper.fetchChangesArgs(cursors: cursors, limit: limit),
            yielding: SyncFetchChangesResponse.self
        )

        for try await response in publisher.values {
            return response
        }

        throw ConvexSyncClientError.noFetchChangesValue
    }
}

enum ConvexSyncArgumentMapper {
    static func upsertUserSettingsArgs(_ record: UserSettingsSyncPayload) -> [String: ConvexEncodable?] {
        ["record": userSettingsRecord(record)]
    }

    static func upsertExerciseArgs(_ record: ExerciseSyncPayload) -> [String: ConvexEncodable?] {
        ["record": exerciseRecord(record)]
    }

    static func upsertWorkoutSessionArgs(_ record: WorkoutSessionSyncPayload) -> [String: ConvexEncodable?] {
        ["record": workoutSessionRecord(record)]
    }

    static func upsertLoggedExerciseArgs(_ record: LoggedExerciseSyncPayload) -> [String: ConvexEncodable?] {
        ["record": loggedExerciseRecord(record)]
    }

    static func upsertLoggedSetArgs(_ record: LoggedSetSyncPayload) -> [String: ConvexEncodable?] {
        ["record": loggedSetRecord(record)]
    }

    static func fetchChangesArgs(cursors: SyncChangeCursors, limit: Int) -> [String: ConvexEncodable?] {
        ["cursors": cursorRecord(cursors), "limit": Double(limit)]
    }

    static func userSettingsRecord(_ record: UserSettingsSyncPayload) -> [String: ConvexEncodable?] {
        [
            "clientId": record.clientId,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "deletedAt": record.deletedAt,
            "weightUnitRaw": record.weightUnitRaw,
            "defaultRestTimerSeconds": Double(record.defaultRestTimerSeconds),
            "hasCompletedOnboarding": record.hasCompletedOnboarding,
        ]
    }

    static func exerciseRecord(_ record: ExerciseSyncPayload) -> [String: ConvexEncodable?] {
        [
            "clientId": record.clientId,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "deletedAt": record.deletedAt,
            "seedIdentifier": record.seedIdentifier,
            "name": record.name,
            "categoryRaw": record.categoryRaw,
            "equipmentRaw": record.equipmentRaw,
            "primaryMuscleRaw": record.primaryMuscleRaw,
            "primaryMuscleGroupRaw": record.primaryMuscleGroupRaw,
            "notes": record.notes,
            "isArchived": record.isArchived,
            "isSeeded": record.isSeeded,
        ]
    }

    static func workoutSessionRecord(_ record: WorkoutSessionSyncPayload) -> [String: ConvexEncodable?] {
        [
            "clientId": record.clientId,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "deletedAt": record.deletedAt,
            "title": record.title,
            "startedAt": record.startedAt,
            "endedAt": record.endedAt,
            "durationSeconds": Double(record.durationSeconds),
            "notes": record.notes,
            "referenceNotes": record.referenceNotes,
            "statusRaw": record.statusRaw,
            "sourceRaw": record.sourceRaw,
            "sourceSessionID": record.sourceSessionID,
            "healthLinkID": record.healthLinkID,
        ]
    }

    static func loggedExerciseRecord(_ record: LoggedExerciseSyncPayload) -> [String: ConvexEncodable?] {
        [
            "clientId": record.clientId,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "deletedAt": record.deletedAt,
            "sessionClientId": record.sessionClientId,
            "exerciseClientId": record.exerciseClientId,
            "orderIndex": Double(record.orderIndex),
            "exerciseSnapshotName": record.exerciseSnapshotName,
            "exerciseSnapshotEquipmentRaw": record.exerciseSnapshotEquipmentRaw,
            "exerciseSnapshotPrimaryMuscleGroupRaw": record.exerciseSnapshotPrimaryMuscleGroupRaw,
            "hasSnapshotMetadata": record.hasSnapshotMetadata,
            "notes": record.notes,
            "referenceNotes": record.referenceNotes,
        ]
    }

    static func loggedSetRecord(_ record: LoggedSetSyncPayload) -> [String: ConvexEncodable?] {
        [
            "clientId": record.clientId,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "deletedAt": record.deletedAt,
            "loggedExerciseClientId": record.loggedExerciseClientId,
            "orderIndex": Double(record.orderIndex),
            "weight": record.weight,
            "reps": record.reps.map(Double.init),
            "rpe": record.rpe,
            "placeholderWeight": record.placeholderWeight,
            "placeholderReps": record.placeholderReps.map(Double.init),
            "placeholderRPE": record.placeholderRPE,
            "kindRaw": record.kindRaw,
            "isCompleted": record.isCompleted,
            "completedAt": record.completedAt,
            "notes": record.notes,
            "healthLinkID": record.healthLinkID,
        ]
    }

    static func cursorRecord(_ cursors: SyncChangeCursors) -> [String: ConvexEncodable?] {
        [
            "userSettings": cursors.userSettings,
            "exercises": cursors.exercises,
            "workoutSessions": cursors.workoutSessions,
            "loggedExercises": cursors.loggedExercises,
            "loggedSets": cursors.loggedSets,
        ]
    }
}

enum ConvexSyncClientError: LocalizedError {
    case noFetchChangesValue

    var errorDescription: String? {
        switch self {
        case .noFetchChangesValue:
            "Convex fetchChanges subscription completed without a value."
        }
    }
}
