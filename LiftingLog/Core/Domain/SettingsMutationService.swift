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
        let previousUnit = settings.weightUnit
        guard previousUnit != newUnit else { return }
        let effectiveOwner = try mutationOwner(
            currentOwner: settings.syncOwnerTokenIdentifier,
            requestedOwner: ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        )

        let sets = try context.fetch(FetchDescriptor<LoggedSet>())
        for set in sets where !set.isDeleted && canApplyWeightUnitChange(to: set, ownerTokenIdentifier: effectiveOwner) {
            var didConvertSet = false
            if let weight = set.weight {
                set.weight = previousUnit.convert(weight, to: newUnit)
                didConvertSet = true
            }
            if let placeholderWeight = set.placeholderWeight {
                set.placeholderWeight = previousUnit.convert(placeholderWeight, to: newUnit)
                didConvertSet = true
            }
            if didConvertSet {
                set.touch(now: now)
                if set.loggedExercise?.session?.status != .active {
                    try recordWorkoutGraphParentsForExplicitSetIntent(
                        set,
                        ownerTokenIdentifier: effectiveOwner,
                        context: context,
                        now: now
                    )
                    try recorder.recordUpdate(
                        entityKind: .loggedSet,
                        entityID: set.id,
                        ownerTokenIdentifier: effectiveOwner,
                        context: context,
                        now: now
                    )
                }
            }
        }

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

    private func canApplyWeightUnitChange(to set: LoggedSet, ownerTokenIdentifier: String?) -> Bool {
        guard let session = set.loggedExercise?.session else {
            return ownerTokenIdentifier == nil
        }
        guard let ownerTokenIdentifier else {
            return session.syncOwnerTokenIdentifier == nil
        }
        return session.syncOwnerTokenIdentifier == nil
            || session.syncOwnerTokenIdentifier == ownerTokenIdentifier
    }

    private func recordWorkoutGraphParentsForExplicitSetIntent(
        _ set: LoggedSet,
        ownerTokenIdentifier: String?,
        context: ModelContext,
        now: Date
    ) throws {
        guard let ownerTokenIdentifier,
              let loggedExercise = set.loggedExercise,
              let session = loggedExercise.session else {
            return
        }

        if session.syncOwnerTokenIdentifier == nil {
            session.syncOwnerTokenIdentifier = ownerTokenIdentifier
            try recorder.recordUpdate(
                entityKind: .workoutSession,
                entityID: session.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }
        guard session.syncOwnerTokenIdentifier == ownerTokenIdentifier else { return }
        try recorder.recordUpdate(
            entityKind: .loggedExercise,
            entityID: loggedExercise.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
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
