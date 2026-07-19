import Foundation

protocol SyncClient {
    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult
    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult
    func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult
    func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult
    func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult
    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult
    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse
    func deleteAccountData(cancellationToken: UUID) async throws -> AccountDataDeletionResult
    func cancelAccountDeletion(cancellationToken: UUID) async throws -> AccountDeletionCancellationResult
}
