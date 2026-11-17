import Foundation
@testable import BarosCore

// Copy of `FakeSyncClient` from BarosCore/Tests/BarosCoreTests/SyncCoordinatorTests.swift.
// Hosted tests cannot import the package test target, so keep the two in sync.
final class FakeSyncClient: SyncClient, @unchecked Sendable {
    var upsertedSettings: [UserSettingsSyncPayload] = []
    var upsertedExercises: [ExerciseSyncPayload] = []
    var upsertedWorkoutSessions: [WorkoutSessionSyncPayload] = []
    var upsertedLoggedExercises: [LoggedExerciseSyncPayload] = []
    var upsertedLoggedSets: [LoggedSetSyncPayload] = []
    var upsertedWorkoutTemplates: [WorkoutTemplateSyncPayload] = []
    var workoutTemplateMutationResults: [SyncMutationResult] = []
    var operationLog: [String] = []
    var tombstones: [(SyncEntityKind, UUID, Date)] = []
    var fetchRequests: [(cursors: SyncChangeCursors, limit: Int)] = []
    var userSettingsMutationResults: [SyncMutationResult] = []
    var exerciseMutationResults: [SyncMutationResult] = []
    var workoutSessionMutationResults: [SyncMutationResult] = []
    var loggedExerciseMutationResults: [SyncMutationResult] = []
    var loggedSetMutationResults: [SyncMutationResult] = []
    var tombstoneResults: [SyncMutationResult] = []
    var fetchResponses: [SyncFetchChangesResponse] = []
    var deleteAccountDataCallCount = 0
    var deleteAccountDataTokens: [UUID] = []
    var deleteAccountDataError: Error?
    var deleteAccountDataResult = AccountDataDeletionResult(
        status: "deleted",
        deletedCounts: AccountDataDeletionCounts(
            loggedSets: 0,
            loggedExercises: 0,
            workoutSessions: 0,
            exercises: 0,
            userSettings: 0
        )
    )
    var cancelAccountDeletionCallCount = 0
    var cancelAccountDeletionTokens: [UUID] = []
    var cancelAccountDeletionError: Error?
    var cancelAccountDeletionResult = AccountDeletionCancellationResult(
        status: "cancelled"
    )
    var fetchResponse = SyncFetchChangesResponse(
        userSettings: [],
        exercises: [],
        workoutSessions: [],
        loggedExercises: [],
        loggedSets: [],
        cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
        hasMore: SyncHasMore(userSettings: false, exercises: false)
    )
    var onFetchChanges: (() -> Void)?
    var onUpsertExercise: ((ExerciseSyncPayload) throws -> Void)?
    var onUpsertLoggedExercise: ((LoggedExerciseSyncPayload) throws -> Void)?
    var onUpsertLoggedSet: ((LoggedSetSyncPayload) throws -> Void)?
    var error: Error?
    var fetchError: Error?

    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        upsertedSettings.append(record)
        if !userSettingsMutationResults.isEmpty {
            return userSettingsMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        try onUpsertExercise?(record)
        upsertedExercises.append(record)
        if !exerciseMutationResults.isEmpty {
            return exerciseMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        operationLog.append("upsertWorkoutSession:\(record.clientId)")
        upsertedWorkoutSessions.append(record)
        if !workoutSessionMutationResults.isEmpty {
            return workoutSessionMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        try onUpsertLoggedExercise?(record)
        operationLog.append("upsertLoggedExercise:\(record.clientId)")
        upsertedLoggedExercises.append(record)
        if !loggedExerciseMutationResults.isEmpty {
            return loggedExerciseMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertWorkoutTemplate(_ record: WorkoutTemplateSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        operationLog.append("upsertWorkoutTemplate:\(record.clientId)")
        upsertedWorkoutTemplates.append(record)
        if !workoutTemplateMutationResults.isEmpty {
            return workoutTemplateMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        try onUpsertLoggedSet?(record)
        operationLog.append("upsertLoggedSet:\(record.clientId)")
        upsertedLoggedSets.append(record)
        if !loggedSetMutationResults.isEmpty {
            return loggedSetMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult {
        if let error { throw error }
        tombstones.append((entityKind, clientId, deletedAt))
        if !tombstoneResults.isEmpty {
            return tombstoneResults.removeFirst()
        }
        return SyncMutationResult(status: "tombstoned", serverUpdatedAt: 1)
    }

    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse {
        if let fetchError { throw fetchError }
        fetchRequests.append((cursors, limit))
        onFetchChanges?()
        if !fetchResponses.isEmpty {
            return fetchResponses.removeFirst()
        }
        return fetchResponse
    }

    func deleteAccountData(cancellationToken: UUID) async throws -> AccountDataDeletionResult {
        deleteAccountDataCallCount += 1
        deleteAccountDataTokens.append(cancellationToken)
        operationLog.append("deleteAccountData")
        if let deleteAccountDataError { throw deleteAccountDataError }
        if let error { throw error }
        return deleteAccountDataResult
    }

    func cancelAccountDeletion(cancellationToken: UUID) async throws -> AccountDeletionCancellationResult {
        cancelAccountDeletionCallCount += 1
        cancelAccountDeletionTokens.append(cancellationToken)
        operationLog.append("cancelAccountDeletion")
        if let cancelAccountDeletionError { throw cancelAccountDeletionError }
        if let error { throw error }
        return cancelAccountDeletionResult
    }
}
