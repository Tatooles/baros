import Foundation

protocol SettingsExerciseSyncClient {
    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult
    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult
    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult
    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse
}
