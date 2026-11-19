import BarosCore
import ClerkKit
import SwiftData
import SwiftUI

struct AccountDeletionFactory {
    let makeCoordinator: @MainActor (
        _ modelContext: ModelContext,
        _ syncScheduler: SyncScheduler,
        _ clerk: Clerk
    ) -> AccountDeletionCoordinator

    static func live(syncClient: any SyncClient & Sendable) -> AccountDeletionFactory {
        AccountDeletionFactory { modelContext, syncScheduler, clerk in
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitest-in-memory-store"),
               ProcessInfo.processInfo.arguments.contains("--uitest-fail-cloud-deletion-once") {
                return AccountDeletionCoordinator(
                    syncClient: CloudDeletionUITestClient(),
                    accountDeleter: CloudDeletionUITestAccountDeleter(),
                    attemptStore: CloudDeletionUITestAttemptStore(),
                    localDataResetService: LocalDataResetService(),
                    syncScheduler: syncScheduler,
                    modelContext: modelContext
                )
            }
            #endif
            return AccountDeletionCoordinator(
                syncClient: syncClient,
                accountDeleter: ClerkAccountDeleter(clerk: clerk),
                attemptStore: UserDefaultsAccountDeletionAttemptStore(),
                localDataResetService: LocalDataResetService(),
                syncScheduler: syncScheduler,
                modelContext: modelContext
            )
        }
    }
}

private struct AccountDeletionFactoryKey: EnvironmentKey {
    static let defaultValue = AccountDeletionFactory { _, _, _ in
        fatalError("AccountDeletionFactory must be injected by the app.")
    }
}

extension EnvironmentValues {
    var accountDeletionFactory: AccountDeletionFactory {
        get { self[AccountDeletionFactoryKey.self] }
        set { self[AccountDeletionFactoryKey.self] = newValue }
    }
}

#if DEBUG
// All operations are local stand-ins; this fixture never calls Clerk or Convex.
private final class CloudDeletionUITestClient: SyncClient, @unchecked Sendable {
    private let lock = NSLock()
    private var hasFailed = false
    private enum FixtureError: Error { case cloudDeletionUnconfirmed, unexpectedSync }

    func deleteAccountData(cancellationToken: UUID) async throws -> AccountDataDeletionResult {
        if ProcessInfo.processInfo.arguments.contains("--uitest-delay-cloud-deletion") {
            try await Task.sleep(for: .seconds(4))
        }
        await CloudDeletionUITestGate.shared.waitForRelease()
        let shouldFail = lock.withLock {
            if hasFailed { return false }
            hasFailed = true
            return true
        }
        if shouldFail { throw FixtureError.cloudDeletionUnconfirmed }
        return AccountDataDeletionResult(status: "deleted", deletedCounts: .init(
            loggedSets: 0, loggedExercises: 0, workoutSessions: 0, exercises: 0, userSettings: 0
        ))
    }
    func cancelAccountDeletion(cancellationToken: UUID) async throws -> AccountDeletionCancellationResult {
        throw FixtureError.unexpectedSync
    }
    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult { throw FixtureError.unexpectedSync }
    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult { throw FixtureError.unexpectedSync }
    func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult { throw FixtureError.unexpectedSync }
    func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult { throw FixtureError.unexpectedSync }
    func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult { throw FixtureError.unexpectedSync }
    func upsertWorkoutTemplate(_ record: WorkoutTemplateSyncPayload) async throws -> SyncMutationResult { throw FixtureError.unexpectedSync }
    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult { throw FixtureError.unexpectedSync }
    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse { throw FixtureError.unexpectedSync }
}

/// With `--uitest-hold-cloud-deletion`, the fixture's cloud request stays pending until
/// the test taps `UITestReleaseCloudDeletionButton`. A fixed delay races slow CI runners
/// when a test checks that nothing happens while the request is still running.
@MainActor
@Observable
final class CloudDeletionUITestGate {
    static let shared = CloudDeletionUITestGate()
    private static let isEnabled = ProcessInfo.processInfo.arguments.contains("--uitest-hold-cloud-deletion")
    /// True only while a request is parked, so the release control proves one is pending.
    private(set) var isHoldingRequest = false
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async {
        guard Self.isEnabled, !isReleased else { return }
        isHoldingRequest = true
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isReleased = true
        isHoldingRequest = false
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

struct CloudDeletionUITestReleaseControl: View {
    var body: some View {
        if CloudDeletionUITestGate.shared.isHoldingRequest {
            Button("Release Cloud Deletion") { CloudDeletionUITestGate.shared.release() }
                .font(.caption2)
                .accessibilityIdentifier("UITestReleaseCloudDeletionButton")
        }
    }
}

@MainActor
private final class CloudDeletionUITestAccountDeleter: AccountDeleting {
    func deleteCurrentAccount() async throws {}
}

@MainActor
private final class CloudDeletionUITestAttemptStore: AccountDeletionAttemptStoring {
    private var token: UUID?
    func persistedCancellationToken(for ownerTokenIdentifier: String?) -> UUID? { token }
    func setPersistedCancellationToken(_ token: UUID?, for ownerTokenIdentifier: String?) { self.token = token }
}
#endif
