import Combine
import ConvexMobile
import Foundation

struct ConvexSettingsExerciseSyncClient: SettingsExerciseSyncClient, @unchecked Sendable {
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
            to: "sync:fetchSettingsExerciseChanges",
            with: ConvexSyncArgumentMapper.fetchChangesArgs(cursors: cursors, limit: limit),
            yielding: SyncFetchChangesResponse.self
        )

        for try await response in publisher.values {
            return response
        }

        throw ConvexSettingsExerciseSyncClientError.noFetchChangesValue
    }
}

enum ConvexSyncArgumentMapper {
    static func upsertUserSettingsArgs(_ record: UserSettingsSyncPayload) -> [String: ConvexEncodable?] {
        ["record": userSettingsRecord(record)]
    }

    static func upsertExerciseArgs(_ record: ExerciseSyncPayload) -> [String: ConvexEncodable?] {
        ["record": exerciseRecord(record)]
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

enum ConvexSettingsExerciseSyncClientError: LocalizedError {
    case noFetchChangesValue

    var errorDescription: String? {
        switch self {
        case .noFetchChangesValue:
            "Convex fetchChanges subscription completed without a value."
        }
    }
}
