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

        try prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        let didCompletePush = try await pushPendingEntries(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        guard didCompletePush else { return }
        try await pullChanges(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
    }

    func prepareForSync(ownerTokenIdentifier: String, context: ModelContext) throws {
        for settings in try context.fetch(FetchDescriptor<UserSettings>()) {
            if settings.syncOwnerTokenIdentifier == nil {
                settings.syncOwnerTokenIdentifier = ownerTokenIdentifier
            }
        }

        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            if exercise.syncOwnerTokenIdentifier == nil {
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

        try context.save()
    }

    private func pushPendingEntries(ownerTokenIdentifier: String, context: ModelContext) async throws -> Bool {
        let entries = try recorder.pendingEntries(context: context)
            .filter { entry in
                entry.ownerTokenIdentifier == ownerTokenIdentifier
                    && (entry.entityKind == .userSettings || entry.entityKind == .exercise)
            }

        for entry in entries {
            let logicalUpdatedAt = logicalFallbackTimestamp(for: entry)
            recorder.markInFlight(entry, now: .now)
            try context.save()

            do {
                try await push(
                    entry: entry,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    fallbackTimestamp: logicalUpdatedAt,
                    context: context
                )
                recorder.removeCompleted(entry, context: context)
                try context.save()
            } catch {
                if entry.status == .inFlight {
                    recorder.markFailed(entry, message: error.localizedDescription, now: .now)
                    try context.save()
                }
                return false
            }
        }

        return true
    }

    private func logicalFallbackTimestamp(for entry: SyncOutboxEntry) -> Date {
        return entry.hasBeenAttempted ? entry.createdAt : entry.updatedAt
    }

    private func push(
        entry: SyncOutboxEntry,
        ownerTokenIdentifier: String,
        fallbackTimestamp: Date,
        context: ModelContext
    ) async throws {
        guard let entityKind = entry.entityKind, let operation = entry.operation else { return }

        switch (entityKind, operation) {
        case (.userSettings, .create), (.userSettings, .update):
            guard let settings = try findUserSettings(id: entry.entityID, context: context) else {
                _ = try await client.tombstone(entityKind: .userSettings, clientId: entry.entityID, deletedAt: fallbackTimestamp)
                return
            }
            guard settings.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SettingsExerciseSyncCoordinatorError.ownerMismatch(entityKind: .userSettings, entityID: entry.entityID)
            }
            _ = try await client.upsertUserSettings(SyncPayloadMapper.userSettingsPayload(from: settings))
        case (.exercise, .create), (.exercise, .update):
            guard let exercise = try findExercise(id: entry.entityID, context: context) else {
                _ = try await client.tombstone(entityKind: .exercise, clientId: entry.entityID, deletedAt: fallbackTimestamp)
                return
            }
            guard exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SettingsExerciseSyncCoordinatorError.ownerMismatch(entityKind: .exercise, entityID: entry.entityID)
            }
            _ = try await client.upsertExercise(SyncPayloadMapper.exercisePayload(from: exercise))
        case (.userSettings, .delete):
            let settings = try findUserSettings(id: entry.entityID, context: context)
            if let settings, settings.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SettingsExerciseSyncCoordinatorError.ownerMismatch(entityKind: .userSettings, entityID: entry.entityID)
            }
            let deletedAt = settings?.deletedAt ?? fallbackTimestamp
            _ = try await client.tombstone(entityKind: .userSettings, clientId: entry.entityID, deletedAt: deletedAt)
        case (.exercise, .delete):
            let exercise = try findExercise(id: entry.entityID, context: context)
            if let exercise, exercise.syncOwnerTokenIdentifier != ownerTokenIdentifier {
                throw SettingsExerciseSyncCoordinatorError.ownerMismatch(entityKind: .exercise, entityID: entry.entityID)
            }
            let deletedAt = exercise?.deletedAt ?? fallbackTimestamp
            _ = try await client.tombstone(entityKind: .exercise, clientId: entry.entityID, deletedAt: deletedAt)
        default:
            return
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

    private func pullChanges(ownerTokenIdentifier: String, context: ModelContext) async throws {
        let state = try SyncCursorState.state(for: ownerTokenIdentifier, context: context)
        var hasMore = true

        while hasMore {
            let response = try await client.fetchChanges(
                cursors: SyncChangeCursors(
                    userSettings: state.userSettingsCursor,
                    exercises: state.exercisesCursor
                ),
                limit: 100
            )

            try apply(userSettingsRecords: response.userSettings, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            try apply(exerciseRecords: response.exercises, ownerTokenIdentifier: ownerTokenIdentifier, context: context)

            state.userSettingsCursor = response.cursors.userSettings
            state.exercisesCursor = response.cursors.exercises
            try context.save()

            hasMore = response.hasMore.userSettings || response.hasMore.exercises
        }
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
            } else if incomingDeletedAt == nil {
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
