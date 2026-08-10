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
    private static let durableFailureAttemptThreshold = 3

    enum FailureReason: Equatable {
        case failedOutboxPush
        case incompleteRemotePull
        case syncError
        case recoveryMarkerPersistenceFailed
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
            observability.setCurrentOwner(currentOwnerTokenIdentifier)
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
    private(set) var isCloudSyncAuthorized = true
    private(set) var recoveryInvalidationGeneration: UInt = 0

    private var coordinator: SyncCoordinator?
    private var modelContext: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var needsSync = false
    private let lastKnownOwnerTokenStore: LastKnownSyncOwnerTokenStore
    let observability: any SyncObserving

    init(
        coordinator: SyncCoordinator? = nil,
        modelContext: ModelContext? = nil,
        lastKnownOwnerTokenStore: LastKnownSyncOwnerTokenStore = .standard,
        observability: any SyncObserving = DisabledSyncObservability.shared
    ) {
        self.coordinator = coordinator
        self.modelContext = modelContext
        self.lastKnownOwnerTokenStore = lastKnownOwnerTokenStore
        self.observability = observability
    }

    func configure(coordinator: SyncCoordinator, modelContext: ModelContext) {
        self.coordinator = coordinator
        self.modelContext = modelContext
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func requestSync() {
        requestSync(isRetry: false)
    }

    private func requestSync(isRetry: Bool) {
        requestCount += 1
        observability.record(.syncRequested(isRetry: isRetry))
        guard !isDeletionModeEnabled else {
            observability.record(.transient(phase: .scheduler, errorCode: .deletionMode))
            return
        }
        guard currentOwnerTokenIdentifier != nil else {
            observability.record(.transient(phase: .ownership, errorCode: .noCurrentOwner))
            return
        }
        guard isCloudSyncAuthorized else {
            observability.record(.transient(phase: .scheduler, errorCode: .authorizationUnavailable))
            needsSync = true
            hasQueuedSyncRequest = true
            return
        }
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
        guard isCloudSyncAuthorized else { return }
        guard currentOwnerTokenIdentifier != nil else { return }
        guard coordinator != nil, modelContext != nil else { return }

        requestSync()
    }

    func retrySync() {
        requestSync(isRetry: true)
    }

    func pauseCloudSync() {
        guard isCloudSyncAuthorized else { return }
        let shouldQueueSync = syncTask != nil || needsSync
        isCloudSyncAuthorized = false
        cancelInFlightSync()
        if shouldQueueSync {
            needsSync = true
            hasQueuedSyncRequest = true
        }
    }

    func authorizeCloudSync() {
        isCloudSyncAuthorized = true
    }

    func beginDeletionMode() {
        invalidateRecoveryAttempts()
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
        invalidateRecoveryAttempts()
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
        invalidateRecoveryAttempts()
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

    private func invalidateRecoveryAttempts() {
        recoveryInvalidationGeneration &+= 1
    }

    private func clearRuntimeStateForOwnerChange() {
        needsSync = false
        hasQueuedSyncRequest = false
        isSyncing = false
        lastSyncedAt = nil
        lastFailure = nil
    }

    private func startSyncTask(coordinator: SyncCoordinator, modelContext: ModelContext) {
        syncTask = Task { @MainActor in
            isSyncing = true
            var reportedFailureBeingRetried = reportedDurableOutboxFailure(
                ownerTokenIdentifier: currentOwnerTokenIdentifier,
                context: modelContext
            )
            while true {
                needsSync = false
                hasQueuedSyncRequest = false
                let syncOwnerTokenIdentifier = currentOwnerTokenIdentifier
                do {
                    let result = try await coordinator.run(ownerTokenIdentifier: syncOwnerTokenIdentifier, context: modelContext)
                    guard !Task.isCancelled, currentOwnerTokenIdentifier == syncOwnerTokenIdentifier else {
                        break
                    }
                    if let transientCondition = result.transientCondition {
                        lastFailure = Failure(
                            message: Self.incompleteSyncFailureMessage,
                            occurredAt: .now,
                            reason: .failedOutboxPush
                        )
                        let reachedDurableFailureThreshold = failedActiveV1OutboxEntries(
                            ownerTokenIdentifier: syncOwnerTokenIdentifier,
                            context: modelContext
                        ).contains { entry in
                            entry.attemptCount >= Self.durableFailureAttemptThreshold
                        }
                        if reachedDurableFailureThreshold {
                            recordDurableOutboxFailure(
                                ownerTokenIdentifier: syncOwnerTokenIdentifier,
                                context: modelContext
                            )
                        } else {
                            observability.record(.transient(
                                phase: .push,
                                errorCode: transientCondition
                            ))
                        }
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
                        recordDurableOutboxFailure(
                            ownerTokenIdentifier: syncOwnerTokenIdentifier,
                            context: modelContext
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
                        recordDurableFailure(
                            reason: .incompleteRemotePull,
                            ownerTokenIdentifier: syncOwnerTokenIdentifier,
                            context: modelContext
                        )
                        break
                    } else {
                        lastSyncedAt = .now
                        let counts = observationCounts(
                            ownerTokenIdentifier: syncOwnerTokenIdentifier,
                            context: modelContext,
                            recovered: 1
                        )
                        if let recoveredFailure = reportedFailureBeingRetried {
                            observability.record(.syncRecovered(
                                failure: recoveredFailure,
                                counts: counts
                            ))
                            reportedFailureBeingRetried = nil
                        } else {
                            observability.record(.syncSucceeded(counts: counts))
                        }
                    }
                    lastFailure = nil
                } catch is CancellationError {
                    if currentOwnerTokenIdentifier == syncOwnerTokenIdentifier {
                        observability.record(.transient(
                            phase: .scheduler,
                            errorCode: .cancelled
                        ))
                    }
                    break
                } catch {
                    guard !Task.isCancelled, currentOwnerTokenIdentifier == syncOwnerTokenIdentifier else {
                        break
                    }
                    if let transientCondition = TransientSyncConditionClassifier.errorCode(for: error) {
                        observability.record(.transient(
                            phase: .pull,
                            errorCode: transientCondition
                        ))
                        lastFailure = Failure(
                            message: error.localizedDescription,
                            occurredAt: .now,
                            reason: .syncError
                        )
                        break
                    }
                    lastFailure = Failure(message: error.localizedDescription, occurredAt: .now, reason: .syncError)
                    recordDurableFailure(
                        reason: .syncError,
                        ownerTokenIdentifier: syncOwnerTokenIdentifier,
                        context: modelContext
                    )
                    break
                }
                if Task.isCancelled {
                    break
                }
                guard needsSync else { break }
                await Task.yield()
            }

            let hasValidQueuedSync = needsSync
                && currentOwnerTokenIdentifier != nil
                && !isDeletionModeEnabled
            let shouldStartQueuedSync = hasValidQueuedSync && isCloudSyncAuthorized
            isSyncing = false
            syncTask = nil
            if shouldStartQueuedSync {
                needsSync = false
                hasQueuedSyncRequest = false
                startSyncTask(coordinator: coordinator, modelContext: modelContext)
            } else if hasValidQueuedSync {
                hasQueuedSyncRequest = true
            } else {
                needsSync = false
                hasQueuedSyncRequest = false
            }
        }
    }

    private func hasFailedActiveV1OutboxEntries(
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) -> Bool {
        !failedActiveV1OutboxEntries(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ).isEmpty
    }

    private func failedActiveV1OutboxEntries(
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) -> [SyncOutboxEntry] {
        guard let ownerTokenIdentifier else { return [] }
        let failedStatus = SyncOutboxStatus.failed.rawValue
        let entries = (try? context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.statusRaw == failedStatus
                    && (entry.ownerTokenIdentifier == ownerTokenIdentifier || entry.ownerTokenIdentifier == nil)
            }
        ))) ?? []
        return entries.filter { entry in
            entry.isActive && entry.entityKind?.isV1Synced == true
        }
    }

    private func recordDurableFailure(
        reason: FailureReason,
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) {
        let failedEntry = failedActiveV1OutboxEntries(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ).first
        let failureClassification: (
            phase: SyncObservationPhase,
            category: SyncFailureCategory,
            errorCode: SyncStableErrorCode
        ) = switch reason {
        case .failedOutboxPush:
            (.push, .outbox, .failedOutboxPush)
        case .incompleteRemotePull:
            (.pull, .remotePull, .incompleteRemotePull)
        case .syncError:
            (.scheduler, .clientCall, .clientCallFailed)
        case .recoveryMarkerPersistenceFailed:
            (.scheduler, .localPersistence, .recoveryMarkerPersistenceFailed)
        }
        observability.record(.durableFailure(DurableSyncFailure(
            phase: failureClassification.phase,
            entityKind: failedEntry?.entityKind,
            operation: failedEntry?.operation,
            category: failureClassification.category,
            errorCode: failureClassification.errorCode,
            counts: observationCounts(
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                attempt: failedEntry?.attemptCount ?? 0
            )
        )))
    }

    private func recordDurableOutboxFailure(
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) {
        guard let failedEntry = failedActiveV1OutboxEntries(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ).first else {
            recordDurableFailure(
                reason: .syncError,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
            return
        }

        failedEntry.hasReportedDurableFailure = true
        do {
            try context.save()
        } catch {
            context.rollback()
            recordDurableFailure(
                reason: .recoveryMarkerPersistenceFailed,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
            return
        }

        recordDurableFailure(
            reason: .failedOutboxPush,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )
    }

    private func reportedDurableOutboxFailure(
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) -> DurableSyncFailure? {
        guard let entry = failedActiveV1OutboxEntries(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ).first(where: { $0.hasReportedDurableFailure == true }) else {
            return nil
        }
        return DurableSyncFailure(
            phase: .push,
            entityKind: entry.entityKind,
            operation: entry.operation,
            category: .outbox,
            errorCode: .failedOutboxPush
        )
    }

    private func observationCounts(
        ownerTokenIdentifier: String?,
        context: ModelContext,
        attempt: Int = 0,
        recovered: Int = 0
    ) -> SyncObservationCounts {
        guard let ownerTokenIdentifier else {
            return SyncObservationCounts(attempt: attempt, recovered: recovered)
        }
        let entries = ((try? context.fetch(FetchDescriptor<SyncOutboxEntry>())) ?? [])
            .filter { entry in
                entry.isActive
                    && entry.entityKind?.isV1Synced == true
                    && (entry.ownerTokenIdentifier == ownerTokenIdentifier || entry.ownerTokenIdentifier == nil)
            }
        return SyncObservationCounts(
            attempt: attempt,
            pending: entries.count,
            failed: entries.filter { $0.status == .failed }.count,
            recovered: recovered
        )
    }
}
