import Foundation
import SwiftData

@MainActor
@Observable
final class SyncScheduler {
    private static let incompleteSyncFailureMessage = "Cloud sync could not finish."

    struct Failure: Equatable {
        let message: String
        let occurredAt: Date
    }

    var currentOwnerTokenIdentifier: String? {
        didSet {
            guard oldValue != currentOwnerTokenIdentifier else { return }
            cancelInFlightSync()
            clearRuntimeStateForOwnerChange()
        }
    }
    private(set) var requestCount = 0
    private(set) var isSyncing = false
    private(set) var hasQueuedSyncRequest = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastFailure: Failure?
    private(set) var isDeletionModeEnabled = false

    private var coordinator: SyncCoordinator?
    private var modelContext: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var needsSync = false

    init(
        coordinator: SyncCoordinator? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.coordinator = coordinator
        self.modelContext = modelContext
    }

    func configure(coordinator: SyncCoordinator, modelContext: ModelContext) {
        self.coordinator = coordinator
        self.modelContext = modelContext
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func requestSync() {
        requestCount += 1
        guard !isDeletionModeEnabled else { return }
        guard currentOwnerTokenIdentifier != nil else { return }
        guard let coordinator, let modelContext else { return }
        guard syncTask == nil else {
            needsSync = true
            hasQueuedSyncRequest = true
            return
        }

        startSyncTask(coordinator: coordinator, modelContext: modelContext)
    }

    func retrySync() {
        requestSync()
    }

    func beginDeletionMode() {
        isDeletionModeEnabled = true
        cancelInFlightSync()
        clearRuntimeStateForOwnerChange()
    }

    func endDeletionMode() {
        isDeletionModeEnabled = false
    }

    func recoverAfterFailedAccountDeletion() {
        guard let currentOwnerTokenIdentifier, let modelContext else {
            endDeletionMode()
            return
        }

        let recorder = SyncOutboxRecorder()
        try? recorder.enqueueOwnedV1SyncableRecords(
            ownerTokenIdentifier: currentOwnerTokenIdentifier,
            context: modelContext,
            now: .now
        )
        try? modelContext.save()
        endDeletionMode()
        requestSync()
    }

    func resetAfterDataDeletion() {
        isDeletionModeEnabled = false
        currentOwnerTokenIdentifier = nil
        cancelInFlightSync()
        clearRuntimeStateForOwnerChange()
    }

    func seedDefaultsForCurrentOwner() {
        guard let currentOwnerTokenIdentifier, let modelContext else { return }
        let hasBootstrapped = (try? SyncCursorState.state(
            for: currentOwnerTokenIdentifier,
            context: modelContext
        ).hasBootstrappedSettingsExercises) ?? true
        try? SeedDataService.seedIfNeeded(
            context: modelContext,
            ownerTokenIdentifier: currentOwnerTokenIdentifier,
            claimOwnerlessVisibleDefaults: !hasBootstrapped
        )
    }

    func seedDefaultsForLocalMode() {
        guard let modelContext else { return }
        try? SeedDataService.seedIfNeeded(context: modelContext)
    }

    func recordFailureForTesting(message: String, at date: Date = .now) {
        lastFailure = Failure(message: message, occurredAt: date)
    }

    private func cancelInFlightSync() {
        guard let syncTask else { return }
        needsSync = false
        syncTask.cancel()
    }

    private func clearRuntimeStateForOwnerChange() {
        hasQueuedSyncRequest = false
        isSyncing = false
        lastSyncedAt = nil
        lastFailure = nil
    }

    private func startSyncTask(coordinator: SyncCoordinator, modelContext: ModelContext) {
        syncTask = Task { @MainActor in
            isSyncing = true
            while true {
                needsSync = false
                hasQueuedSyncRequest = false
                let syncOwnerTokenIdentifier = currentOwnerTokenIdentifier
                do {
                    let result = try await coordinator.run(ownerTokenIdentifier: syncOwnerTokenIdentifier, context: modelContext)
                    guard !Task.isCancelled, currentOwnerTokenIdentifier == syncOwnerTokenIdentifier else {
                        break
                    }
                    guard !hasFailedActiveV1OutboxEntries(
                        ownerTokenIdentifier: syncOwnerTokenIdentifier,
                        context: modelContext
                    ) else {
                        lastFailure = Failure(message: Self.incompleteSyncFailureMessage, occurredAt: .now)
                        break
                    }
                    if result.hasMorePendingEntries {
                        needsSync = true
                    } else {
                        lastSyncedAt = .now
                    }
                    lastFailure = nil
                } catch is CancellationError {
                    break
                } catch {
                    guard !Task.isCancelled, currentOwnerTokenIdentifier == syncOwnerTokenIdentifier else {
                        break
                    }
                    lastFailure = Failure(message: error.localizedDescription, occurredAt: .now)
                    break
                }
                if Task.isCancelled {
                    break
                }
                guard needsSync else { break }
                await Task.yield()
            }

            let shouldStartQueuedSync = needsSync && currentOwnerTokenIdentifier != nil && !isDeletionModeEnabled
            needsSync = false
            hasQueuedSyncRequest = false
            isSyncing = false
            syncTask = nil
            if shouldStartQueuedSync {
                startSyncTask(coordinator: coordinator, modelContext: modelContext)
            }
        }
    }

    private func hasFailedActiveV1OutboxEntries(
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) -> Bool {
        guard let ownerTokenIdentifier else { return false }
        let failedStatus = SyncOutboxStatus.failed.rawValue
        let entries = (try? context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.statusRaw == failedStatus
                    && (entry.ownerTokenIdentifier == ownerTokenIdentifier || entry.ownerTokenIdentifier == nil)
            }
        ))) ?? []
        return entries.contains { entry in
            guard entry.isActive else { return false }
            guard entry.entityKind?.isV1Synced == true else { return false }
            return true
        }
    }
}
