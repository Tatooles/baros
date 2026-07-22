import Foundation
import SwiftData

@MainActor
final class SyncCoordinator {
    private let client: any SyncClient & Sendable
    private let maxPendingPushEntriesPerRun: Int
    private let recorder = SyncOutboxRecorder()
    private var isRunning = false

    init(client: any SyncClient & Sendable, maxPendingPushEntriesPerRun: Int = 50) {
        self.client = client
        self.maxPendingPushEntriesPerRun = maxPendingPushEntriesPerRun
    }

    @discardableResult
    func run(ownerTokenIdentifier: String?, context: ModelContext) async throws -> SyncRunResult {
        guard let ownerTokenIdentifier else { return SyncRunResult() }
        guard !isRunning else { return SyncRunResult() }
        isRunning = true
        defer { isRunning = false }
        try Task.checkCancellation()

        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        let pullSummary = try await pullChanges(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        var hasIncompleteRemotePull = pullSummary.hasIncompleteRemotePull
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
        try Task.checkCancellation()
        let pushResult = try await pushPendingEntries(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        guard pushResult.didComplete else {
            return SyncRunResult(didPush: pushResult.didPush, hasIncompleteRemotePull: hasIncompleteRemotePull)
        }
        guard !pushResult.hasMorePendingEntries else {
            return SyncRunResult(
                didPush: pushResult.didPush,
                hasMorePendingEntries: true,
                hasIncompleteRemotePull: hasIncompleteRemotePull
            )
        }
        if pushResult.didPush {
            let summary = try await pullChanges(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            hasIncompleteRemotePull = summary.hasIncompleteRemotePull
        }
        return SyncRunResult(didPush: pushResult.didPush, hasIncompleteRemotePull: hasIncompleteRemotePull)
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

            if entry.ownerTokenIdentifier == nil, try canClaim(
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
            if entry.ownerTokenIdentifier == ownerTokenIdentifier, entry.status == .inFlight || entry.status == .failed {
                recorder.markPendingForRetry(entry, now: .now)
            }
        }

        if !state.hasBootstrappedSettingsExercises {
            try bootstrapSettingsExercisesForSync(
                ownerTokenIdentifier: ownerTokenIdentifier,
                candidates: bootstrapCandidates,
                context: context,
                now: .now
            )
            state.hasBootstrappedSettingsExercises = true
        }
        if !state.hasBootstrappedWorkoutGraph && completeWorkoutGraphBootstrap {
            let didCompleteWorkoutGraphBootstrap = try bootstrapWorkoutGraphForSync(
                ownerTokenIdentifier: ownerTokenIdentifier,
                includeOwnerlessCompletedWorkouts: includeOwnerlessCompletedWorkouts,
                context: context,
                now: .now
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
                now: .now
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

    private func pushPendingEntries(ownerTokenIdentifier: String, context: ModelContext) async throws -> SyncPushResult {
        let fetchedEntries = try recorder.pendingEntries(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )
        let hasMorePendingEntries = fetchedEntries.count > maxPendingPushEntriesPerRun
        let entries = fetchedEntries
            .sorted { lhs, rhs in
                let lhsRank = syncPushRank(for: lhs)
                let rhsRank = syncPushRank(for: rhs)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.updatedAt < rhs.updatedAt
            }
            .prefix(maxPendingPushEntriesPerRun)

        var needsSave = false
        var completedSinceLastSave = 0
        for entry in entries {
            try Task.checkCancellation()
            let logicalUpdatedAt = logicalFallbackTimestamp(for: entry)
            recorder.markInFlight(entry, now: .now)
            needsSave = true
            try Task.checkCancellation()

            do {
                let result = try await push(
                    entry: entry,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    fallbackTimestamp: logicalUpdatedAt,
                    context: context
                )
                try rewindCursorForIgnoredStaleResult(
                    result,
                    entry: entry,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context
                )
                recorder.removeCompleted(entry, context: context)
                needsSave = true
                completedSinceLastSave += 1
                if completedSinceLastSave >= 25 {
                    try context.save()
                    needsSave = false
                    completedSinceLastSave = 0
                }
            } catch {
                if let syncError = error as? SyncCoordinatorError, case .ownerMismatch = syncError {
                    context.delete(entry)
                    needsSave = true
                    completedSinceLastSave += 1
                    if completedSinceLastSave >= 25 {
                        try context.save()
                        needsSave = false
                        completedSinceLastSave = 0
                    }
                    continue
                }
                if entry.status == .inFlight {
                    recorder.markFailed(entry, message: error.localizedDescription, now: .now)
                    needsSave = true
                }
                if needsSave {
                    try context.save()
                }
                return SyncPushResult(didComplete: false, didPush: true)
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

    private func pullChanges(ownerTokenIdentifier: String, context: ModelContext) async throws -> SyncPullSummary {
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        var summary = SyncPullSummary()
        var hasMore = true
        var loggedExercisesCursorBlocked = false
        var loggedSetsCursorBlocked = false
        var pulledRemoteExerciseIDs = Set<UUID>()
        let allowsOwnerScopedSeedAdoption = !state.hasBootstrappedSettingsExercises
        var fetchCursors = SyncChangeCursors(
            userSettings: state.userSettingsCursor,
            exercises: state.exercisesCursor,
            workoutSessions: state.workoutSessionsCursor,
            loggedExercises: state.loggedExercisesCursor,
            loggedSets: state.loggedSetsCursor
        )

        while hasMore {
            let response = try await client.fetchChanges(
                cursors: fetchCursors,
                limit: 100
            )

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
                guard SyncConflictResolver.decision(
                    localUpdatedAt: settings.updatedAt,
                    localDeletedAt: settings.deletedAt,
                    incomingUpdatedAt: incomingUpdatedAt,
                    incomingDeletedAt: incomingDeletedAt,
                    allowsIncomingRestore: false
                ) == .applyIncoming else {
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
                guard SyncConflictResolver.decision(
                    localUpdatedAt: exercise.updatedAt,
                    localDeletedAt: exercise.deletedAt,
                    incomingUpdatedAt: incomingUpdatedAt,
                    incomingDeletedAt: incomingDeletedAt,
                    allowsIncomingRestore: false
                ) == .applyIncoming else {
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
        exercise.notes = record.notes
        exercise.isArchived = record.isArchived
        exercise.isSeeded = record.isSeeded
        exercise.createdAt = Date(timeIntervalSince1970: record.createdAt)
        exercise.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        exercise.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
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
                guard SyncConflictResolver.decision(
                    localUpdatedAt: session.updatedAt,
                    localDeletedAt: session.deletedAt,
                    incomingUpdatedAt: incomingUpdatedAt,
                    incomingDeletedAt: incomingDeletedAt,
                    allowsIncomingRestore: false
                ) == .applyIncoming else {
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
                    referenceNotes: record.referenceNotes,
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt,
                    healthLinkID: record.healthLinkID.flatMap(UUID.init(uuidString:)),
                    syncOwnerTokenIdentifier: ownerTokenIdentifier
                )
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
        session.createdAt = Date(timeIntervalSince1970: record.createdAt)
        session.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        session.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        session.healthLinkID = record.healthLinkID.flatMap(UUID.init(uuidString:))
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
                guard SyncConflictResolver.decision(
                    localUpdatedAt: loggedExercise.updatedAt,
                    localDeletedAt: loggedExercise.deletedAt,
                    incomingUpdatedAt: incomingUpdatedAt,
                    incomingDeletedAt: incomingDeletedAt,
                    allowsIncomingRestore: false
                ) == .applyIncoming else {
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
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt
                )
                loggedExercise.hasSnapshotMetadata = record.hasSnapshotMetadata
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
        loggedExercise.notes = record.notes
        loggedExercise.referenceNotes = record.referenceNotes
        loggedExercise.sourceLoggedExerciseID = record.sourceLoggedExerciseID.flatMap(UUID.init(uuidString:))
        loggedExercise.createdAt = Date(timeIntervalSince1970: record.createdAt)
        loggedExercise.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        loggedExercise.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
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
            guard let id = UUID(uuidString: record.clientId) else {
                recordAppliedCursor(record.serverUpdatedAt)
                continue
            }
            guard let loggedExerciseID = UUID(uuidString: record.loggedExerciseClientId),
                  let loggedExercise = try findLoggedExercise(id: loggedExerciseID, context: context) else {
                if record.deletedAt != nil {
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
                guard SyncConflictResolver.decision(
                    localUpdatedAt: set.updatedAt,
                    localDeletedAt: set.deletedAt,
                    incomingUpdatedAt: incomingUpdatedAt,
                    incomingDeletedAt: incomingDeletedAt,
                    allowsIncomingRestore: false
                ) == .applyIncoming else {
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
        set.loggedExercise = loggedExercise
        if !loggedExercise.sets.contains(where: { $0.id == set.id }) {
            loggedExercise.sets.append(set)
        }
    }

    private func canClaim(
        entry: SyncOutboxEntry,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> Bool {
        switch entry.entityKind {
        case .userSettings:
            guard let settings = try findUserSettings(id: entry.entityID, context: context) else {
                return false
            }
            return settings.syncOwnerTokenIdentifier == nil
                || settings.syncOwnerTokenIdentifier == ownerTokenIdentifier
        case .exercise:
            guard let exercise = try findExercise(id: entry.entityID, context: context) else {
                return false
            }
            return exercise.syncOwnerTokenIdentifier == nil
                || exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier
        case .workoutSession:
            guard let session = try findWorkoutSession(id: entry.entityID, context: context) else {
                return false
            }
            if session.syncOwnerTokenIdentifier == nil {
                return entry.isActive
            }
            return try canSyncWorkoutSession(session, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        case .loggedExercise:
            guard let session = try findLoggedExercise(id: entry.entityID, context: context)?.session else {
                return false
            }
            if session.syncOwnerTokenIdentifier == nil {
                return entry.isActive
            }
            return try canSyncWorkoutSession(session, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        case .loggedSet:
            guard let session = try findLoggedSet(id: entry.entityID, context: context)?.loggedExercise?.session else {
                return false
            }
            if session.syncOwnerTokenIdentifier == nil {
                return entry.isActive
            }
            return try canSyncWorkoutSession(session, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        default:
            return false
        }
    }

    private func canSyncWorkoutSession(
        _ session: WorkoutSession,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> Bool {
        if session.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            return true
        }
        guard session.syncOwnerTokenIdentifier == nil else {
            return false
        }
        return try canBootstrapOwnerlessWorkoutGraph(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
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
            canonical.notes = duplicate.notes
            canonical.isArchived = duplicate.isArchived
            canonical.updatedAt = duplicate.updatedAt
        }

        for loggedExercise in try context.fetch(FetchDescriptor<LoggedExercise>())
        where loggedExercise.exercise?.id == duplicateID {
            loggedExercise.exercise = canonical
        }
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
    case ownerMismatch(entityKind: SyncEntityKind, entityID: UUID)

    var errorDescription: String? {
        switch self {
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
}

private struct SyncPushResult {
    var didComplete: Bool
    var didPush: Bool
    var hasMorePendingEntries = false
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
        userSettings || exercises || workoutSessions || loggedExercises || loggedSets
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
