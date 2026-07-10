import Foundation
import SwiftData

@MainActor
final class LastKnownSyncOwnerTokenStore {
    static let standard = LastKnownSyncOwnerTokenStore()

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "lastKnownSyncOwnerTokenIdentifier"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    var ownerTokenIdentifier: String? {
        get {
            userDefaults.string(forKey: key)
        }
        set {
            guard let newValue, !newValue.isEmpty else {
                userDefaults.removeObject(forKey: key)
                return
            }
            userDefaults.set(newValue, forKey: key)
        }
    }

    func clear() {
        ownerTokenIdentifier = nil
    }
}

@MainActor
@Observable
final class SyncScheduler {
    private static let incompleteSyncFailureMessage = "Cloud sync could not finish."

    enum FailureReason: Equatable {
        case failedOutboxPush
        case incompleteRemotePull
        case syncError
    }

    struct Failure: Equatable {
        let message: String
        let occurredAt: Date
        let reason: FailureReason
    }

    var currentOwnerTokenIdentifier: String? {
        didSet {
            if let currentOwnerTokenIdentifier {
                lastKnownOwnerTokenStore.ownerTokenIdentifier = currentOwnerTokenIdentifier
            }
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
    private let lastKnownOwnerTokenStore: LastKnownSyncOwnerTokenStore

    init(
        coordinator: SyncCoordinator? = nil,
        modelContext: ModelContext? = nil,
        lastKnownOwnerTokenStore: LastKnownSyncOwnerTokenStore = .standard
    ) {
        self.coordinator = coordinator
        self.modelContext = modelContext
        self.lastKnownOwnerTokenStore = lastKnownOwnerTokenStore
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

    func requestSyncOnAppForeground() {
        guard !isDeletionModeEnabled else { return }
        guard currentOwnerTokenIdentifier != nil else { return }
        guard coordinator != nil, modelContext != nil else { return }

        requestSync()
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
        lastKnownOwnerTokenStore.clear()
        currentOwnerTokenIdentifier = nil
        cancelInFlightSync()
        clearRuntimeStateForOwnerChange()
    }

    @discardableResult
    func restoreLastKnownOwnerTokenIdentifier() -> Bool {
        restoreLastKnownOwnerTokenIdentifier(where: { _ in true })
    }

    @discardableResult
    func restoreLastKnownOwnerTokenIdentifier(matchingOwnerSubject ownerSubject: String) -> Bool {
        restoreLastKnownOwnerTokenIdentifier { ownerTokenIdentifier in
            Self.ownerTokenIdentifier(ownerTokenIdentifier, matchesSubject: ownerSubject)
        }
    }

    @discardableResult
    func activateValidatedOwnerTokenIdentifier(_ ownerTokenIdentifier: String) -> Bool {
        guard !ownerTokenIdentifier.isEmpty else {
            return false
        }

        activateOwnerTokenIdentifier(ownerTokenIdentifier)
        return true
    }

    private func restoreLastKnownOwnerTokenIdentifier(where isAllowedOwner: (String) -> Bool) -> Bool {
        let cachedOwnerTokenIdentifier = lastKnownOwnerTokenStore.ownerTokenIdentifier
        let ownerTokenIdentifier: String?
        if let cachedOwnerTokenIdentifier, isAllowedOwner(cachedOwnerTokenIdentifier) {
            ownerTokenIdentifier = cachedOwnerTokenIdentifier
        } else if let inferredOwnerTokenIdentifier = inferSingleLocalOwnerTokenIdentifier(),
                  isAllowedOwner(inferredOwnerTokenIdentifier) {
            ownerTokenIdentifier = inferredOwnerTokenIdentifier
        } else {
            ownerTokenIdentifier = nil
        }

        guard let ownerTokenIdentifier else {
            return false
        }

        activateOwnerTokenIdentifier(ownerTokenIdentifier)
        return true
    }

    func enterSignedOutMode() {
        lastKnownOwnerTokenStore.clear()
        currentOwnerTokenIdentifier = nil
        seedDefaultsForLocalMode()
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

    private func inferSingleLocalOwnerTokenIdentifier() -> String? {
        let owners = localOwnerTokenIdentifiers()

        return owners.count == 1 ? owners.first : nil
    }

    private func localOwnerTokenIdentifiers() -> Set<String> {
        guard let modelContext else { return [] }

        var owners = Set<String>()
        if let cursorStates = try? modelContext.fetch(FetchDescriptor<SyncCursorState>()) {
            owners.formUnion(cursorStates.map(\.ownerTokenIdentifier))
        }
        if let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()) {
            owners.formUnion(settings.compactMap { settings in
                settings.isDeleted ? nil : settings.syncOwnerTokenIdentifier
            })
        }
        if let exercises = try? modelContext.fetch(FetchDescriptor<Exercise>()) {
            owners.formUnion(exercises.compactMap { exercise in
                exercise.isDeleted ? nil : exercise.syncOwnerTokenIdentifier
            })
        }
        if let sessions = try? modelContext.fetch(FetchDescriptor<WorkoutSession>()) {
            owners.formUnion(sessions.compactMap { session in
                session.isDeleted ? nil : session.syncOwnerTokenIdentifier
            })
        }

        return owners
    }

    private func activateOwnerTokenIdentifier(_ ownerTokenIdentifier: String) {
        lastKnownOwnerTokenStore.ownerTokenIdentifier = ownerTokenIdentifier
        currentOwnerTokenIdentifier = ownerTokenIdentifier
        seedDefaultsForCurrentOwner()
    }

    private static func ownerTokenIdentifier(_ ownerTokenIdentifier: String, matchesSubject subject: String) -> Bool {
        guard !subject.isEmpty,
              let separatorIndex = ownerTokenIdentifier.lastIndex(of: "|") else {
            return false
        }

        let subjectStartIndex = ownerTokenIdentifier.index(after: separatorIndex)
        guard subjectStartIndex < ownerTokenIdentifier.endIndex else {
            return false
        }

        return String(ownerTokenIdentifier[subjectStartIndex...]) == subject
    }

    func recordFailureForTesting(message: String, at date: Date = .now, reason: FailureReason = .syncError) {
        lastFailure = Failure(message: message, occurredAt: date, reason: reason)
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
                        lastFailure = Failure(
                            message: Self.incompleteSyncFailureMessage,
                            occurredAt: .now,
                            reason: .failedOutboxPush
                        )
                        break
                    }
                    if result.hasMorePendingEntries {
                        needsSync = true
                    } else if result.hasIncompleteRemotePull {
                        lastFailure = Failure(
                            message: Self.incompleteSyncFailureMessage,
                            occurredAt: .now,
                            reason: .incompleteRemotePull
                        )
                        break
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
                    lastFailure = Failure(message: error.localizedDescription, occurredAt: .now, reason: .syncError)
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
