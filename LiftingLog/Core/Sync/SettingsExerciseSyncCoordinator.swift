import Foundation
import SwiftData

@MainActor
final class SettingsExerciseSyncCoordinator {
    private let client: SettingsExerciseSyncClient
    private let recorder = SyncOutboxRecorder()
    private var isRunning = false

    init(client: SettingsExerciseSyncClient) {
        self.client = client
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
