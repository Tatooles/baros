import Foundation
import SwiftData

@MainActor
public final class SyncCoordinator {
    private let client: any SyncClient & Sendable
    private let maxPendingPushEntriesPerRun: Int
    private let observability: any SyncObserving
    private let rpeDefaults: UserDefaults
    private let recorder: SyncOutboxRecorder
    /// The device clock. Injected so tests can move time, including backwards.
    private let clock: () -> Date
    private var isRunning = false
    /// The lowest change-feed position per kind that a pull in this run
    /// skipped because local intent was waiting. Rewound after the push.
    private var keptLocalFloors: [SyncEntityKind: Double] = [:]
    /// Local intent per record, read again for every pulled page, because a
    /// local edit can land while a fetch is in flight.
    private var pullLocalIntents: [SyncOutboxKey: SyncLocalIntent] = [:]
    private var pullBootstrapState = PullBootstrapState()

    public init(
        client: any SyncClient & Sendable,
        maxPendingPushEntriesPerRun: Int = 50,
        observability: any SyncObserving = DisabledSyncObservability.shared,
        rpeDefaults: UserDefaults = .standard,
        clock: @escaping () -> Date = { .now }
    ) {
        self.client = client
        self.maxPendingPushEntriesPerRun = maxPendingPushEntriesPerRun
        self.observability = observability
        self.rpeDefaults = rpeDefaults
        self.clock = clock
        self.recorder = SyncOutboxRecorder(clock: clock)
    }

    @discardableResult
    func run(ownerTokenIdentifier: String?, context: ModelContext) async throws -> SyncRunResult {
        guard let ownerTokenIdentifier else { return SyncRunResult() }
        guard !isRunning else { return SyncRunResult() }
        isRunning = true
        keptLocalFloors = [:]
        defer {
            // Covers a pull that ends the run early, and a pull after the
            // push that kept a record edited while the run was in flight.
            try? rewindPastKeptLocalRecords(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            isRunning = false
            pullLocalIntents = [:]
        }
        try Task.checkCancellation()

        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        let wasFullyBootstrapped = state.hasBootstrappedSettingsExercises && state.hasBootstrappedWorkoutGraph
        let pullSummary: SyncPullSummary
        do {
            pullSummary = try await pullChanges(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        } catch let error as CancellationError {
            throw error
        } catch {
            guard let transientCondition = TransientSyncConditionClassifier.errorCode(for: error) else {
                throw SyncCoordinatorError.remotePullFailed(error)
            }
            throw SyncPullInterruption(
                transientCondition: transientCondition,
                didCompleteInitialPull: false,
                hasIncompleteInitialPull: false
            )
        }
        var hasIncompleteRemotePull = pullSummary.hasIncompleteRemotePull
        if !pullSummary.hasIncompleteRemotePull {
            observability.record(.syncPhaseCompleted(.pull))
        }
        try Task.checkCancellation()

        let bootstrapScope: BootstrapScope
        let includeOwnerlessCompletedWorkouts: Bool
        let completeWorkoutGraphBootstrap: Bool
        if state.hasBootstrappedSettingsExercises && state.hasBootstrappedWorkoutGraph {
            bootstrapScope = .allOwned
            includeOwnerlessCompletedWorkouts = false
            completeWorkoutGraphBootstrap = true
        } else {
            bootstrapScope = pullSummary.hasRemoteSettingsExerciseRecords ? .unownedOnly : .allOwned
            completeWorkoutGraphBootstrap = !pullSummary.hasIncompleteRemotePull || pullSummary.hasAppliedRemoteWorkoutGraphRecords
            includeOwnerlessCompletedWorkouts = completeWorkoutGraphBootstrap && !pullSummary.hasAppliedRemoteWorkoutGraphRecords
        }

        try prepareForSync(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            bootstrapScope: bootstrapScope,
            includeOwnerlessCompletedWorkouts: includeOwnerlessCompletedWorkouts,
            completeWorkoutGraphBootstrap: completeWorkoutGraphBootstrap
        )
        try runConvergenceUpgradeIfNeeded(
            ownerTokenIdentifier: ownerTokenIdentifier,
            wasFullyBootstrapped: wasFullyBootstrapped,
            context: context
        )
        try Task.checkCancellation()
        let pushResult: SyncPushResult
        pushResult = try await pushPendingEntries(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        try rewindPastKeptLocalRecords(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        if let code = pushResult.accountWideRejectionCode {
            throw SyncCoordinatorError.accountUnavailable(code: code)
        }
        guard pushResult.didComplete else {
            return SyncRunResult(
                didPush: pushResult.didPush,
                hasIncompleteRemotePull: hasIncompleteRemotePull,
                transientCondition: pushResult.transientCondition
            )
        }
        if pushResult.didPush {
            observability.record(.syncPhaseCompleted(.push))
        }
        guard !pushResult.hasMorePendingEntries else {
            return SyncRunResult(
                didPush: pushResult.didPush,
                hasMorePendingEntries: true,
                hasIncompleteRemotePull: hasIncompleteRemotePull
            )
        }
        if pushResult.didPush {
            let summary: SyncPullSummary
            do {
                summary = try await pullChanges(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            } catch let error as CancellationError {
                throw error
            } catch {
                guard let transientCondition = TransientSyncConditionClassifier.errorCode(for: error) else {
                    throw SyncCoordinatorError.remotePullFailed(error)
                }
                throw SyncPullInterruption(
                    transientCondition: transientCondition,
                    didCompleteInitialPull: true,
                    hasIncompleteInitialPull: pullSummary.hasIncompleteRemotePull
                )
            }
            hasIncompleteRemotePull = summary.hasIncompleteRemotePull
            if !summary.hasIncompleteRemotePull {
                observability.record(.syncPhaseCompleted(.pull))
            }
        }
        return SyncRunResult(didPush: pushResult.didPush, hasIncompleteRemotePull: hasIncompleteRemotePull)
    }

    /// Pulls a record again after its push, when a pull kept the local copy
    /// for a waiting entry. If that push ends without a verdict from the
    /// server, the server's version is still pulled once the entry completes.
    private func rewindPastKeptLocalRecords(ownerTokenIdentifier: String, context: ModelContext) throws {
        guard !keptLocalFloors.isEmpty else { return }
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        for (kind, floor) in keptLocalFloors {
            state.rewind(kind, toBefore: floor)
        }
        keptLocalFloors = [:]
        try context.save()
    }

    /// The one-time step a device runs after updating to this build.
    ///
    /// - Every local delete is sent again, so the server applies the ones an
    ///   older server rejected or later undid (#97, #98). Only the topmost
    ///   deleted record of a workout is sent; the server deletes what is
    ///   under it. User settings are left out.
    /// - Records already synced take their current version as their sync
    ///   base, so the next edit outranks the version this device holds. A
    ///   record with a waiting entry keeps no base: its edit may not have
    ///   reached the server.
    ///
    /// A device that has not finished its first bootstrap has nothing an older
    /// build synced, so it only marks the step done.
    private func runConvergenceUpgradeIfNeeded(
        ownerTokenIdentifier: String,
        wasFullyBootstrapped: Bool,
        context: ModelContext
    ) throws {
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        guard !state.hasRunConvergenceUpgrade else { return }
        if wasFullyBootstrapped {
            try adoptSyncBasesForSyncedRecords(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            try reassertLocalDeletes(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        }
        if state.hasBootstrappedSettingsExercises && state.hasBootstrappedWorkoutGraph {
            state.hasRunConvergenceUpgrade = true
        }
        try context.save()
    }

    private func adoptSyncBasesForSyncedRecords(ownerTokenIdentifier: String, context: ModelContext) throws {
        let active = try activeOutboxKeys(context: context)
        func adopt(_ record: some SyncEditStamped, kind: SyncEntityKind, id: UUID) {
            guard record.syncBaseUpdatedAt == nil,
                  !active.contains(SyncOutboxKey(kind: kind, id: id)) else { return }
            record.syncBaseUpdatedAt = record.updatedAt.timeIntervalSince1970
        }
        for settings in try context.fetch(FetchDescriptor<UserSettings>())
        where settings.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            adopt(settings, kind: .userSettings, id: settings.id)
        }
        for exercise in try context.fetch(FetchDescriptor<Exercise>())
        where exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            adopt(exercise, kind: .exercise, id: exercise.id)
        }
        for template in try context.fetch(FetchDescriptor<WorkoutTemplate>())
        where template.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            adopt(template, kind: .workoutTemplate, id: template.id)
        }
        for session in try context.fetch(FetchDescriptor<WorkoutSession>())
        where session.syncOwnerTokenIdentifier == ownerTokenIdentifier && session.status != .active {
            adopt(session, kind: .workoutSession, id: session.id)
            for loggedExercise in session.loggedExercises {
                adopt(loggedExercise, kind: .loggedExercise, id: loggedExercise.id)
                for set in loggedExercise.sets {
                    adopt(set, kind: .loggedSet, id: set.id)
                }
            }
        }
    }

    private func reassertLocalDeletes(ownerTokenIdentifier: String, context: ModelContext) throws {
        var active = try activeOutboxKeys(context: context)
        let now = clock()
        func reassert(kind: SyncEntityKind, id: UUID) throws {
            let key = SyncOutboxKey(kind: kind, id: id)
            guard !active.contains(key) else { return }
            try recorder.recordDelete(
                entityKind: kind,
                entityID: id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
            active.insert(key)
        }
        for exercise in try context.fetch(FetchDescriptor<Exercise>())
        where exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier && exercise.isDeleted {
            try reassert(kind: .exercise, id: exercise.id)
        }
        for template in try context.fetch(FetchDescriptor<WorkoutTemplate>())
        where template.syncOwnerTokenIdentifier == ownerTokenIdentifier && template.isDeleted {
            try reassert(kind: .workoutTemplate, id: template.id)
        }
        for session in try context.fetch(FetchDescriptor<WorkoutSession>())
        where session.syncOwnerTokenIdentifier == ownerTokenIdentifier && session.status != .active {
            if session.isDeleted {
                try reassert(kind: .workoutSession, id: session.id)
                continue
            }
            for loggedExercise in session.loggedExercises {
                if loggedExercise.isDeleted {
                    try reassert(kind: .loggedExercise, id: loggedExercise.id)
                    continue
                }
                for set in loggedExercise.sets where set.isDeleted {
                    try reassert(kind: .loggedSet, id: set.id)
                }
            }
        }
    }

    private func activeOutboxKeys(context: ModelContext) throws -> Set<SyncOutboxKey> {
        Set(try activeOutboxEntries(context: context).compactMap(\.outboxKey))
    }

    private func activeOutboxEntries(context: ModelContext) throws -> [SyncOutboxEntry] {
        let completedStatus = SyncOutboxStatus.completed.rawValue
        return try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.statusRaw != completedStatus && entry.operationRaw != ""
            }
        ))
        .filter { $0.isActive && $0.operation != nil }
    }

    func prepareForSync(
        ownerTokenIdentifier: String,
        context: ModelContext,
        bootstrapScope: BootstrapScope = .allOwned,
        includeOwnerlessCompletedWorkouts: Bool = true,
        completeWorkoutGraphBootstrap: Bool = true
    ) throws {
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        let hadBootstrappedWorkoutGraph = state.hasBootstrappedWorkoutGraph
        let bootstrapCandidates = try state.hasBootstrappedSettingsExercises
            ? BootstrapCandidates()
            : candidatesForBootstrap(
                ownerTokenIdentifier: ownerTokenIdentifier,
                scope: bootstrapScope,
                context: context
            )

        // Collapse signed-out duplicate seeds before claiming, while they are still
        // ownerless — once the claim loop below stamps an edited duplicate with the owner
        // it would be indistinguishable from the canonical seed and slip through.
        try mergeOwnerlessDuplicateSeedExercises(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )

        for settings in try context.fetch(FetchDescriptor<UserSettings>()) {
            if settings.syncOwnerTokenIdentifier == nil,
               try canClaimUnownedRecord(
                   entityKind: .userSettings,
                   entityID: settings.id,
                   hasBootstrapped: state.hasBootstrappedSettingsExercises,
                   context: context
               ) {
                settings.syncOwnerTokenIdentifier = ownerTokenIdentifier
            }
        }

        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            if exercise.syncOwnerTokenIdentifier == nil,
               try canClaimUnownedRecord(
                   entityKind: .exercise,
                   entityID: exercise.id,
                   hasBootstrapped: state.hasBootstrappedSettingsExercises,
                   context: context
               ) {
                exercise.syncOwnerTokenIdentifier = ownerTokenIdentifier
            }
        }

        let completedStatus = SyncOutboxStatus.completed.rawValue
        for entry in try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.statusRaw != completedStatus
                    && entry.operationRaw != ""
            }
        )) {
            guard let entityKind = entry.entityKind, entityKind.isV1Synced else {
                continue
            }

            if entry.ownerTokenIdentifier == nil, try SyncOutboxClaimEligibility.canClaim(
                entry: entry,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            ) {
                entry.ownerTokenIdentifier = ownerTokenIdentifier
                try claimWorkoutGraphOwnerIfNeeded(
                    entry: entry,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                )
            }
            if entry.ownerTokenIdentifier == ownerTokenIdentifier, entry.status == .inFlight {
                recorder.markPendingForRetry(entry, now: clock())
            }
        }

        if !state.hasBootstrappedSettingsExercises {
            try bootstrapSettingsExercisesForSync(
                ownerTokenIdentifier: ownerTokenIdentifier,
                candidates: bootstrapCandidates,
                context: context,
                now: clock()
            )
            state.hasBootstrappedSettingsExercises = true
        }
        if !state.hasBootstrappedWorkoutGraph && completeWorkoutGraphBootstrap {
            let didCompleteWorkoutGraphBootstrap = try bootstrapWorkoutGraphForSync(
                ownerTokenIdentifier: ownerTokenIdentifier,
                includeOwnerlessCompletedWorkouts: includeOwnerlessCompletedWorkouts,
                context: context,
                now: clock()
            )
            if didCompleteWorkoutGraphBootstrap {
                state.hasBootstrappedWorkoutGraph = true
                if state.loggedSetsCursor == 0,
                   try hasActiveOutboxEntries(entityKind: .loggedSet, ownerTokenIdentifier: ownerTokenIdentifier, context: context) {
                    state.loggedSetsCursor = 1
                }
            }
        }
        if hadBootstrappedWorkoutGraph && state.loggedSetsCursor == 0 {
            try backfillOwnedCompletedLoggedSetsForSync(
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: clock()
            )
            if try hasActiveOutboxEntries(entityKind: .loggedSet, ownerTokenIdentifier: ownerTokenIdentifier, context: context) {
                state.loggedSetsCursor = 1
            }
        }

        try context.save()
    }

    private func candidatesForBootstrap(
        ownerTokenIdentifier: String,
        scope: BootstrapScope,
        context: ModelContext
    ) throws -> BootstrapCandidates {
        switch scope {
        case .allOwned:
            return BootstrapCandidates(
                settingsIDs: Set(
                    try context.fetch(FetchDescriptor<UserSettings>())
                        .filter { $0.syncOwnerTokenIdentifier == nil || $0.syncOwnerTokenIdentifier == ownerTokenIdentifier }
                        .map(\.id)
                ),
                exerciseIDs: Set(
                    try context.fetch(FetchDescriptor<Exercise>())
                        .filter { $0.syncOwnerTokenIdentifier == nil || $0.syncOwnerTokenIdentifier == ownerTokenIdentifier }
                        .map(\.id)
                )
            )
        case .unownedOnly:
            return BootstrapCandidates(
                settingsIDs: Set(
                    try context.fetch(FetchDescriptor<UserSettings>())
                        .filter { $0.syncOwnerTokenIdentifier == nil }
                        .map(\.id)
                ),
                exerciseIDs: Set(
                    try context.fetch(FetchDescriptor<Exercise>())
                        .filter { $0.syncOwnerTokenIdentifier == nil }
                        .map(\.id)
                )
            )
        }
    }

    private func bootstrapSettingsExercisesForSync(
        ownerTokenIdentifier: String,
        candidates: BootstrapCandidates,
        context: ModelContext,
        now: Date
    ) throws {
        for settings in try context.fetch(FetchDescriptor<UserSettings>())
            where settings.syncOwnerTokenIdentifier == ownerTokenIdentifier && candidates.settingsIDs.contains(settings.id) {
            try recordBootstrapEntry(
                entityKind: .userSettings,
                entityID: settings.id,
                isDeleted: settings.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }

        for exercise in try context.fetch(FetchDescriptor<Exercise>())
            where exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier && candidates.exerciseIDs.contains(exercise.id) {
            try recordBootstrapEntry(
                entityKind: .exercise,
                entityID: exercise.id,
                isDeleted: exercise.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }
    }

    private func bootstrapWorkoutGraphForSync(
        ownerTokenIdentifier: String,
        includeOwnerlessCompletedWorkouts: Bool,
        context: ModelContext,
        now: Date
    ) throws -> Bool {
        guard includeOwnerlessCompletedWorkouts else { return true }
        guard try canBootstrapOwnerlessWorkoutGraph(ownerTokenIdentifier: ownerTokenIdentifier, context: context) else {
            return false
        }

        for session in try context.fetch(FetchDescriptor<WorkoutSession>())
            where session.status == .completed && !session.isDeleted {
            session.syncOwnerTokenIdentifier = ownerTokenIdentifier
            if !(try claimOwnerlessOutboxEntryIfNeeded(
                entityKind: .workoutSession,
                entityID: session.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )) {
                try recordBootstrapEntry(
                    entityKind: .workoutSession,
                    entityID: session.id,
                    isDeleted: false,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )
            }

            for loggedExercise in session.sortedLoggedExercises where !loggedExercise.isDeleted {
                if !(try claimOwnerlessOutboxEntryIfNeeded(
                    entityKind: .loggedExercise,
                    entityID: loggedExercise.id,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )) {
                    try recordBootstrapEntry(
                        entityKind: .loggedExercise,
                        entityID: loggedExercise.id,
                        isDeleted: false,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        context: context,
                        now: now
                    )
                }

                for set in loggedExercise.sortedSets where !set.isDeleted {
                    if !(try claimOwnerlessOutboxEntryIfNeeded(
                        entityKind: .loggedSet,
                        entityID: set.id,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        context: context,
                        now: now
                    )) {
                        try recordBootstrapEntry(
                            entityKind: .loggedSet,
                            entityID: set.id,
                            isDeleted: false,
                            ownerTokenIdentifier: ownerTokenIdentifier,
                            context: context,
                            now: now
                        )
                    }
                }
            }
        }
        return true
    }

    private func backfillOwnedCompletedLoggedSetsForSync(
        ownerTokenIdentifier: String,
        context: ModelContext,
        now: Date
    ) throws {
        for set in try context.fetch(FetchDescriptor<LoggedSet>()) where !set.isDeleted {
            guard let loggedExercise = set.loggedExercise,
                  !loggedExercise.isDeleted,
                  let session = loggedExercise.session,
                  session.status == .completed,
                  !session.isDeleted,
                  session.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                continue
            }

            try recordBootstrapEntry(
                entityKind: .loggedSet,
                entityID: set.id,
                isDeleted: false,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }
    }

    private func canBootstrapOwnerlessWorkoutGraph(ownerTokenIdentifier: String, context: ModelContext) throws -> Bool {
        try OwnerlessWorkoutGraphBootstrapPolicy.canBootstrap(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )
    }

    private func recordBootstrapEntry(
        entityKind: SyncEntityKind,
        entityID: UUID,
        isDeleted: Bool,
        ownerTokenIdentifier: String,
        context: ModelContext,
        now: Date
    ) throws {
        guard try !hasFailedBootstrapEquivalent(
            entityKind: entityKind,
            entityID: entityID,
            isDeleted: isDeleted,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ) else {
            return
        }

        if isDeleted {
            try recorder.recordDelete(
                entityKind: entityKind,
                entityID: entityID,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        } else {
            try recorder.recordCreate(
                entityKind: entityKind,
                entityID: entityID,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }
    }

    private func claimWorkoutGraphOwnerIfNeeded(
        entry: SyncOutboxEntry,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        switch entry.entityKind {
        case .workoutSession:
            try findWorkoutSession(id: entry.entityID, context: context)?.syncOwnerTokenIdentifier = ownerTokenIdentifier
        case .loggedExercise:
            try findLoggedExercise(id: entry.entityID, context: context)?.session?.syncOwnerTokenIdentifier = ownerTokenIdentifier
        case .loggedSet:
            try findLoggedSet(id: entry.entityID, context: context)?.loggedExercise?.session?.syncOwnerTokenIdentifier = ownerTokenIdentifier
        case .workoutTemplate:
            try findWorkoutTemplate(id: entry.entityID, context: context)?.syncOwnerTokenIdentifier = ownerTokenIdentifier
        default:
            break
        }
    }

    private func claimOwnerlessOutboxEntryIfNeeded(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String,
        context: ModelContext,
        now: Date
    ) throws -> Bool {
        let entityKindRaw = entityKind.rawValue
        let completedStatus = SyncOutboxStatus.completed.rawValue
        guard let entry = try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.entityKindRaw == entityKindRaw
                    && entry.entityID == entityID
                    && entry.ownerTokenIdentifier == nil
                    && entry.statusRaw != completedStatus
                    && entry.operationRaw != ""
            }
        ))
            .first(where: { $0.isActive && $0.operation != nil }) else {
            return false
        }

        entry.ownerTokenIdentifier = ownerTokenIdentifier
        entry.refreshPending(now: now)
        try claimWorkoutGraphOwnerIfNeeded(
            entry: entry,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )
        return true
    }

    /// Sends due outbox entries, parents before children.
    ///
    /// One rejected record does not stop the rest (#96). A rejection is
    /// counted on the entry, which backs off and is dead-lettered after
    /// enough rejections over a long enough time. Entries under a rejected
    /// parent wait for it. The run stops on a network error, after repeated
    /// account-wide rejections, and after a streak of uncoded rejections that
    /// looks like a server problem rather than a bad record.
    private func pushPendingEntries(ownerTokenIdentifier: String, context: ModelContext) async throws -> SyncPushResult {
        let runStartedAt = clock()
        let fetchedEntries = try recorder.entriesForPush(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )
        .filter { SyncRejectionPolicy.isDue(nextAttemptAt: $0.nextAttemptAt, now: runStartedAt) }
        let hasMorePendingEntries = fetchedEntries.count > maxPendingPushEntriesPerRun
        let entries = fetchedEntries
            .sorted { lhs, rhs in
                let lhsRank = syncPushRank(for: lhs)
                let rhsRank = syncPushRank(for: rhs)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                let lhsIsDurableRetry = lhs.status == .failed
                let rhsIsDurableRetry = rhs.status == .failed
                if lhsIsDurableRetry != rhsIsDurableRetry {
                    return !lhsIsDurableRetry
                }
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.updatedAt < rhs.updatedAt
            }
            .prefix(maxPendingPushEntriesPerRun)

        var activeEntriesByKey: [SyncOutboxKey: [SyncOutboxEntry]] = [:]
        for entry in try activeOutboxEntries(context: context) {
            if let key = entry.outboxKey {
                activeEntriesByKey[key, default: []].append(entry)
            }
        }
        var rejectedThisRun = Set<SyncOutboxKey>()
        var accountWideRejections = 0
        var uncodedRejectionStreak = 0
        var needsSave = false
        var completedSinceLastSave = 0
        func saveEvery25() throws {
            needsSave = true
            completedSinceLastSave += 1
            if completedSinceLastSave >= 25 {
                try context.save()
                needsSave = false
                completedSinceLastSave = 0
            }
        }

        for entry in entries {
            try Task.checkCancellation()
            guard entry.status == .pending || entry.status == .failed else {
                // A local edit, or the parent requeue below, changed it during the run.
                continue
            }
            if try dependsOnRejectedParent(entry, rejectedThisRun: rejectedThisRun, activeEntriesByKey: activeEntriesByKey, context: context) {
                continue
            }
            let logicalUpdatedAt = logicalFallbackTimestamp(for: entry)
            let previousDurableFailureMessage = entry.status == .failed ? entry.lastErrorMessage : nil
            let wasDurableFailure = entry.status == .failed
            recorder.markInFlight(entry, now: clock())
            needsSave = true

            do {
                try Task.checkCancellation()
                let result = try await push(
                    entry: entry,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    fallbackTimestamp: logicalUpdatedAt,
                    context: context
                )
                try recordSyncBase(from: result, entry: entry, context: context)
                try rewindCursorForIgnoredStaleResult(
                    result,
                    entry: entry,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                )
                recorder.removeCompleted(entry, context: context)
                uncodedRejectionStreak = 0
                try saveEvery25()
            } catch is CancellationError {
                if wasDurableFailure {
                    recorder.restoreFailed(entry, message: previousDurableFailureMessage, now: clock())
                } else {
                    recorder.markPendingForRetry(entry, now: clock())
                }
                try context.save()
                throw CancellationError()
            } catch {
                if let syncError = error as? SyncCoordinatorError, case .ownerMismatch = syncError {
                    observability.record(.durableFailure(DurableSyncFailure(
                        phase: .ownership,
                        entityKind: entry.entityKind,
                        operation: entry.operation,
                        category: .ownership,
                        errorCode: .ownerMismatch,
                        counts: SyncObservationCounts(
                            attempt: entry.attemptCount,
                            pending: fetchedEntries.count
                        )
                    )))
                    context.delete(entry)
                    try saveEvery25()
                    continue
                }

                let failure = SyncPushFailureClassifier.classify(error)
                func restoreUncounted() {
                    guard entry.status == .inFlight else { return }
                    if wasDurableFailure {
                        recorder.restoreFailed(entry, message: previousDurableFailureMessage, now: clock())
                    } else {
                        recorder.markPendingForRetry(entry, now: clock())
                    }
                }
                switch failure {
                case let .transient(condition):
                    restoreUncounted()
                    try context.save()
                    return SyncPushResult(didComplete: false, didPush: true, transientCondition: condition)
                case let .accountWide(code):
                    // Nothing will succeed for this account right now; the
                    // record is fine, so the rejection is not counted.
                    restoreUncounted()
                    accountWideRejections += 1
                    if accountWideRejections >= SyncRejectionPolicy.accountWideRejectionsBeforeStopping {
                        try context.save()
                        return SyncPushResult(didComplete: false, didPush: true, accountWideRejectionCode: code)
                    }
                    needsSave = true
                    continue
                case .record, .unknown:
                    if let key = entry.outboxKey {
                        rejectedThisRun.insert(key)
                    }
                    // An entry a local edit re-queued while it was in flight
                    // is sent as the new edit; this rejection was for the old one.
                    if entry.status == .inFlight {
                        recorder.markRejected(entry, code: failure.code, message: error.localizedDescription, now: clock())
                        if entry.status == .blocked {
                            observability.record(.durableFailure(DurableSyncFailure(
                                phase: .push,
                                entityKind: entry.entityKind,
                                operation: entry.operation,
                                category: .outbox,
                                errorCode: .blockedOutboxEntry,
                                counts: SyncObservationCounts(
                                    attempt: entry.rejectionCount,
                                    pending: fetchedEntries.count
                                )
                            )))
                        }
                    }
                    if case let .record(code) = failure {
                        try requeueMissingReference(
                            code: code,
                            entry: entry,
                            ownerTokenIdentifier: ownerTokenIdentifier,
                            context: context
                        )
                        uncodedRejectionStreak = 0
                    } else {
                        uncodedRejectionStreak += 1
                    }
                    needsSave = true
                    if uncodedRejectionStreak >= SyncRejectionPolicy.uncodedRejectionStreakBeforeStopping {
                        try context.save()
                        return SyncPushResult(didComplete: false, didPush: true)
                    }
                    continue
                }
            }
        }

        if needsSave {
            try context.save()
        }
        return SyncPushResult(
            didComplete: true,
            didPush: !entries.isEmpty,
            hasMorePendingEntries: hasMorePendingEntries
        )
    }

    /// Whether a record upload must wait for a record it depends on: its
    /// workout, its logged exercise, or the exercise a logged exercise names.
    /// It waits while that record's own upload was rejected this run, or while
    /// its create keeps failing, so the server may not have it. A delete never
    /// waits: the server stores it even before its record.
    private func dependsOnRejectedParent(
        _ entry: SyncOutboxEntry,
        rejectedThisRun: Set<SyncOutboxKey>,
        activeEntriesByKey: [SyncOutboxKey: [SyncOutboxEntry]],
        context: ModelContext
    ) throws -> Bool {
        guard entry.operation != .delete else { return false }
        var dependencies: [SyncOutboxKey] = []
        switch entry.entityKind {
        case .some(.loggedExercise):
            let loggedExercise = try findLoggedExercise(id: entry.entityID, context: context)
            if let session = loggedExercise?.session {
                dependencies.append(SyncOutboxKey(kind: .workoutSession, id: session.id))
            }
            if let exercise = loggedExercise?.exercise {
                dependencies.append(SyncOutboxKey(kind: .exercise, id: exercise.id))
            }
        case .some(.loggedSet):
            if let loggedExercise = try findLoggedSet(id: entry.entityID, context: context)?.loggedExercise {
                dependencies.append(SyncOutboxKey(kind: .loggedExercise, id: loggedExercise.id))
                if let session = loggedExercise.session {
                    dependencies.append(SyncOutboxKey(kind: .workoutSession, id: session.id))
                }
            }
        default:
            return false
        }
        return dependencies.contains { dependency in
            if rejectedThisRun.contains(dependency) { return true }
            return (activeEntriesByKey[dependency] ?? []).contains { dependencyEntry in
                (dependencyEntry.status == .failed || dependencyEntry.status == .blocked)
                    && dependencyEntry.operation == .create
            }
        }
    }

    /// A rejected upload names a parent or exercise the server never got.
    /// Upload it again if this device still has it and nothing is queued for it.
    private func requeueMissingReference(
        code: String,
        entry: SyncOutboxEntry,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        let target: SyncOutboxKey?
        switch (code, entry.entityKind) {
        case ("missingParent", .some(.loggedExercise)):
            target = try findLoggedExercise(id: entry.entityID, context: context)?.session
                .map { SyncOutboxKey(kind: .workoutSession, id: $0.id) }
        case ("missingParent", .some(.loggedSet)):
            target = try findLoggedSet(id: entry.entityID, context: context)?.loggedExercise
                .map { SyncOutboxKey(kind: .loggedExercise, id: $0.id) }
        case ("missingExerciseReference", .some(.loggedExercise)):
            let exercise = try findLoggedExercise(id: entry.entityID, context: context)?.exercise
            target = exercise.flatMap { exercise in
                exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier
                    ? SyncOutboxKey(kind: .exercise, id: exercise.id)
                    : nil
            }
        default:
            target = nil
        }
        guard let target,
              try !hasActiveOutboxEntry(entityKind: target.kind, entityID: target.id, context: context) else {
            return
        }
        try recorder.recordUpdate(
            entityKind: target.kind,
            entityID: target.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: clock()
        )
    }

    /// The local copy, edited since the upload or not, now descends from the
    /// version the server stored.
    private func recordSyncBase(from result: SyncMutationResult?, entry: SyncOutboxEntry, context: ModelContext) throws {
        guard let result,
              result.status == "inserted" || result.status == "updated",
              let updatedAt = result.updatedAt else {
            return
        }
        try syncedRecord(kind: entry.entityKind, id: entry.entityID, context: context)?.syncBaseUpdatedAt = updatedAt
    }

    private func syncedRecord(kind: SyncEntityKind?, id: UUID, context: ModelContext) throws -> (any SyncEditStamped)? {
        switch kind {
        case .some(.userSettings): try findUserSettings(id: id, context: context)
        case .some(.exercise): try findExercise(id: id, context: context)
        case .some(.workoutSession): try findWorkoutSession(id: id, context: context)
        case .some(.loggedExercise): try findLoggedExercise(id: id, context: context)
        case .some(.loggedSet): try findLoggedSet(id: id, context: context)
        case .some(.workoutTemplate): try findWorkoutTemplate(id: id, context: context)
        default: nil
        }
    }

    private func syncPushRank(for entry: SyncOutboxEntry) -> Int {
        guard entry.operation == .delete else {
            return syncPushRank(for: entry.entityKind)
        }

        return switch entry.entityKind {
        case .some(.userSettings): 0
        case .some(.exercise): 1
        case .some(.loggedSet): 2
        case .some(.loggedExercise): 3
        case .some(.workoutSession): 4
        case .some(.workoutTemplate): 5
        default: 999
        }
    }

    private func syncPushRank(for entityKind: SyncEntityKind?) -> Int {
        switch entityKind {
        case .some(.userSettings): 0
        case .some(.exercise): 1
        case .some(.workoutSession): 2
        case .some(.loggedExercise): 3
        case .some(.loggedSet): 4
        case .some(.workoutTemplate): 5
        default: 999
        }
    }

    private func logicalFallbackTimestamp(for entry: SyncOutboxEntry) -> Date {
        return entry.hasBeenAttempted ? entry.createdAt : entry.updatedAt
    }

    private func push(
        entry: SyncOutboxEntry,
        ownerTokenIdentifier: String,
        fallbackTimestamp: Date,
        context: ModelContext
    ) async throws -> SyncMutationResult? {
        guard let entityKind = entry.entityKind, let operation = entry.operation else { return nil }

        switch (entityKind, operation) {
        case (.userSettings, .create), (.userSettings, .update):
            guard let settings = try findUserSettings(id: entry.entityID, context: context) else {
                return try await client.tombstone(entityKind: .userSettings, clientId: entry.entityID, deletedAt: fallbackTimestamp)
            }
            guard settings.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .userSettings, entityID: entry.entityID)
            }
            return try await client.upsertUserSettings(SyncPayloadMapper.userSettingsPayload(from: settings))
        case (.exercise, .create), (.exercise, .update):
            guard let exercise = try findExercise(id: entry.entityID, context: context) else {
                return try await client.tombstone(entityKind: .exercise, clientId: entry.entityID, deletedAt: fallbackTimestamp)
            }
            guard exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .exercise, entityID: entry.entityID)
            }
            return try await client.upsertExercise(SyncPayloadMapper.exercisePayload(from: exercise))
        case (.workoutSession, .create), (.workoutSession, .update):
            guard let session = try findWorkoutSession(id: entry.entityID, context: context) else {
                return try await client.tombstone(entityKind: .workoutSession, clientId: entry.entityID, deletedAt: fallbackTimestamp)
            }
            guard session.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .workoutSession, entityID: entry.entityID)
            }
            guard session.status != .active else { return nil }
            return try await client.upsertWorkoutSession(SyncPayloadMapper.workoutSessionPayload(from: session))
        case (.loggedExercise, .create), (.loggedExercise, .update):
            guard let loggedExercise = try findLoggedExercise(id: entry.entityID, context: context) else {
                return try await client.tombstone(entityKind: .loggedExercise, clientId: entry.entityID, deletedAt: fallbackTimestamp)
            }
            guard let session = loggedExercise.session, session.status != .active else { return nil }
            guard session.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .loggedExercise, entityID: entry.entityID)
            }
            return try await client.upsertLoggedExercise(SyncPayloadMapper.loggedExercisePayload(from: loggedExercise))
        case (.loggedSet, .create), (.loggedSet, .update):
            guard let set = try findLoggedSet(id: entry.entityID, context: context) else {
                return try await client.tombstone(entityKind: .loggedSet, clientId: entry.entityID, deletedAt: fallbackTimestamp)
            }
            guard let loggedExercise = set.loggedExercise,
                  let session = loggedExercise.session,
                  session.status != .active else { return nil }
            guard session.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .loggedSet, entityID: entry.entityID)
            }
            return try await client.upsertLoggedSet(SyncPayloadMapper.loggedSetPayload(from: set))
        case (.workoutTemplate, .create), (.workoutTemplate, .update):
            guard let template = try findWorkoutTemplate(id: entry.entityID, context: context) else {
                return try await client.tombstone(entityKind: .workoutTemplate, clientId: entry.entityID, deletedAt: fallbackTimestamp)
            }
            guard template.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .workoutTemplate, entityID: entry.entityID)
            }
            return try await client.upsertWorkoutTemplate(SyncPayloadMapper.workoutTemplatePayload(from: template))
        case (.userSettings, .delete):
            let settings = try findUserSettings(id: entry.entityID, context: context)
            if let settings, settings.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .userSettings, entityID: entry.entityID)
            }
            let deletedAt = settings?.deletedAt ?? fallbackTimestamp
            return try await client.tombstone(entityKind: .userSettings, clientId: entry.entityID, deletedAt: deletedAt)
        case (.exercise, .delete):
            let exercise = try findExercise(id: entry.entityID, context: context)
            if let exercise, exercise.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .exercise, entityID: entry.entityID)
            }
            let deletedAt = exercise?.deletedAt ?? fallbackTimestamp
            return try await client.tombstone(entityKind: .exercise, clientId: entry.entityID, deletedAt: deletedAt)
        case (.workoutSession, .delete):
            let session = try findWorkoutSession(id: entry.entityID, context: context)
            if let session, session.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .workoutSession, entityID: entry.entityID)
            }
            let deletedAt = session?.deletedAt ?? fallbackTimestamp
            return try await client.tombstone(entityKind: .workoutSession, clientId: entry.entityID, deletedAt: deletedAt)
        case (.loggedExercise, .delete):
            let loggedExercise = try findLoggedExercise(id: entry.entityID, context: context)
            if let session = loggedExercise?.session, session.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .loggedExercise, entityID: entry.entityID)
            }
            let deletedAt = loggedExercise?.deletedAt ?? fallbackTimestamp
            return try await client.tombstone(entityKind: .loggedExercise, clientId: entry.entityID, deletedAt: deletedAt)
        case (.loggedSet, .delete):
            let set = try findLoggedSet(id: entry.entityID, context: context)
            if let session = set?.loggedExercise?.session, session.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .loggedSet, entityID: entry.entityID)
            }
            let deletedAt = set?.deletedAt ?? fallbackTimestamp
            return try await client.tombstone(entityKind: .loggedSet, clientId: entry.entityID, deletedAt: deletedAt)
        case (.workoutTemplate, .delete):
            let template = try findWorkoutTemplate(id: entry.entityID, context: context)
            if let template, template.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SyncCoordinatorError.ownerMismatch(entityKind: .workoutTemplate, entityID: entry.entityID)
            }
            let deletedAt = template?.deletedAt ?? fallbackTimestamp
            return try await client.tombstone(entityKind: .workoutTemplate, clientId: entry.entityID, deletedAt: deletedAt)
        default:
            return nil
        }
    }

    private func rewindCursorForIgnoredStaleResult(
        _ result: SyncMutationResult?,
        entry: SyncOutboxEntry,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        guard result?.status == "ignored_stale",
              let serverUpdatedAt = result?.serverUpdatedAt else {
            return
        }

        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        let refetchCursor = max(0, serverUpdatedAt - 1)
        switch entry.entityKind {
        case .some(.userSettings):
            state.userSettingsCursor = min(state.userSettingsCursor, refetchCursor)
        case .some(.exercise):
            state.exercisesCursor = min(state.exercisesCursor, refetchCursor)
        case .some(.workoutSession):
            state.workoutSessionsCursor = min(state.workoutSessionsCursor, refetchCursor)
        case .some(.loggedExercise):
            state.loggedExercisesCursor = min(state.loggedExercisesCursor, refetchCursor)
        case .some(.loggedSet):
            state.loggedSetsCursor = min(state.loggedSetsCursor, refetchCursor)
        case .some(.workoutTemplate):
            state.workoutTemplatesCursor = min(state.workoutTemplatesCursor, refetchCursor)
        default:
            break
        }
    }

    private func findUserSettings(id: UUID, context: ModelContext) throws -> UserSettings? {
        try context.fetch(FetchDescriptor<UserSettings>(
            predicate: #Predicate { settings in
                settings.id == id
            }
        )).first
    }

    private func findExercise(id: UUID, context: ModelContext) throws -> Exercise? {
        try context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { exercise in
                exercise.id == id
            }
        )).first
    }

    private func findWorkoutSession(id: UUID, context: ModelContext) throws -> WorkoutSession? {
        try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == id
            }
        )).first
    }

    private func findLoggedExercise(id: UUID, context: ModelContext) throws -> LoggedExercise? {
        try context.fetch(FetchDescriptor<LoggedExercise>(
            predicate: #Predicate { loggedExercise in
                loggedExercise.id == id
            }
        )).first
    }

    private func findLoggedSet(id: UUID, context: ModelContext) throws -> LoggedSet? {
        try context.fetch(FetchDescriptor<LoggedSet>(
            predicate: #Predicate { set in
                set.id == id
            }
        )).first
    }

    private func findWorkoutTemplate(id: UUID, context: ModelContext) throws -> WorkoutTemplate? {
        try context.fetch(FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { template in
                template.id == id
            }
        )).first
    }

    private func pullChanges(ownerTokenIdentifier: String, context: ModelContext) async throws -> SyncPullSummary {
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        var summary = SyncPullSummary()
        var hasMore = true
        var loggedExercisesCursorBlocked = false
        var loggedSetsCursorBlocked = false
        var pulledRemoteExerciseIDs = Set<UUID>()
        let allowsOwnerScopedSeedAdoption = !state.hasBootstrappedSettingsExercises
        pullBootstrapState = PullBootstrapState(
            isBootstrappingSettingsExercises: !state.hasBootstrappedSettingsExercises,
            isBootstrappingWorkoutGraph: !state.hasBootstrappedWorkoutGraph
        )
        var fetchCursors = SyncChangeCursors(
            userSettings: state.userSettingsCursor,
            exercises: state.exercisesCursor,
            workoutSessions: state.workoutSessionsCursor,
            loggedExercises: state.loggedExercisesCursor,
            loggedSets: state.loggedSetsCursor,
            workoutTemplates: state.workoutTemplatesCursor
        )

        while hasMore {
            let response = try await client.fetchChanges(
                cursors: fetchCursors,
                limit: 100
            )
            // Read after the fetch: a local edit can land while it is in flight.
            pullLocalIntents = try loadLocalIntents(context: context)

            summary.record(response)
            try apply(userSettingsRecords: response.userSettings, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            try apply(
                exerciseRecords: response.exercises,
                ownerTokenIdentifier: ownerTokenIdentifier,
                allowsOwnerScopedSeedAdoption: allowsOwnerScopedSeedAdoption,
                pulledRemoteExerciseIDs: &pulledRemoteExerciseIDs,
                context: context
            )
            let workoutSessionApplyResult = try apply(
                workoutSessionRecords: response.workoutSessions,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
            let loggedExerciseApplyResult = try apply(
                loggedExerciseRecords: response.loggedExercises,
                hasMore: response.hasMore,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
            let loggedSetApplyResult = try apply(
                loggedSetRecords: response.loggedSets,
                hasMore: response.hasMore,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )

            try apply(
                workoutTemplateRecords: response.workoutTemplates ?? [],
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )

            summary.record(workoutSessionApplyResult)
            summary.record(loggedExerciseApplyResult)
            summary.record(loggedSetApplyResult)
            fetchCursors.userSettings = max(fetchCursors.userSettings, response.cursors.userSettings)
            fetchCursors.exercises = max(fetchCursors.exercises, response.cursors.exercises)
            fetchCursors.workoutSessions = max(fetchCursors.workoutSessions, response.cursors.workoutSessions)
            fetchCursors.loggedExercises = nextChildFetchCursor(
                current: fetchCursors.loggedExercises,
                responseCursor: response.cursors.loggedExercises,
                result: loggedExerciseApplyResult
            )
            fetchCursors.loggedSets = nextChildFetchCursor(
                current: fetchCursors.loggedSets,
                responseCursor: response.cursors.loggedSets,
                result: loggedSetApplyResult
            )
            state.userSettingsCursor = max(state.userSettingsCursor, response.cursors.userSettings)
            state.exercisesCursor = max(state.exercisesCursor, response.cursors.exercises)
            if let workoutTemplatesCursor = response.cursors.workoutTemplates {
                fetchCursors.workoutTemplates = max(fetchCursors.workoutTemplates ?? 0, workoutTemplatesCursor)
                state.workoutTemplatesCursor = max(state.workoutTemplatesCursor, workoutTemplatesCursor)
            }
            if let appliedWorkoutSessionCursor = workoutSessionApplyResult.appliedCursor {
                state.workoutSessionsCursor = max(state.workoutSessionsCursor, appliedWorkoutSessionCursor)
            }
            if let appliedLoggedExerciseCursor = loggedExerciseApplyResult.appliedCursor, !loggedExercisesCursorBlocked {
                state.loggedExercisesCursor = max(state.loggedExercisesCursor, appliedLoggedExerciseCursor)
            }
            if loggedExerciseApplyResult.skippedMissingParent {
                loggedExercisesCursorBlocked = true
            }
            if let appliedLoggedSetCursor = loggedSetApplyResult.appliedCursor, !loggedSetsCursorBlocked {
                state.loggedSetsCursor = max(state.loggedSetsCursor, appliedLoggedSetCursor)
            }
            if loggedSetApplyResult.skippedMissingParent {
                loggedSetsCursorBlocked = true
            }
            try context.save()

            hasMore = response.hasMore.hasAnyMore
        }

        return summary
    }

    private func nextChildFetchCursor(
        current: Double,
        responseCursor: Double,
        result: WorkoutChildApplyResult
    ) -> Double {
        if result.skippedMissingParent {
            return max(current, responseCursor)
        }
        if let appliedCursor = result.appliedCursor {
            return max(current, appliedCursor)
        }
        return current
    }

    private func apply(
        userSettingsRecords records: [UserSettingsSyncRecord],
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        for record in records {
            guard let id = UUID(uuidString: record.clientId) else { continue }
            let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
            let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))

            if let settings = try findUserSettings(id: id, context: context) {
                guard settings.syncOwnerTokenIdentifier == nil || settings.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                    continue
                }
                guard try shouldApplyIncoming(
                    kind: .userSettings,
                    local: settings,
                    incomingUpdatedAt: record.updatedAt,
                    incomingDeletedAt: record.deletedAt,
                    incomingCreatedAt: record.createdAt,
                    serverUpdatedAt: record.serverUpdatedAt,
                    isOwnedByCurrentOwner: settings.syncOwnerTokenIdentifier == ownerTokenIdentifier,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                ) else {
                    continue
                }
                apply(record, to: settings, ownerTokenIdentifier: ownerTokenIdentifier)
            } else if incomingDeletedAt == nil {
                if let settings = try adoptableUserSettings(ownerTokenIdentifier: ownerTokenIdentifier, context: context) {
                    let localID = settings.id
                    let hasLocalIntent = try hasActiveOutboxEntry(
                        entityKind: .userSettings,
                        entityID: localID,
                        context: context
                    )
                    settings.id = id
                    settings.syncOwnerTokenIdentifier = ownerTokenIdentifier
                    try retargetOutboxEntries(
                        entityKind: .userSettings,
                        from: localID,
                        to: id,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        context: context
                    )
                    if !hasLocalIntent {
                        apply(record, to: settings, ownerTokenIdentifier: ownerTokenIdentifier)
                    } else if settings.defaultRestTimerSeconds == UserSettings.seededRestTimerSeconds {
                        // The pending change is a choice made before sign-in, such
                        // as the onboarding weight unit. A rest duration still at
                        // its seed was never chosen, so keep the account's.
                        settings.defaultRestTimerSeconds = record.defaultRestTimerSeconds
                    }
                    continue
                }

                let settings = UserSettings(
                    id: id,
                    weightUnit: MeasurementUnit(rawValue: record.weightUnitRaw) ?? .pounds,
                    defaultRestTimerSeconds: record.defaultRestTimerSeconds,
                    hasCompletedOnboarding: record.hasCompletedOnboarding,
                    syncOwnerTokenIdentifier: ownerTokenIdentifier,
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: nil
                )
                settings.weightUnitRaw = record.weightUnitRaw
                settings.syncBaseUpdatedAt = record.updatedAt
                context.insert(settings)
            }
        }
    }

    private func apply(
        _ record: UserSettingsSyncRecord,
        to settings: UserSettings,
        ownerTokenIdentifier: String
    ) {
        settings.syncOwnerTokenIdentifier = ownerTokenIdentifier
        settings.weightUnitRaw = record.weightUnitRaw
        settings.defaultRestTimerSeconds = record.defaultRestTimerSeconds
        settings.hasCompletedOnboarding = record.hasCompletedOnboarding
        settings.createdAt = Date(timeIntervalSince1970: record.createdAt)
        settings.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        settings.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        settings.syncBaseUpdatedAt = record.updatedAt
    }

    private func apply(
        exerciseRecords records: [ExerciseSyncRecord],
        ownerTokenIdentifier: String,
        allowsOwnerScopedSeedAdoption: Bool,
        pulledRemoteExerciseIDs: inout Set<UUID>,
        context: ModelContext
    ) throws {
        for record in records {
            guard let id = UUID(uuidString: record.clientId) else { continue }
            defer { pulledRemoteExerciseIDs.insert(id) }
            let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
            let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))

            if let exercise = try findExercise(id: id, context: context) {
                guard exercise.syncOwnerTokenIdentifier == nil || exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                    continue
                }
                guard try shouldApplyIncoming(
                    kind: .exercise,
                    local: exercise,
                    incomingUpdatedAt: record.updatedAt,
                    incomingDeletedAt: record.deletedAt,
                    incomingCreatedAt: record.createdAt,
                    serverUpdatedAt: record.serverUpdatedAt,
                    isOwnedByCurrentOwner: exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                ) else {
                    continue
                }
                apply(record, to: exercise, ownerTokenIdentifier: ownerTokenIdentifier)
            } else {
                if let seedIdentifier = record.seedIdentifier,
                   let exercise = try adoptableSeedExercise(
                       seedIdentifier: seedIdentifier,
                       ownerTokenIdentifier: ownerTokenIdentifier,
                       allowsOwnerScopedAdoption: allowsOwnerScopedSeedAdoption,
                       excluding: pulledRemoteExerciseIDs,
                       context: context
                   ) {
                    let localID = exercise.id
                    let hasLocalIntent = try hasActiveOutboxEntry(
                        entityKind: .exercise,
                        entityID: localID,
                        context: context
                    )
                    exercise.id = id
                    exercise.syncOwnerTokenIdentifier = ownerTokenIdentifier
                    try repointTemplateEntries(from: localID, to: id, context: context)
                    try retargetOutboxEntries(
                        entityKind: .exercise,
                        from: localID,
                        to: id,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        context: context
                    )
                    if !hasLocalIntent {
                        apply(record, to: exercise, ownerTokenIdentifier: ownerTokenIdentifier)
                    }
                    continue
                }

                let exercise = Exercise(
                    id: id,
                    seedIdentifier: record.seedIdentifier,
                    name: record.name,
                    category: ExerciseCategory(rawValue: record.categoryRaw) ?? .other,
                    equipment: ExerciseEquipment(rawValue: record.equipmentRaw) ?? .other,
                    primaryMuscleGroup: ExerciseMuscleGroup(rawValue: record.primaryMuscleGroupRaw) ?? .other,
                    notes: record.notes,
                    isArchived: record.isArchived,
                    isSeeded: record.isSeeded,
                    syncOwnerTokenIdentifier: ownerTokenIdentifier,
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt
                )
                exercise.categoryRaw = record.categoryRaw
                exercise.equipmentRaw = record.equipmentRaw
                exercise.primaryMuscleRaw = record.primaryMuscleRaw
                exercise.primaryMuscleGroupRaw = record.primaryMuscleGroupRaw
                exercise.trackingMethodRaw = record.trackingMethodRaw
                exercise.syncBaseUpdatedAt = record.updatedAt
                context.insert(exercise)
            }
        }
    }

    private func apply(
        _ record: ExerciseSyncRecord,
        to exercise: Exercise,
        ownerTokenIdentifier: String
    ) {
        exercise.syncOwnerTokenIdentifier = ownerTokenIdentifier
        exercise.seedIdentifier = record.seedIdentifier
        exercise.name = record.name
        exercise.categoryRaw = record.categoryRaw
        exercise.equipmentRaw = record.equipmentRaw
        exercise.primaryMuscleRaw = record.primaryMuscleRaw
        exercise.primaryMuscleGroupRaw = record.primaryMuscleGroupRaw
        exercise.trackingMethodRaw = record.trackingMethodRaw
        exercise.notes = record.notes
        exercise.isArchived = record.isArchived
        exercise.isSeeded = record.isSeeded
        exercise.createdAt = Date(timeIntervalSince1970: record.createdAt)
        exercise.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        exercise.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        exercise.syncBaseUpdatedAt = record.updatedAt
    }

    private func apply(
        workoutTemplateRecords records: [WorkoutTemplateSyncRecord],
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        for record in records {
            guard let id = UUID(uuidString: record.clientId) else { continue }
            let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
            let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))

            if let template = try findWorkoutTemplate(id: id, context: context) {
                guard template.syncOwnerTokenIdentifier == nil || template.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                    continue
                }
                guard try shouldApplyIncoming(
                    kind: .workoutTemplate,
                    local: template,
                    incomingUpdatedAt: record.updatedAt,
                    incomingDeletedAt: record.deletedAt,
                    incomingCreatedAt: record.createdAt,
                    serverUpdatedAt: record.serverUpdatedAt,
                    isOwnedByCurrentOwner: template.syncOwnerTokenIdentifier == ownerTokenIdentifier,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                ) else {
                    continue
                }
                template.syncOwnerTokenIdentifier = ownerTokenIdentifier
                template.name = record.name
                template.entries = Self.templateEntries(from: record)
                template.createdAt = Date(timeIntervalSince1970: record.createdAt)
                template.updatedAt = incomingUpdatedAt
                template.deletedAt = incomingDeletedAt
                template.syncBaseUpdatedAt = record.updatedAt
            } else {
                let template = WorkoutTemplate(
                    id: id,
                    name: record.name,
                    entries: Self.templateEntries(from: record),
                    syncOwnerTokenIdentifier: ownerTokenIdentifier,
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt
                )
                template.syncBaseUpdatedAt = record.updatedAt
                context.insert(template)
            }
        }
    }

    private static func templateEntries(from record: WorkoutTemplateSyncRecord) -> [WorkoutTemplateEntry] {
        record.entries.compactMap { entry in
            guard let id = UUID(uuidString: entry.id) else { return nil }
            return WorkoutTemplateEntry(
                id: id,
                exerciseID: entry.exerciseClientId.flatMap(UUID.init(uuidString:)),
                exerciseSnapshotName: entry.exerciseSnapshotName,
                exerciseSnapshotEquipmentRaw: entry.exerciseSnapshotEquipmentRaw,
                exerciseSnapshotPrimaryMuscleGroupRaw: entry.exerciseSnapshotPrimaryMuscleGroupRaw,
                supersetGroupID: entry.supersetGroupID.flatMap(UUID.init(uuidString:))
            )
        }
    }

    /// Keeps template entries on an exercise whose id sync replaced or merged,
    /// and uploads the change so other devices follow.
    private func repointTemplateEntries(from oldExerciseID: UUID, to newExerciseID: UUID, context: ModelContext) throws {
        let now = clock()
        for template in try context.fetch(FetchDescriptor<WorkoutTemplate>())
        where template.repointEntries(from: oldExerciseID, to: newExerciseID) {
            template.stampEdit(now: now)
            try recorder.recordUpdate(
                entityKind: .workoutTemplate,
                entityID: template.id,
                ownerTokenIdentifier: template.syncOwnerTokenIdentifier,
                context: context,
                now: now
            )
        }
    }

    private func apply(
        workoutSessionRecords records: [WorkoutSessionSyncRecord],
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> WorkoutGraphApplyResult {
        var maxAppliedServerUpdatedAt: Double?
        var didApplyLocalGraphRecord = false
        for record in records {
            guard let id = UUID(uuidString: record.clientId) else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
            let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))

            if let session = try findWorkoutSession(id: id, context: context) {
                guard session.syncOwnerTokenIdentifier == nil || session.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                    continue
                }
                guard try shouldApplyIncoming(
                    kind: .workoutSession,
                    local: session,
                    incomingUpdatedAt: record.updatedAt,
                    incomingDeletedAt: record.deletedAt,
                    incomingCreatedAt: record.createdAt,
                    serverUpdatedAt: record.serverUpdatedAt,
                    isOwnedByCurrentOwner: session.syncOwnerTokenIdentifier == ownerTokenIdentifier,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                ) else {
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                    continue
                }
                apply(record, to: session, ownerTokenIdentifier: ownerTokenIdentifier)
                didApplyLocalGraphRecord = true
            } else {
                guard incomingDeletedAt == nil else {
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                    continue
                }
                let session = WorkoutSession(
                    id: id,
                    title: record.title,
                    startedAt: Date(timeIntervalSince1970: record.startedAt),
                    endedAt: record.endedAt.map(Date.init(timeIntervalSince1970:)),
                    durationSeconds: record.durationSeconds,
                    notes: record.notes,
                    status: WorkoutSessionStatus(rawValue: record.statusRaw) ?? .completed,
                    source: WorkoutSource(rawValue: record.sourceRaw) ?? .blank,
                    sourceSessionID: record.sourceSessionID.flatMap(UUID.init(uuidString:)),
                    sourceTemplateID: record.sourceTemplateID.flatMap(UUID.init(uuidString:)),
                    referenceNotes: record.referenceNotes,
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt,
                    healthLinkID: record.healthLinkID.flatMap(UUID.init(uuidString:)),
                    syncOwnerTokenIdentifier: ownerTokenIdentifier
                )
                session.syncBaseUpdatedAt = record.updatedAt
                context.insert(session)
                didApplyLocalGraphRecord = true
            }
            maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
        }
        return WorkoutGraphApplyResult(
            appliedCursor: maxAppliedServerUpdatedAt,
            didApplyLocalGraphRecord: didApplyLocalGraphRecord
        )
    }

    private func apply(_ record: WorkoutSessionSyncRecord, to session: WorkoutSession, ownerTokenIdentifier: String) {
        session.syncOwnerTokenIdentifier = ownerTokenIdentifier
        session.title = record.title
        session.startedAt = Date(timeIntervalSince1970: record.startedAt)
        session.endedAt = record.endedAt.map(Date.init(timeIntervalSince1970:))
        session.durationSeconds = record.durationSeconds
        session.notes = record.notes
        session.referenceNotes = record.referenceNotes
        session.statusRaw = record.statusRaw
        session.sourceRaw = record.sourceRaw
        session.sourceSessionID = record.sourceSessionID.flatMap(UUID.init(uuidString:))
        session.sourceTemplateID = record.sourceTemplateID.flatMap(UUID.init(uuidString:))
        session.createdAt = Date(timeIntervalSince1970: record.createdAt)
        session.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        session.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        session.healthLinkID = record.healthLinkID.flatMap(UUID.init(uuidString:))
        session.syncBaseUpdatedAt = record.updatedAt
        if let deletedAt = session.deletedAt {
            cascadeRemoteWorkoutSessionDeletion(session, deletedAt: deletedAt)
        }
    }

    private func cascadeRemoteWorkoutSessionDeletion(_ session: WorkoutSession, deletedAt: Date) {
        for loggedExercise in session.loggedExercises {
            if loggedExercise.deletedAt == nil {
                loggedExercise.deletedAt = deletedAt
            }
            if loggedExercise.updatedAt < deletedAt {
                loggedExercise.updatedAt = deletedAt
            }

            for set in loggedExercise.sets {
                if set.deletedAt == nil {
                    set.deletedAt = deletedAt
                }
                if set.updatedAt < deletedAt {
                    set.updatedAt = deletedAt
                }
            }
        }
    }

    private func apply(
        loggedExerciseRecords records: [LoggedExerciseSyncRecord],
        hasMore: SyncHasMore,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> WorkoutChildApplyResult {
        var maxAppliedServerUpdatedAt: Double?
        var skippedMissingParent = false
        var didApplyLocalGraphRecord = false
        var canAdvanceCursor = true
        func recordAppliedCursor(_ serverUpdatedAt: Double) {
            guard canAdvanceCursor else { return }
            maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, serverUpdatedAt)
        }

        for record in records {
            guard let id = UUID(uuidString: record.clientId) else {
                recordAppliedCursor(record.serverUpdatedAt)
                continue
            }
            guard let sessionID = UUID(uuidString: record.sessionClientId),
                  let session = try findWorkoutSession(id: sessionID, context: context) else {
                if record.deletedAt != nil {
                    // A placeholder tombstone names no workout. Apply it to a
                    // copy this device holds.
                    if let held = try findLoggedExercise(id: id, context: context),
                       held.session?.syncOwnerTokenIdentifier == ownerTokenIdentifier {
                        applyDeletion(of: record.updatedAt, deletedAt: record.deletedAt, to: held)
                    }
                    recordAppliedCursor(record.serverUpdatedAt)
                    continue
                }
                guard hasMore.workoutSessions else {
                    canAdvanceCursor = false
                    skippedMissingParent = true
                    continue
                }
                return WorkoutChildApplyResult(appliedCursor: maxAppliedServerUpdatedAt)
            }
            guard session.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                recordAppliedCursor(record.serverUpdatedAt)
                continue
            }
            let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
            let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
            let exercise: Exercise?
            if let exerciseClientId = record.exerciseClientId,
               let exerciseID = UUID(uuidString: exerciseClientId) {
                guard let resolvedExercise = try findExercise(id: exerciseID, context: context) else {
                    guard incomingDeletedAt == nil else {
                        recordAppliedCursor(record.serverUpdatedAt)
                        continue
                    }
                    guard hasMore.exercises else {
                        canAdvanceCursor = false
                        skippedMissingParent = true
                        continue
                    }
                    return WorkoutChildApplyResult(appliedCursor: maxAppliedServerUpdatedAt)
                }
                exercise = resolvedExercise
            } else {
                exercise = nil
            }

            if let loggedExercise = try findLoggedExercise(id: id, context: context) {
                guard try shouldApplyIncoming(
                    kind: .loggedExercise,
                    local: loggedExercise,
                    incomingUpdatedAt: record.updatedAt,
                    incomingDeletedAt: record.deletedAt,
                    incomingCreatedAt: record.createdAt,
                    serverUpdatedAt: record.serverUpdatedAt,
                    isOwnedByCurrentOwner: true,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                ) else {
                    recordAppliedCursor(record.serverUpdatedAt)
                    continue
                }
                apply(record, to: loggedExercise, session: session, exercise: exercise)
                didApplyLocalGraphRecord = true
            } else {
                guard incomingDeletedAt == nil else {
                    recordAppliedCursor(record.serverUpdatedAt)
                    continue
                }
                let loggedExercise = LoggedExercise(
                    id: id,
                    orderIndex: record.orderIndex,
                    exercise: exercise,
                    exerciseSnapshotName: record.exerciseSnapshotName,
                    exerciseSnapshotEquipmentRaw: record.exerciseSnapshotEquipmentRaw,
                    exerciseSnapshotPrimaryMuscleGroupRaw: record.exerciseSnapshotPrimaryMuscleGroupRaw,
                    notes: record.notes,
                    referenceNotes: record.referenceNotes,
                    sourceLoggedExerciseID: record.sourceLoggedExerciseID.flatMap(UUID.init(uuidString:)),
                    supersetGroupID: record.supersetGroupID.flatMap(UUID.init(uuidString:)),
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt
                )
                loggedExercise.hasSnapshotMetadata = record.hasSnapshotMetadata
                loggedExercise.trackingMethodRaw = record.trackingMethodRaw
                loggedExercise.syncBaseUpdatedAt = record.updatedAt
                loggedExercise.session = session
                session.loggedExercises.append(loggedExercise)
                context.insert(loggedExercise)
                didApplyLocalGraphRecord = true
            }
            recordAppliedCursor(record.serverUpdatedAt)
        }
        return WorkoutChildApplyResult(
            appliedCursor: maxAppliedServerUpdatedAt,
            didApplyLocalGraphRecord: didApplyLocalGraphRecord,
            skippedMissingParent: skippedMissingParent
        )
    }

    private func apply(
        _ record: LoggedExerciseSyncRecord,
        to loggedExercise: LoggedExercise,
        session: WorkoutSession,
        exercise: Exercise?
    ) {
        loggedExercise.orderIndex = record.orderIndex
        loggedExercise.exercise = exercise
        loggedExercise.exerciseSnapshotName = record.exerciseSnapshotName
        loggedExercise.exerciseSnapshotEquipmentRaw = record.exerciseSnapshotEquipmentRaw
        loggedExercise.exerciseSnapshotPrimaryMuscleGroupRaw = record.exerciseSnapshotPrimaryMuscleGroupRaw
        loggedExercise.hasSnapshotMetadata = record.hasSnapshotMetadata
        loggedExercise.trackingMethodRaw = record.trackingMethodRaw
        loggedExercise.notes = record.notes
        loggedExercise.referenceNotes = record.referenceNotes
        loggedExercise.sourceLoggedExerciseID = record.sourceLoggedExerciseID.flatMap(UUID.init(uuidString:))
        loggedExercise.supersetGroupID = record.supersetGroupID.flatMap(UUID.init(uuidString:))
        loggedExercise.createdAt = Date(timeIntervalSince1970: record.createdAt)
        loggedExercise.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        loggedExercise.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        loggedExercise.syncBaseUpdatedAt = record.updatedAt
        loggedExercise.session = session
        if !session.loggedExercises.contains(where: { $0.id == loggedExercise.id }) {
            session.loggedExercises.append(loggedExercise)
        }
    }

    private func apply(
        loggedSetRecords records: [LoggedSetSyncRecord],
        hasMore: SyncHasMore,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> WorkoutChildApplyResult {
        var maxAppliedServerUpdatedAt: Double?
        var skippedMissingParent = false
        var didApplyLocalGraphRecord = false
        var canAdvanceCursor = true
        func recordAppliedCursor(_ serverUpdatedAt: Double) {
            guard canAdvanceCursor else { return }
            maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, serverUpdatedAt)
        }

        for record in records {
            if record.deletedAt == nil, WorkoutNumericInputPolicy.validatedRPE(record.rpe) != nil {
                RPEPreference.enableIfUndecided(defaults: rpeDefaults)
            }
            guard let id = UUID(uuidString: record.clientId) else {
                recordAppliedCursor(record.serverUpdatedAt)
                continue
            }
            guard let loggedExerciseID = UUID(uuidString: record.loggedExerciseClientId),
                  let loggedExercise = try findLoggedExercise(id: loggedExerciseID, context: context) else {
                if record.deletedAt != nil {
                    // A placeholder tombstone names no logged exercise. Apply
                    // it to a copy this device holds.
                    if let held = try findLoggedSet(id: id, context: context),
                       held.loggedExercise?.session?.syncOwnerTokenIdentifier == ownerTokenIdentifier {
                        applyDeletion(of: record.updatedAt, deletedAt: record.deletedAt, to: held)
                    }
                    recordAppliedCursor(record.serverUpdatedAt)
                    continue
                }
                guard hasMore.exercises || hasMore.workoutSessions || hasMore.loggedExercises else {
                    canAdvanceCursor = false
                    skippedMissingParent = true
                    continue
                }
                return WorkoutChildApplyResult(appliedCursor: maxAppliedServerUpdatedAt)
            }
            guard loggedExercise.session?.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                recordAppliedCursor(record.serverUpdatedAt)
                continue
            }
            let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
            let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))

            if let set = try findLoggedSet(id: id, context: context) {
                guard try shouldApplyIncoming(
                    kind: .loggedSet,
                    local: set,
                    incomingUpdatedAt: record.updatedAt,
                    incomingDeletedAt: record.deletedAt,
                    incomingCreatedAt: record.createdAt,
                    serverUpdatedAt: record.serverUpdatedAt,
                    isOwnedByCurrentOwner: true,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                ) else {
                    recordAppliedCursor(record.serverUpdatedAt)
                    continue
                }
                apply(record, to: set, loggedExercise: loggedExercise)
                didApplyLocalGraphRecord = true
            } else {
                guard incomingDeletedAt == nil else {
                    recordAppliedCursor(record.serverUpdatedAt)
                    continue
                }
                let set = LoggedSet(
                    id: id,
                    orderIndex: record.orderIndex,
                    weight: WorkoutNumericInputPolicy.validatedWeight(record.weight),
                    reps: WorkoutNumericInputPolicy.validatedReps(record.reps),
                    durationSeconds: WorkoutNumericInputPolicy.validatedDuration(record.durationSeconds),
                    rpe: WorkoutNumericInputPolicy.validatedRPE(record.rpe),
                    kind: SetKind(rawValue: record.kindRaw) ?? .working,
                    isCompleted: record.isCompleted,
                    completedAt: record.completedAt.map(Date.init(timeIntervalSince1970:)),
                    notes: record.notes,
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt,
                    healthLinkID: record.healthLinkID.flatMap(UUID.init(uuidString:)),
                    sourceLoggedSetID: record.sourceLoggedSetID.flatMap(UUID.init(uuidString:))
                )
                set.syncBaseUpdatedAt = record.updatedAt
                set.loggedExercise = loggedExercise
                loggedExercise.sets.append(set)
                context.insert(set)
                didApplyLocalGraphRecord = true
            }
            recordAppliedCursor(record.serverUpdatedAt)
        }
        return WorkoutChildApplyResult(
            appliedCursor: maxAppliedServerUpdatedAt,
            didApplyLocalGraphRecord: didApplyLocalGraphRecord,
            skippedMissingParent: skippedMissingParent
        )
    }

    private func apply(_ record: LoggedSetSyncRecord, to set: LoggedSet, loggedExercise: LoggedExercise) {
        set.orderIndex = record.orderIndex
        set.weight = WorkoutNumericInputPolicy.validatedWeight(record.weight)
        set.reps = WorkoutNumericInputPolicy.validatedReps(record.reps)
        set.durationSeconds = WorkoutNumericInputPolicy.validatedDuration(record.durationSeconds)
        set.knowsDuration = true
        set.rpe = WorkoutNumericInputPolicy.validatedRPE(record.rpe)
        set.kindRaw = record.kindRaw
        set.isCompleted = record.isCompleted
        set.completedAt = record.completedAt.map(Date.init(timeIntervalSince1970:))
        set.notes = record.notes
        set.createdAt = Date(timeIntervalSince1970: record.createdAt)
        set.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        set.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        set.healthLinkID = record.healthLinkID.flatMap(UUID.init(uuidString:))
        set.sourceLoggedSetID = record.sourceLoggedSetID.flatMap(UUID.init(uuidString:))
        set.syncBaseUpdatedAt = record.updatedAt
        set.loggedExercise = loggedExercise
        if !loggedExercise.sets.contains(where: { $0.id == set.id }) {
            loggedExercise.sets.append(set)
        }
    }

    /// The pull rule for one record this device holds (`SyncPullRule`).
    /// Returns whether to copy the server's version. A placeholder tombstone,
    /// which carries no content, deletes the local copy here and returns false.
    private func shouldApplyIncoming(
        kind: SyncEntityKind,
        local: some SyncEditStamped,
        incomingUpdatedAt: Double,
        incomingDeletedAt: Double?,
        incomingCreatedAt: Double,
        serverUpdatedAt: Double,
        isOwnedByCurrentOwner: Bool,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> Bool {
        let key = SyncOutboxKey(kind: kind, id: local.id)
        let decision = SyncPullRule.decide(
            localUpdatedAt: local.updatedAt,
            localIsDeleted: local.deletedAt != nil,
            incomingUpdatedAt: Date(timeIntervalSince1970: incomingUpdatedAt),
            incomingIsDeleted: incomingDeletedAt != nil,
            localIntent: pullLocalIntents[key] ?? .none,
            isBootstrapping: pullBootstrapState.isBootstrapping(kind),
            reassertsLocalDeletes: kind != .userSettings && isOwnedByCurrentOwner
        )
        switch decision {
        case .applyIncoming:
            // Zero createdAt marks a placeholder: the server got the delete
            // before the record, so it has no content to copy.
            if incomingCreatedAt == 0, incomingDeletedAt != nil {
                applyDeletion(of: incomingUpdatedAt, deletedAt: incomingDeletedAt, to: local)
                return false
            }
            return true
        case let .keepLocal(rewindCursor):
            if rewindCursor {
                keptLocalFloors[kind] = min(keptLocalFloors[kind] ?? serverUpdatedAt, serverUpdatedAt)
            }
            return false
        case .reassertLocalDelete:
            try recorder.recordDelete(
                entityKind: kind,
                entityID: key.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: clock()
            )
            pullLocalIntents[key] = .pending
            return false
        }
    }

    /// Applies only the deletion of a server version, keeping local content.
    private func applyDeletion(of incomingUpdatedAt: Double, deletedAt incomingDeletedAt: Double?, to local: some SyncEditStamped) {
        guard let incomingDeletedAt else { return }
        let deletedAt = local.deletedAt ?? Date(timeIntervalSince1970: incomingDeletedAt)
        local.deletedAt = deletedAt
        local.updatedAt = Date(timeIntervalSince1970: incomingUpdatedAt)
        local.syncBaseUpdatedAt = incomingUpdatedAt
        if let session = local as? WorkoutSession {
            cascadeRemoteWorkoutSessionDeletion(session, deletedAt: deletedAt)
        }
    }

    private func loadLocalIntents(context: ModelContext) throws -> [SyncOutboxKey: SyncLocalIntent] {
        var intents: [SyncOutboxKey: SyncLocalIntent] = [:]
        for entry in try activeOutboxEntries(context: context) {
            guard let key = entry.outboxKey else { continue }
            let intent: SyncLocalIntent = entry.status == .blocked ? .blocked : .pending
            if intents[key] != .pending {
                intents[key] = intent
            }
        }
        return intents
    }

    private func canClaimUnownedRecord(
        entityKind: SyncEntityKind,
        entityID: UUID,
        hasBootstrapped: Bool,
        context: ModelContext
    ) throws -> Bool {
        if !hasBootstrapped {
            return true
        }

        return try hasActiveOutboxEntry(entityKind: entityKind, entityID: entityID, context: context)
    }

    private func adoptableUserSettings(ownerTokenIdentifier: String, context: ModelContext) throws -> UserSettings? {
        try context.fetch(FetchDescriptor<UserSettings>())
            .first { settings in
                (settings.syncOwnerTokenIdentifier == nil || settings.syncOwnerTokenIdentifier == ownerTokenIdentifier)
                    && !settings.isDeleted
            }
    }

    /// Collapses ownerless duplicate seeded exercises into the matching owner-scoped seed.
    ///
    /// Signed-out mode re-seeds default exercises as ownerless rows because it cannot see
    /// the owner-scoped library, so after a sign-in / sign-out / sign-in cycle a seed can
    /// exist twice: once owner-scoped (already synced) and once ownerless. A workout logged
    /// while signed out references the ownerless copy, whose `exerciseClientId` does not
    /// exist remotely for the owner, so the server rejects the logged exercise. Repoint
    /// those references onto the canonical owner-scoped seed and drop the stranded
    /// duplicate. Only runs when an owner-scoped seed already exists for the identifier, so
    /// it never interferes with first-time bootstrap of a purely ownerless library.
    private func mergeOwnerlessDuplicateSeedExercises(
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        var canonicalBySeedIdentifier: [String: Exercise] = [:]
        for exercise in exercises
        where exercise.isSeeded && exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            guard let seedIdentifier = exercise.seedIdentifier else { continue }
            if let existing = canonicalBySeedIdentifier[seedIdentifier],
               existing.createdAt <= exercise.createdAt {
                continue
            }
            canonicalBySeedIdentifier[seedIdentifier] = exercise
        }

        guard !canonicalBySeedIdentifier.isEmpty else { return }

        for duplicate in exercises
        where duplicate.isSeeded && duplicate.syncOwnerTokenIdentifier == nil {
            guard let seedIdentifier = duplicate.seedIdentifier,
                  let canonical = canonicalBySeedIdentifier[seedIdentifier],
                  canonical.id != duplicate.id else {
                continue
            }
            try mergeSeedExercise(
                duplicate: duplicate,
                into: canonical,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
        }
    }

    private func mergeSeedExercise(
        duplicate: Exercise,
        into canonical: Exercise,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        let duplicateID = duplicate.id

        // Last-write-wins, but only for a duplicate the user actually edited while signed
        // out. A freshly re-seeded duplicate gets a current `updatedAt` purely from being
        // created, so a timestamp comparison alone would let an unedited default overwrite
        // the canonical seed's previously-synced custom fields. Require an active exercise
        // outbox entry (real local intent) before copying. The retargeted outbox entry then
        // pushes the merged values under the canonical id.
        let duplicateHasLocalEdit = try hasActiveOutboxEntry(
            entityKind: .exercise,
            entityID: duplicateID,
            context: context
        )
        if duplicateHasLocalEdit, duplicate.updatedAt > canonical.updatedAt {
            canonical.name = duplicate.name
            canonical.categoryRaw = duplicate.categoryRaw
            canonical.equipmentRaw = duplicate.equipmentRaw
            canonical.primaryMuscleRaw = duplicate.primaryMuscleRaw
            canonical.primaryMuscleGroupRaw = duplicate.primaryMuscleGroupRaw
            canonical.trackingMethodRaw = duplicate.trackingMethodRaw ?? canonical.trackingMethodRaw
            canonical.notes = duplicate.notes
            canonical.isArchived = duplicate.isArchived
            canonical.stampEdit(now: max(clock(), duplicate.updatedAt))
        }

        for loggedExercise in try context.fetch(FetchDescriptor<LoggedExercise>())
        where loggedExercise.exercise?.id == duplicateID {
            loggedExercise.exercise = canonical
        }
        try repointTemplateEntries(from: duplicateID, to: canonical.id, context: context)
        try retargetOutboxEntries(
            entityKind: .exercise,
            from: duplicateID,
            to: canonical.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )
        context.delete(duplicate)
    }

    private func adoptableSeedExercise(
        seedIdentifier: String,
        ownerTokenIdentifier: String,
        allowsOwnerScopedAdoption: Bool,
        excluding pulledRemoteExerciseIDs: Set<UUID>,
        context: ModelContext
    ) throws -> Exercise? {
        try context.fetch(FetchDescriptor<Exercise>())
            .first { exercise in
                !pulledRemoteExerciseIDs.contains(exercise.id)
                    && (exercise.syncOwnerTokenIdentifier == nil
                        || (allowsOwnerScopedAdoption && exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier))
                    && exercise.isSeeded
                    && exercise.seedIdentifier == seedIdentifier
            }
    }

    private func hasActiveOutboxEntry(
        entityKind: SyncEntityKind,
        entityID: UUID,
        context: ModelContext
    ) throws -> Bool {
        let entityKindRaw = entityKind.rawValue
        let completedStatus = SyncOutboxStatus.completed.rawValue
        return try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.entityKindRaw == entityKindRaw
                    && entry.entityID == entityID
                    && entry.statusRaw != completedStatus
                    && entry.operationRaw != ""
            }
        ))
            .contains { entry in
                entry.isActive && entry.operation != nil
            }
    }

    private func hasFailedBootstrapEquivalent(
        entityKind: SyncEntityKind,
        entityID: UUID,
        isDeleted: Bool,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> Bool {
        let entityKindRaw = entityKind.rawValue
        let failedStatus = SyncOutboxStatus.failed.rawValue
        let blockedStatus = SyncOutboxStatus.blocked.rawValue
        return try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.entityKindRaw == entityKindRaw
                    && entry.entityID == entityID
                    && entry.ownerTokenIdentifier == ownerTokenIdentifier
                    && (entry.statusRaw == failedStatus || entry.statusRaw == blockedStatus)
                    && entry.operationRaw != ""
            }
        ))
            .contains { entry in
                guard entry.status == .failed || entry.status == .blocked, let operation = entry.operation else {
                    return false
                }
                return isDeleted ? operation == .delete : operation == .create || operation == .update
            }
    }

    private func hasActiveOutboxEntries(
        entityKind: SyncEntityKind,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> Bool {
        let entityKindRaw = entityKind.rawValue
        let completedStatus = SyncOutboxStatus.completed.rawValue
        return try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.entityKindRaw == entityKindRaw
                    && entry.ownerTokenIdentifier == ownerTokenIdentifier
                    && entry.statusRaw != completedStatus
                    && entry.operationRaw != ""
            }
        ))
            .contains { entry in
                entry.isActive && entry.operation != nil
            }
    }

    private func retargetOutboxEntries(
        entityKind: SyncEntityKind,
        from oldID: UUID,
        to newID: UUID,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        let entityKindRaw = entityKind.rawValue
        let completedStatus = SyncOutboxStatus.completed.rawValue
        for entry in try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.entityKindRaw == entityKindRaw
                    && entry.entityID == oldID
                    && entry.statusRaw != completedStatus
                    && entry.operationRaw != ""
            }
        )) where entry.isActive {
            entry.entityID = newID
            if entry.ownerTokenIdentifier == nil {
                entry.ownerTokenIdentifier = ownerTokenIdentifier
            }
        }
    }
}

enum SyncCoordinatorError: LocalizedError {
    case remotePullFailed(Error)
    case ownerMismatch(entityKind: SyncEntityKind, entityID: UUID)
    /// The server refused writes for the whole account, such as while it is
    /// being deleted or after sign-in lapsed. Nothing was counted against the
    /// queued records.
    case accountUnavailable(code: String)

    var errorDescription: String? {
        switch self {
        case let .accountUnavailable(code):
            "Cloud sync is unavailable for this account right now (\(code))."
        case let .remotePullFailed(error):
            error.localizedDescription
        case let .ownerMismatch(entityKind, entityID):
            "Cannot sync \(entityKind.displayName) \(entityID.uuidString) because the local record belongs to a different owner."
        }
    }
}

enum BootstrapScope {
    case allOwned
    case unownedOnly
}

private struct BootstrapCandidates {
    var settingsIDs: Set<UUID> = []
    var exerciseIDs: Set<UUID> = []
}

private struct SyncPullSummary {
    var hasUserSettings = false
    var hasExercises = false
    var hasIncompleteRemotePull = false
    var hasAppliedRemoteWorkoutGraphRecords = false

    var hasRemoteSettingsExerciseRecords: Bool {
        hasUserSettings || hasExercises
    }

    mutating func record(_ response: SyncFetchChangesResponse) {
        hasUserSettings = hasUserSettings || !response.userSettings.isEmpty
        hasExercises = hasExercises || !response.exercises.isEmpty
    }

    mutating func record(_ result: WorkoutGraphApplyResult) {
        hasAppliedRemoteWorkoutGraphRecords = hasAppliedRemoteWorkoutGraphRecords || result.didApplyLocalGraphRecord
    }

    mutating func record(_ result: WorkoutChildApplyResult) {
        hasIncompleteRemotePull = hasIncompleteRemotePull || result.skippedMissingParent
        hasAppliedRemoteWorkoutGraphRecords = hasAppliedRemoteWorkoutGraphRecords || result.didApplyLocalGraphRecord
    }
}

struct SyncRunResult {
    var didPush = false
    var hasMorePendingEntries = false
    var hasIncompleteRemotePull = false
    var transientCondition: SyncStableErrorCode?
}

struct SyncPullInterruption: Error {
    let transientCondition: SyncStableErrorCode
    let didCompleteInitialPull: Bool
    let hasIncompleteInitialPull: Bool
}

private struct SyncPushResult {
    var didComplete: Bool
    var didPush: Bool
    var hasMorePendingEntries = false
    var transientCondition: SyncStableErrorCode?
    /// Set when the run stopped after repeated account-wide rejections.
    var accountWideRejectionCode: String?
}

/// Which record groups are still in their first-run bootstrap, read once at
/// the start of a pull.
private struct PullBootstrapState {
    var isBootstrappingSettingsExercises = false
    var isBootstrappingWorkoutGraph = false

    func isBootstrapping(_ kind: SyncEntityKind) -> Bool {
        switch kind {
        case .workoutSession, .loggedExercise, .loggedSet:
            isBootstrappingWorkoutGraph
        default:
            isBootstrappingSettingsExercises
        }
    }
}

private struct WorkoutGraphApplyResult {
    var appliedCursor: Double?
    var didApplyLocalGraphRecord = false
}

private struct WorkoutChildApplyResult {
    var appliedCursor: Double?
    var didApplyLocalGraphRecord = false
    var skippedMissingParent = false
}

private extension SyncHasMore {
    var hasAnyMore: Bool {
        userSettings || exercises || workoutSessions || loggedExercises || loggedSets || workoutTemplates == true
    }
}

private extension SyncEntityKind {
    var displayName: String {
        switch self {
        case .userSettings:
            "userSettings"
        case .exercise:
            "exercise"
        case .workoutSession:
            "workoutSession"
        case .loggedExercise:
            "loggedExercise"
        case .loggedSet:
            "loggedSet"
        case .workoutTemplate:
            "workoutTemplate"
        case .healthDataLink:
            "healthDataLink"
        case .seedMetadata:
            "seedMetadata"
        }
    }
}
