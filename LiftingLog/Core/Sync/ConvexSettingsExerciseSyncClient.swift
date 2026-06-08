import Combine
import ConvexMobile
import Foundation

struct ConvexSettingsExerciseSyncClient: SettingsExerciseSyncClient, @unchecked Sendable {
    private let client: ConvexClientWithAuth<String>

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult {
        let args: [String: ConvexEncodable?] = ["record": record.convexDictionary()]
        return try await client.mutation(
            "sync:upsertUserSettings",
            with: args
        )
    }

    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult {
        let args: [String: ConvexEncodable?] = ["record": record.convexDictionary()]
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
            to: "sync:fetchChanges",
            with: ["cursors": cursors.convexDictionary(), "limit": limit],
            yielding: SyncFetchChangesResponse.self
        )

        for try await response in publisher.values {
            return response
        }

        throw ConvexSettingsExerciseSyncClientError.noFetchChangesValue
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

private extension UserSettingsSyncPayload {
    func convexDictionary() -> [String: ConvexEncodable?] {
        [
            "clientId": clientId,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "deletedAt": deletedAt,
            "weightUnitRaw": weightUnitRaw,
            "defaultRestTimerSeconds": defaultRestTimerSeconds,
            "hasCompletedOnboarding": hasCompletedOnboarding,
        ]
    }
}

private extension ExerciseSyncPayload {
    func convexDictionary() -> [String: ConvexEncodable?] {
        [
            "clientId": clientId,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "deletedAt": deletedAt,
            "seedIdentifier": seedIdentifier,
            "name": name,
            "categoryRaw": categoryRaw,
            "equipmentRaw": equipmentRaw,
            "primaryMuscleRaw": primaryMuscleRaw,
            "primaryMuscleGroupRaw": primaryMuscleGroupRaw,
            "notes": notes,
            "isArchived": isArchived,
            "isSeeded": isSeeded,
        ]
    }
}

private extension SyncChangeCursors {
    func convexDictionary() -> [String: ConvexEncodable?] {
        [
            "userSettings": userSettings,
            "exercises": exercises,
            "workoutSessions": workoutSessions,
            "loggedExercises": loggedExercises,
            "loggedSets": loggedSets,
        ]
    }
}
