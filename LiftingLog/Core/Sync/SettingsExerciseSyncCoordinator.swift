import Foundation
import SwiftData

@MainActor
final class SettingsExerciseSyncCoordinator {
    private let client: any SettingsExerciseSyncClient & Sendable
    private let recorder = SyncOutboxRecorder()
    private var isRunning = false

    init(client: any SettingsExerciseSyncClient & Sendable) {
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
        let didPullBeforePush: Bool
        if state.hasBootstrappedSettingsExercises {
            bootstrapScope = .allOwned
            didPullBeforePush = false
        } else {
            let summary = try await pullChanges(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            try Task.checkCancellation()
            bootstrapScope = summary.hasRemoteRecords ? .unownedOnly : .allOwned
            didPullBeforePush = true
        }

        try prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context, bootstrapScope: bootstrapScope)
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
        bootstrapScope: BootstrapScope = .allOwned
    ) throws {
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
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
            guard entry.entityKind == .userSettings || entry.entityKind == .exercise else {
                continue
            }

            if entry.ownerTokenIdentifier == nil, try canClaim(
                entry: entry,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            ) {
                entry.ownerTokenIdentifier = ownerTokenIdentifier
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

    private func pushPendingEntries(ownerTokenIdentifier: String, context: ModelContext) async throws -> SyncPushResult {
        let entries = try recorder.pendingEntries(context: context)
            .filter { entry in
                entry.ownerTokenIdentifier == ownerTokenIdentifier
                    && (entry.entityKind == .userSettings || entry.entityKind == .exercise)
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
                return SyncPushResult(didComplete: false, didPush: true)
            }
        }

        return SyncPushResult(didComplete: true, didPush: !entries.isEmpty)
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
                throw SettingsExerciseSyncCoordinatorError.ownerMismatch(entityKind: .userSettings, entityID: entry.entityID)
            }
            return try await client.upsertUserSettings(SyncPayloadMapper.userSettingsPayload(from: settings))
        case (.exercise, .create), (.exercise, .update):
            guard let exercise = try findExercise(id: entry.entityID, context: context) else {
                return try await client.tombstone(entityKind: .exercise, clientId: entry.entityID, deletedAt: fallbackTimestamp)
            }
            guard exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SettingsExerciseSyncCoordinatorError.ownerMismatch(entityKind: .exercise, entityID: entry.entityID)
            }
            return try await client.upsertExercise(SyncPayloadMapper.exercisePayload(from: exercise))
        case (.userSettings, .delete):
            let settings = try findUserSettings(id: entry.entityID, context: context)
            if let settings, settings.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SettingsExerciseSyncCoordinatorError.ownerMismatch(entityKind: .userSettings, entityID: entry.entityID)
            }
            let deletedAt = settings?.deletedAt ?? fallbackTimestamp
            return try await client.tombstone(entityKind: .userSettings, clientId: entry.entityID, deletedAt: deletedAt)
        case (.exercise, .delete):
            let exercise = try findExercise(id: entry.entityID, context: context)
            if let exercise, exercise.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SettingsExerciseSyncCoordinatorError.ownerMismatch(entityKind: .exercise, entityID: entry.entityID)
            }
            let deletedAt = exercise?.deletedAt ?? fallbackTimestamp
            return try await client.tombstone(entityKind: .exercise, clientId: entry.entityID, deletedAt: deletedAt)
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

    private func pullChanges(ownerTokenIdentifier: String, context: ModelContext) async throws -> SyncPullSummary {
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        var summary = SyncPullSummary()
        var hasMore = true

        while hasMore {
            let response = try await client.fetchChanges(
                cursors: SyncChangeCursors(
                    userSettings: state.userSettingsCursor,
                    exercises: state.exercisesCursor
                ),
                limit: 100
            )

            summary.record(response)
            try apply(userSettingsRecords: response.userSettings, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            try apply(exerciseRecords: response.exercises, ownerTokenIdentifier: ownerTokenIdentifier, context: context)

            state.userSettingsCursor = max(state.userSettingsCursor, response.cursors.userSettings)
            state.exercisesCursor = max(state.exercisesCursor, response.cursors.exercises)
            try context.save()

            hasMore = response.hasMore.userSettings || response.hasMore.exercises
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

                guard incomingDeletedAt == nil else { continue }

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
                    deletedAt: nil
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
        default:
            return false
        }
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

enum SettingsExerciseSyncCoordinatorError: LocalizedError {
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

    var hasRemoteRecords: Bool {
        hasUserSettings || hasExercises
    }

    mutating func record(_ response: SyncFetchChangesResponse) {
        hasUserSettings = hasUserSettings || !response.userSettings.isEmpty
        hasExercises = hasExercises || !response.exercises.isEmpty
    }
}

private struct SyncPushResult {
    var didComplete: Bool
    var didPush: Bool
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
