import Foundation
import SwiftData

@MainActor
final class SettingsExerciseSyncCoordinator {
    nonisolated(unsafe) private let client: SettingsExerciseSyncClient
    private let recorder = SyncOutboxRecorder()
    private var isRunning = false

    init(client: SettingsExerciseSyncClient) {
        self.client = client
    }

    func run(ownerTokenIdentifier: String?, context: ModelContext) async throws {
        guard let ownerTokenIdentifier else { return }
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        try prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        try await pushPendingEntries(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
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
            if entry.ownerTokenIdentifier == ownerTokenIdentifier, entry.status == .inFlight {
                recorder.markPendingForRetry(entry, now: .now)
            }
        }

        try context.save()
    }

    private func pushPendingEntries(ownerTokenIdentifier: String, context: ModelContext) async throws {
        let entries = try recorder.pendingEntries(context: context)
            .filter { entry in
                entry.ownerTokenIdentifier == ownerTokenIdentifier
                    && (entry.entityKind == .userSettings || entry.entityKind == .exercise)
            }

        for entry in entries {
            recorder.markInFlight(entry, now: .now)
            try context.save()

            do {
                try await push(entry: entry, context: context)
                recorder.removeCompleted(entry, context: context)
                try context.save()
            } catch {
                recorder.markFailed(entry, message: error.localizedDescription, now: .now)
                try context.save()
                break
            }
        }
    }

    private func push(entry: SyncOutboxEntry, context: ModelContext) async throws {
        guard let entityKind = entry.entityKind, let operation = entry.operation else { return }

        switch (entityKind, operation) {
        case (.userSettings, .create), (.userSettings, .update):
            guard let settings = try findUserSettings(id: entry.entityID, context: context) else {
                _ = try await client.tombstone(entityKind: .userSettings, clientId: entry.entityID, deletedAt: entry.updatedAt)
                return
            }
            _ = try await client.upsertUserSettings(SyncPayloadMapper.userSettingsPayload(from: settings))
        case (.exercise, .create), (.exercise, .update):
            guard let exercise = try findExercise(id: entry.entityID, context: context) else {
                _ = try await client.tombstone(entityKind: .exercise, clientId: entry.entityID, deletedAt: entry.updatedAt)
                return
            }
            _ = try await client.upsertExercise(SyncPayloadMapper.exercisePayload(from: exercise))
        case (.userSettings, .delete):
            let deletedAt = try findUserSettings(id: entry.entityID, context: context)?.deletedAt ?? entry.updatedAt
            _ = try await client.tombstone(entityKind: .userSettings, clientId: entry.entityID, deletedAt: deletedAt)
        case (.exercise, .delete):
            let deletedAt = try findExercise(id: entry.entityID, context: context)?.deletedAt ?? entry.updatedAt
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
