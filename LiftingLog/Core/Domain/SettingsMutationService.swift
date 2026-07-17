import Foundation
import SwiftData

@MainActor
struct SettingsMutationService {
    private let syncOutboxTransaction: SyncOutboxTransaction?

    init(syncOutboxTransaction: SyncOutboxTransaction? = nil) {
        self.syncOutboxTransaction = syncOutboxTransaction
    }

    func updateWeightUnit(
        _ newUnit: MeasurementUnit,
        settings: UserSettings,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        guard settings.weightUnit != newUnit else { return }
        try performUpdate(
            settings: settings,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        ) {
            settings.weightUnitRaw = newUnit.rawValue
            settings.touch(now: now)
        }
    }

    func updateDefaultRestTimerSeconds(
        _ seconds: Int,
        settings: UserSettings,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        guard settings.defaultRestTimerSeconds != seconds else { return }
        try performUpdate(
            settings: settings,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        ) {
            settings.defaultRestTimerSeconds = seconds
            settings.touch(now: now)
        }
    }

    private func performUpdate(
        settings: UserSettings,
        ownerTokenIdentifier: String?,
        context: ModelContext,
        now: Date,
        mutation: () -> Void
    ) throws {
        let requestedOwner = ownerTokenIdentifier ?? syncOutboxTransaction?.currentOwnerTokenIdentifier

        guard let requestedOwner else {
            guard settings.syncOwnerTokenIdentifier == nil else {
                throw SyncMutationOwnershipError.ownerMismatch
            }
            mutation()
            try context.save()
            return
        }

        guard let syncOutboxTransaction else {
            throw SyncOutboxTransactionError.currentOwnerMismatch
        }

        try syncOutboxTransaction.perform(ownerTokenIdentifier: requestedOwner) { actions in
            try actions.update(.userSettings(settings), now: now) { _ in
                let effectiveOwner = try mutationOwner(
                    currentOwner: settings.syncOwnerTokenIdentifier,
                    requestedOwner: requestedOwner
                )
                settings.syncOwnerTokenIdentifier = effectiveOwner
                mutation()
            }
        }
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
