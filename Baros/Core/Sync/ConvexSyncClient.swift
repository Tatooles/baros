import BarosCore
import ConvexMobile
import Foundation

struct ConvexSyncClient: SyncClient, @unchecked Sendable {
    private let client: ConvexClientWithAuth<String>

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult {
        let args = ConvexSyncArgumentMapper.upsertUserSettingsArgs(record)
        return try await syncMutation(
            "sync:upsertUserSettings",
            with: args
        )
    }

    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult {
        let args = ConvexSyncArgumentMapper.upsertExerciseArgs(record)
        return try await syncMutation(
            "sync:upsertExercise",
            with: args
        )
    }

    func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult {
        return try await syncMutation(
            "sync:upsertWorkoutSession",
            with: ConvexSyncArgumentMapper.upsertWorkoutSessionArgs(record)
        )
    }

    func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult {
        return try await syncMutation(
            "sync:upsertLoggedExercise",
            with: ConvexSyncArgumentMapper.upsertLoggedExerciseArgs(record)
        )
    }

    func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult {
        return try await syncMutation(
            "sync:upsertLoggedSet",
            with: ConvexSyncArgumentMapper.upsertLoggedSetArgs(record)
        )
    }

    func upsertWorkoutTemplate(_ record: WorkoutTemplateSyncPayload) async throws -> SyncMutationResult {
        return try await syncMutation(
            "sync:upsertWorkoutTemplate",
            with: ConvexSyncArgumentMapper.upsertWorkoutTemplateArgs(record)
        )
    }

    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult {
        return try await syncMutation(
            "sync:tombstone",
            with: [
                "entityKind": entityKind.rawValue,
                "clientId": clientId.uuidString.lowercased(),
                "deletedAt": deletedAt.timeIntervalSince1970,
            ]
        )
    }

    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse {
        return try await syncMutation(
            "sync:fetchChangesOnce",
            with: ConvexSyncArgumentMapper.fetchChangesArgs(cursors: cursors, limit: limit)
        )
    }

    /// Runs a sync mutation, turning every server-side error into a
    /// `SyncServerRejection` with its `ConvexError` code, if any, so the
    /// coordinator can tell a record the server refuses from a failure that
    /// may pass.
    private func syncMutation<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?]
    ) async throws -> T {
        do {
            return try await client.mutation(name, with: args)
        } catch let error as ClientError {
            switch error {
            case let .ConvexError(data):
                throw SyncServerRejection.fromConvexErrorData(data)
            case let .ServerError(message):
                throw SyncServerRejection(code: nil, message: message)
            case .InternalError:
                throw error
            }
        }
    }

    func deleteAccountData(cancellationToken: UUID) async throws -> AccountDataDeletionResult {
        try await client.action(
            "sync:deleteAccountData",
            with: ["cancellationToken": cancellationToken.uuidString.lowercased()]
        )
    }

    func cancelAccountDeletion(cancellationToken: UUID) async throws -> AccountDeletionCancellationResult {
        try await client.action(
            "sync:cancelAccountDeletion",
            with: ["cancellationToken": cancellationToken.uuidString.lowercased()]
        )
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

    static func upsertWorkoutTemplateArgs(_ record: WorkoutTemplateSyncPayload) -> [String: ConvexEncodable?] {
        ["record": workoutTemplateRecord(record)]
    }

    static func fetchChangesArgs(cursors: SyncChangeCursors, limit: Int) -> [String: ConvexEncodable?] {
        ["cursors": cursorRecord(cursors), "limit": Double(limit)]
    }

    static func userSettingsRecord(_ record: UserSettingsSyncPayload) -> [String: ConvexEncodable?] {
        var args: [String: ConvexEncodable?] = [
            "clientId": record.clientId,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "deletedAt": record.deletedAt,
            "weightUnitRaw": record.weightUnitRaw,
            "defaultRestTimerSeconds": Double(record.defaultRestTimerSeconds),
            "hasCompletedOnboarding": record.hasCompletedOnboarding,
        ]
        // Always sent, null for a record never synced (convex/sync/validators.ts).
        args.updateValue(record.baseUpdatedAt, forKey: "baseUpdatedAt")
        return args
    }

    static func exerciseRecord(_ record: ExerciseSyncPayload) -> [String: ConvexEncodable?] {
        var args: [String: ConvexEncodable?] = [
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
        if let trackingMethodRaw = record.trackingMethodRaw {
            args["trackingMethodRaw"] = trackingMethodRaw
        }
        // Always sent, null for a record never synced (convex/sync/validators.ts).
        args.updateValue(record.baseUpdatedAt, forKey: "baseUpdatedAt")
        return args
    }

    static func workoutSessionRecord(_ record: WorkoutSessionSyncPayload) -> [String: ConvexEncodable?] {
        var args: [String: ConvexEncodable?] = [
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
            "sourceTemplateID": record.sourceTemplateID,
        ]
        // Always sent, null for a record never synced (convex/sync/validators.ts).
        args.updateValue(record.baseUpdatedAt, forKey: "baseUpdatedAt")
        return args
    }

    static func loggedExerciseRecord(_ record: LoggedExerciseSyncPayload) -> [String: ConvexEncodable?] {
        var args: [String: ConvexEncodable?] = [
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
            "sourceLoggedExerciseID": record.sourceLoggedExerciseID,
        ]
        if record.sendsSupersetGroupID {
            // updateValue keeps a nil, which encodes as null.
            args.updateValue(record.supersetGroupID, forKey: "supersetGroupID")
        }
        if let trackingMethodRaw = record.trackingMethodRaw {
            args["trackingMethodRaw"] = trackingMethodRaw
        }
        // Always sent, null for a record never synced (convex/sync/validators.ts).
        args.updateValue(record.baseUpdatedAt, forKey: "baseUpdatedAt")
        return args
    }

    static func workoutTemplateRecord(_ record: WorkoutTemplateSyncPayload) -> [String: ConvexEncodable?] {
        let entries: [ConvexEncodable?] = record.entries.map { entry in
            [
                "id": entry.id,
                "exerciseClientId": entry.exerciseClientId,
                "exerciseSnapshotName": entry.exerciseSnapshotName,
                "exerciseSnapshotEquipmentRaw": entry.exerciseSnapshotEquipmentRaw,
                "exerciseSnapshotPrimaryMuscleGroupRaw": entry.exerciseSnapshotPrimaryMuscleGroupRaw,
                "supersetGroupID": entry.supersetGroupID,
            ] as [String: ConvexEncodable?]
        }
        var args: [String: ConvexEncodable?] = [
            "clientId": record.clientId,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "deletedAt": record.deletedAt,
            "name": record.name,
            "entries": entries,
        ]
        // Always sent, null for a record never synced (convex/sync/validators.ts).
        args.updateValue(record.baseUpdatedAt, forKey: "baseUpdatedAt")
        return args
    }

    static func loggedSetRecord(_ record: LoggedSetSyncPayload) -> [String: ConvexEncodable?] {
        var args: [String: ConvexEncodable?] = [
            "clientId": record.clientId,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "deletedAt": record.deletedAt,
            "loggedExerciseClientId": record.loggedExerciseClientId,
            "orderIndex": Double(record.orderIndex),
            "weight": record.weight,
            "reps": record.reps.map(Double.init),
            "rpe": record.rpe,
            "kindRaw": record.kindRaw,
            "isCompleted": record.isCompleted,
            "completedAt": record.completedAt,
            "notes": record.notes,
            "healthLinkID": record.healthLinkID,
            "sourceLoggedSetID": record.sourceLoggedSetID,
        ]
        if record.sendsDurationSeconds {
            // updateValue keeps a nil, which encodes as null.
            args.updateValue(record.durationSeconds.map(Double.init), forKey: "durationSeconds")
        }
        // Always sent, null for a record never synced (convex/sync/validators.ts).
        args.updateValue(record.baseUpdatedAt, forKey: "baseUpdatedAt")
        return args
    }

    static func cursorRecord(_ cursors: SyncChangeCursors) -> [String: ConvexEncodable?] {
        var record: [String: ConvexEncodable?] = [
            "userSettings": cursors.userSettings,
            "exercises": cursors.exercises,
            "workoutSessions": cursors.workoutSessions,
            "loggedExercises": cursors.loggedExercises,
            "loggedSets": cursors.loggedSets,
        ]
        if let workoutTemplates = cursors.workoutTemplates {
            record["workoutTemplates"] = workoutTemplates
        }
        return record
    }
}
