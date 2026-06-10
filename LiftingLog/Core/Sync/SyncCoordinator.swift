import Foundation
import SwiftData

@MainActor
final class SyncCoordinator {
    private let client: any SyncClient & Sendable
    private let recorder = SyncOutboxRecorder()
    private var isRunning = false

    init(client: any SyncClient & Sendable) {
        self.client = client
    }

    func run(ownerTokenIdentifier: String?, context: ModelContext) async throws {
        guard let ownerTokenIdentifier else { return }
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        try Task.checkCancellation()

        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        let bootstrapScope: BootstrapScope
        let includeOwnerlessCompletedWorkouts: Bool
        let didPullBeforePush: Bool
        if state.hasBootstrappedSettingsExercises && state.hasBootstrappedWorkoutGraph {
            bootstrapScope = .allOwned
            includeOwnerlessCompletedWorkouts = false
            didPullBeforePush = false
        } else {
            let summary = try await pullChanges(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            try Task.checkCancellation()
            bootstrapScope = summary.hasRemoteSettingsExerciseRecords ? .unownedOnly : .allOwned
            includeOwnerlessCompletedWorkouts = !summary.hasRemoteWorkoutGraphRecords
            didPullBeforePush = true
        }

        try prepareForSync(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            bootstrapScope: bootstrapScope,
            includeOwnerlessCompletedWorkouts: includeOwnerlessCompletedWorkouts
        )
        try Task.checkCancellation()
        let pushResult = try await pushPendingEntries(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        guard pushResult.didComplete else { return }
        if pushResult.didPush || !didPullBeforePush {
            _ = try await pullChanges(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        }
    }

    func prepareForSync(
        ownerTokenIdentifier: String,
        context: ModelContext,
        bootstrapScope: BootstrapScope = .allOwned,
        includeOwnerlessCompletedWorkouts: Bool = true
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

        for entry in try context.fetch(FetchDescriptor<SyncOutboxEntry>()) {
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
        if !state.hasBootstrappedWorkoutGraph {
            let didCompleteWorkoutGraphBootstrap = try bootstrapWorkoutGraphForSync(
                ownerTokenIdentifier: ownerTokenIdentifier,
                includeOwnerlessCompletedWorkouts: includeOwnerlessCompletedWorkouts,
                context: context,
                now: .now
            )
            if didCompleteWorkoutGraphBootstrap {
                state.hasBootstrappedWorkoutGraph = true
            }
        }
        if hadBootstrappedWorkoutGraph && state.loggedSetsCursor == 0 {
            try backfillOwnedCompletedLoggedSetsForSync(
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: .now
            )
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
        let cursorStates = try context.fetch(FetchDescriptor<SyncCursorState>())
        if cursorStates.contains(where: { $0.ownerTokenIdentifier != ownerTokenIdentifier }) {
            return false
        }

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        if settings.contains(where: { $0.syncOwnerTokenIdentifier != nil && $0.syncOwnerTokenIdentifier != ownerTokenIdentifier }) {
            return false
        }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        if exercises.contains(where: { $0.syncOwnerTokenIdentifier != nil && $0.syncOwnerTokenIdentifier != ownerTokenIdentifier }) {
            return false
        }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        if sessions.contains(where: { $0.syncOwnerTokenIdentifier != nil && $0.syncOwnerTokenIdentifier != ownerTokenIdentifier }) {
            return false
        }

        return true
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
        guard let entry = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            .first(where: {
                $0.entityKind == entityKind
                    && $0.entityID == entityID
                    && $0.ownerTokenIdentifier == nil
                    && $0.isActive
                    && $0.operation != nil
            }) else {
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
        let entries = try recorder.pendingEntries(context: context)
            .filter { entry in
                entry.ownerTokenIdentifier == ownerTokenIdentifier
            }
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

        for entry in entries {
            try Task.checkCancellation()
            let logicalUpdatedAt = logicalFallbackTimestamp(for: entry)
            recorder.markInFlight(entry, now: .now)
            try context.save()
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
                try context.save()
            } catch {
                if entry.status == .inFlight {
                    recorder.markFailed(entry, message: error.localizedDescription, now: .now)
                    try context.save()
                }
                if error is SyncCoordinatorError {
                    continue
                }
                return SyncPushResult(didComplete: false, didPush: true)
            }
        }

        return SyncPushResult(didComplete: true, didPush: !entries.isEmpty)
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
        try context.fetch(FetchDescriptor<UserSettings>())
            .first { $0.id == id }
    }

    private func findExercise(id: UUID, context: ModelContext) throws -> Exercise? {
        try context.fetch(FetchDescriptor<Exercise>())
            .first { $0.id == id }
    }

    private func findWorkoutSession(id: UUID, context: ModelContext) throws -> WorkoutSession? {
        try context.fetch(FetchDescriptor<WorkoutSession>())
            .first { $0.id == id }
    }

    private func findLoggedExercise(id: UUID, context: ModelContext) throws -> LoggedExercise? {
        try context.fetch(FetchDescriptor<LoggedExercise>())
            .first { $0.id == id }
    }

    private func findLoggedSet(id: UUID, context: ModelContext) throws -> LoggedSet? {
        try context.fetch(FetchDescriptor<LoggedSet>())
            .first { $0.id == id }
    }

    private func pullChanges(ownerTokenIdentifier: String, context: ModelContext) async throws -> SyncPullSummary {
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        var summary = SyncPullSummary()
        var hasMore = true

        while hasMore {
            let response = try await client.fetchChanges(
                cursors: SyncChangeCursors(
                    userSettings: state.userSettingsCursor,
                    exercises: state.exercisesCursor,
                    workoutSessions: state.workoutSessionsCursor,
                    loggedExercises: state.loggedExercisesCursor,
                    loggedSets: state.loggedSetsCursor
                ),
                limit: 100
            )

            summary.record(response)
            try apply(userSettingsRecords: response.userSettings, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            try apply(exerciseRecords: response.exercises, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            let appliedWorkoutSessionCursor = try apply(
                workoutSessionRecords: response.workoutSessions,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
            let loggedExerciseApplyResult = try apply(
                loggedExerciseRecords: response.loggedExercises,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
            let loggedSetApplyResult = try apply(
                loggedSetRecords: response.loggedSets,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )

            state.userSettingsCursor = max(state.userSettingsCursor, response.cursors.userSettings)
            state.exercisesCursor = max(state.exercisesCursor, response.cursors.exercises)
            if let appliedWorkoutSessionCursor {
                state.workoutSessionsCursor = max(state.workoutSessionsCursor, appliedWorkoutSessionCursor)
            }
            if let appliedLoggedExerciseCursor = loggedExerciseApplyResult.appliedCursor {
                state.loggedExercisesCursor = max(state.loggedExercisesCursor, appliedLoggedExerciseCursor)
            }
            if let appliedLoggedSetCursor = loggedSetApplyResult.appliedCursor {
                state.loggedSetsCursor = max(state.loggedSetsCursor, appliedLoggedSetCursor)
            }
            try context.save()

            let deferredWorkoutChild = loggedExerciseApplyResult.deferredMissingParent || loggedSetApplyResult.deferredMissingParent
            hasMore = !deferredWorkoutChild
                && (response.hasMore.userSettings
                    || response.hasMore.exercises
                    || response.hasMore.workoutSessions
                    || response.hasMore.loggedExercises
                    || response.hasMore.loggedSets)
        }

        return summary
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
        context: ModelContext
    ) throws {
        for record in records {
            guard let id = UUID(uuidString: record.clientId) else { continue }
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
    ) throws -> Double? {
        var maxAppliedServerUpdatedAt: Double?
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
            }
            maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
        }
        return maxAppliedServerUpdatedAt
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
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> WorkoutChildApplyResult {
        var maxAppliedServerUpdatedAt: Double?
        for record in records {
            guard let id = UUID(uuidString: record.clientId) else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            guard let sessionID = UUID(uuidString: record.sessionClientId),
                  let session = try findWorkoutSession(id: sessionID, context: context) else {
                if record.deletedAt != nil {
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                    continue
                }
                return WorkoutChildApplyResult(
                    appliedCursor: maxAppliedServerUpdatedAt,
                    deferredMissingParent: true
                )
            }
            guard session.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
            let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
            let exercise: Exercise?
            if let exerciseClientId = record.exerciseClientId,
               let exerciseID = UUID(uuidString: exerciseClientId) {
                guard let resolvedExercise = try findExercise(id: exerciseID, context: context) else {
                    guard incomingDeletedAt == nil else {
                        maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                        continue
                    }
                    return WorkoutChildApplyResult(
                        appliedCursor: maxAppliedServerUpdatedAt,
                        deferredMissingParent: true
                    )
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
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                    continue
                }
                apply(record, to: loggedExercise, session: session, exercise: exercise)
            } else {
                guard incomingDeletedAt == nil else {
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
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
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt
                )
                loggedExercise.hasSnapshotMetadata = record.hasSnapshotMetadata
                loggedExercise.session = session
                session.loggedExercises.append(loggedExercise)
                context.insert(loggedExercise)
            }
            maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
        }
        return WorkoutChildApplyResult(appliedCursor: maxAppliedServerUpdatedAt)
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
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> WorkoutChildApplyResult {
        var maxAppliedServerUpdatedAt: Double?
        for record in records {
            guard let id = UUID(uuidString: record.clientId) else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            guard let loggedExerciseID = UUID(uuidString: record.loggedExerciseClientId),
                  let loggedExercise = try findLoggedExercise(id: loggedExerciseID, context: context) else {
                if record.deletedAt != nil {
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                    continue
                }
                return WorkoutChildApplyResult(
                    appliedCursor: maxAppliedServerUpdatedAt,
                    deferredMissingParent: true
                )
            }
            guard loggedExercise.session?.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
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
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                    continue
                }
                apply(record, to: set, loggedExercise: loggedExercise)
            } else {
                guard incomingDeletedAt == nil else {
                    maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                    continue
                }
                let set = LoggedSet(
                    id: id,
                    orderIndex: record.orderIndex,
                    weight: record.weight,
                    reps: record.reps,
                    rpe: record.rpe,
                    placeholderWeight: record.placeholderWeight,
                    placeholderReps: record.placeholderReps,
                    placeholderRPE: record.placeholderRPE,
                    kind: SetKind(rawValue: record.kindRaw) ?? .working,
                    isCompleted: record.isCompleted,
                    completedAt: record.completedAt.map(Date.init(timeIntervalSince1970:)),
                    notes: record.notes,
                    createdAt: Date(timeIntervalSince1970: record.createdAt),
                    updatedAt: incomingUpdatedAt,
                    deletedAt: incomingDeletedAt,
                    healthLinkID: record.healthLinkID.flatMap(UUID.init(uuidString:))
                )
                set.loggedExercise = loggedExercise
                loggedExercise.sets.append(set)
                context.insert(set)
            }
            maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
        }
        return WorkoutChildApplyResult(appliedCursor: maxAppliedServerUpdatedAt)
    }

    private func apply(_ record: LoggedSetSyncRecord, to set: LoggedSet, loggedExercise: LoggedExercise) {
        set.orderIndex = record.orderIndex
        set.weight = record.weight
        set.reps = record.reps
        set.rpe = record.rpe
        set.placeholderWeight = record.placeholderWeight
        set.placeholderReps = record.placeholderReps
        set.placeholderRPE = record.placeholderRPE
        set.kindRaw = record.kindRaw
        set.isCompleted = record.isCompleted
        set.completedAt = record.completedAt.map(Date.init(timeIntervalSince1970:))
        set.notes = record.notes
        set.createdAt = Date(timeIntervalSince1970: record.createdAt)
        set.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        set.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        set.healthLinkID = record.healthLinkID.flatMap(UUID.init(uuidString:))
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

    private func adoptableSeedExercise(
        seedIdentifier: String,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> Exercise? {
        try context.fetch(FetchDescriptor<Exercise>())
            .first { exercise in
                (exercise.syncOwnerTokenIdentifier == nil || exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier)
                    && exercise.isSeeded
                    && exercise.seedIdentifier == seedIdentifier
            }
    }

    private func hasActiveOutboxEntry(
        entityKind: SyncEntityKind,
        entityID: UUID,
        context: ModelContext
    ) throws -> Bool {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            .contains { entry in
                entry.entityKind == entityKind
                    && entry.entityID == entityID
                    && entry.isActive
                    && entry.operation != nil
            }
    }

    private func retargetOutboxEntries(
        entityKind: SyncEntityKind,
        from oldID: UUID,
        to newID: UUID,
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws {
        for entry in try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            where entry.entityKind == entityKind && entry.entityID == oldID && entry.isActive {
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
    var hasWorkoutSessions = false
    var hasLoggedExercises = false
    var hasLoggedSets = false

    var hasRemoteSettingsExerciseRecords: Bool {
        hasUserSettings || hasExercises
    }

    var hasRemoteWorkoutGraphRecords: Bool {
        hasWorkoutSessions || hasLoggedExercises || hasLoggedSets
    }

    mutating func record(_ response: SyncFetchChangesResponse) {
        hasUserSettings = hasUserSettings || !response.userSettings.isEmpty
        hasExercises = hasExercises || !response.exercises.isEmpty
        hasWorkoutSessions = hasWorkoutSessions || !response.workoutSessions.isEmpty
        hasLoggedExercises = hasLoggedExercises || !response.loggedExercises.isEmpty
        hasLoggedSets = hasLoggedSets || !response.loggedSets.isEmpty
    }
}

private struct SyncPushResult {
    var didComplete: Bool
    var didPush: Bool
}

private struct WorkoutChildApplyResult {
    var appliedCursor: Double?
    var deferredMissingParent = false
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
