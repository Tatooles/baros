import Foundation
import SwiftData

@MainActor
struct SettingsMutationService {
    private let recorder = SyncOutboxRecorder()
    private let syncScheduler: SyncScheduler?

    init(syncScheduler: SyncScheduler? = nil) {
        self.syncScheduler = syncScheduler
    }

    func updateWeightUnit(
        _ newUnit: MeasurementUnit,
        settings: UserSettings,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        guard settings.weightUnit != newUnit else { return }
        try chooseWeightUnit(
            newUnit,
            settings: settings,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
    }

    /// Records the unit as the person's choice even when it matches the current
    /// value, so it wins over the unit a later sign-in would otherwise restore.
    func chooseWeightUnit(
        _ newUnit: MeasurementUnit,
        settings: UserSettings,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        let effectiveOwner = try mutationOwner(
            currentOwner: settings.syncOwnerTokenIdentifier,
            requestedOwner: ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        )

        settings.syncOwnerTokenIdentifier = effectiveOwner ?? settings.syncOwnerTokenIdentifier
        settings.weightUnitRaw = newUnit.rawValue
        settings.touch(now: now)
        try recorder.recordUpdate(
            entityKind: .userSettings,
            entityID: settings.id,
            ownerTokenIdentifier: effectiveOwner,
            context: context,
            now: now
        )
        try context.save()
        syncScheduler?.requestSync()
    }

    func updateDefaultRestTimerSeconds(
        _ seconds: Int,
        settings: UserSettings,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        guard settings.defaultRestTimerSeconds != seconds else { return }
        let effectiveOwner = try mutationOwner(
            currentOwner: settings.syncOwnerTokenIdentifier,
            requestedOwner: ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        )

        settings.syncOwnerTokenIdentifier = effectiveOwner ?? settings.syncOwnerTokenIdentifier
        settings.defaultRestTimerSeconds = seconds
        settings.touch(now: now)
        try recorder.recordUpdate(
            entityKind: .userSettings,
            entityID: settings.id,
            ownerTokenIdentifier: effectiveOwner,
            context: context,
            now: now
        )
        try context.save()
        syncScheduler?.requestSync()
    }

    private func mutationOwner(currentOwner: String?, requestedOwner: String?) throws -> String? {
        guard let currentOwner else { return requestedOwner }
        guard let requestedOwner, requestedOwner != currentOwner else { return currentOwner }
        throw SyncMutationOwnershipError.ownerMismatch
    }
}

enum SyncMutationOwnershipError: Error, Equatable {
    case ownerMismatch
}
