import Foundation
import SwiftData

@MainActor
struct ExerciseMutationService {
    private let recorder = SyncOutboxRecorder()

    private let syncScheduler: SyncScheduler?

    init(syncScheduler: SyncScheduler? = nil) {
        self.syncScheduler = syncScheduler
    }

    @discardableResult
    func createExercise(
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscle: String,
        notes: String,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws -> Exercise {
        let effectiveOwner = ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        let exercise = Exercise(
            name: name,
            category: category,
            equipment: equipment,
            primaryMuscle: primaryMuscle,
            notes: notes,
            syncOwnerTokenIdentifier: effectiveOwner,
            createdAt: now,
            updatedAt: now
        )
        context.insert(exercise)
        try recorder.recordCreate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: effectiveOwner,
            context: context,
            now: now
        )
        try context.save()
        syncScheduler?.requestSync()
        return exercise
    }

    func updateExercise(
        _ exercise: Exercise,
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscle: String,
        notes: String,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        guard exercise.name != name
            || exercise.category != category
            || exercise.equipment != equipment
            || exercise.primaryMuscle != primaryMuscle
            || exercise.notes != notes else {
            return
        }

        let effectiveOwner = try mutationOwner(
            currentOwner: exercise.syncOwnerTokenIdentifier,
            requestedOwner: ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        )
        exercise.syncOwnerTokenIdentifier = effectiveOwner ?? exercise.syncOwnerTokenIdentifier
        exercise.update(
            name: name,
            category: category,
            equipment: equipment,
            primaryMuscle: primaryMuscle,
            notes: notes
        )
        exercise.touch(now: now)
        try recorder.recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: effectiveOwner,
            context: context,
            now: now
        )
        try context.save()
        syncScheduler?.requestSync()
    }

    func removeExercise(
        _ exercise: Exercise,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try changeLibraryState(exercise, restoring: false, owner: ownerTokenIdentifier,
                               context: context, now: now, save: save)
    }

    func restoreExercise(
        _ exercise: Exercise,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try changeLibraryState(exercise, restoring: true, owner: ownerTokenIdentifier,
                               context: context, now: now, save: save)
    }

    private func changeLibraryState(
        _ exercise: Exercise, restoring: Bool, owner: String?, context: ModelContext,
        now: Date, save: (ModelContext) throws -> Void
    ) throws {
        let owner = owner ?? syncScheduler?.currentOwnerTokenIdentifier
        // Library actions never claim records belonging to a different local owner.
        guard exercise.isVisible(to: owner), !exercise.isDeleted else {
            throw SyncMutationOwnershipError.ownerMismatch
        }
        guard exercise.isArchived == restoring else { return }
        if restoring {
            let collision = try context.fetch(FetchDescriptor<Exercise>()).contains {
                $0.id != exercise.id && $0.isVisible(to: owner)
                    && $0.hasSameActiveIdentity(name: exercise.name, equipment: exercise.equipment)
            }
            guard !collision else { throw LibraryError.activeDuplicate }
        }

        let archived = exercise.isArchived
        let deletedAt = exercise.deletedAt
        let updatedAt = exercise.updatedAt
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>()).filter {
            $0.entityKind == .exercise && $0.entityID == exercise.id
                && $0.ownerTokenIdentifier == owner
        }
        // Only these fields are changed by recordUpdate/recordDelete.
        let restoreEntries = entries.map { entry in
            let operation = entry.operationRaw, status = entry.statusRaw
            let created = entry.createdAt, updated = entry.updatedAt
            let error = entry.lastErrorMessage
            return {
                if entry.isDeleted {
                    context.insert(SyncOutboxEntry(
                        id: entry.id, entityKind: .exercise, entityID: entry.entityID,
                        operation: SyncOperation(rawValue: operation)!,
                        status: SyncOutboxStatus(rawValue: status)!,
                        ownerTokenIdentifier: entry.ownerTokenIdentifier,
                        createdAt: created, updatedAt: updated,
                        lastAttemptAt: entry.lastAttemptAt, attemptCount: entry.attemptCount,
                        lastErrorMessage: error
                    ))
                    return
                }
                entry.operationRaw = operation
                entry.statusRaw = status
                entry.createdAt = created
                entry.updatedAt = updated
                entry.lastErrorMessage = error
            }
        }
        do {
            let outcome: ExerciseRemovalOutcome
            if restoring {
                exercise.isArchived = false
                exercise.touch(now: now)
                outcome = .archived
            } else {
                outcome = try exercise.archiveOrDelete(context: context, now: now)
            }
            if case .deleted = outcome {
                try recorder.recordDelete(entityKind: .exercise, entityID: exercise.id,
                    ownerTokenIdentifier: owner, context: context, now: now)
            } else {
                try recorder.recordUpdate(entityKind: .exercise, entityID: exercise.id,
                    ownerTokenIdentifier: owner, context: context, now: now)
            }
            try save(context)
        } catch {
            exercise.isArchived = archived
            exercise.deletedAt = deletedAt
            exercise.updatedAt = updatedAt
            let originalIDs = Set(entries.map(\.id))
            for entry in context.insertedModelsArray.compactMap({ $0 as? SyncOutboxEntry })
                where entry.entityKind == .exercise && entry.entityID == exercise.id
                    && entry.ownerTokenIdentifier == owner && !originalIDs.contains(entry.id) {
                context.delete(entry)
            }
            restoreEntries.forEach { $0() }
            throw error
        }
        syncScheduler?.requestSync()
    }

    private enum LibraryError: LocalizedError {
        case activeDuplicate
        var errorDescription: String? {
            "An active exercise already has this name and equipment. Rename that exercise in Active, then try Restore again. Their histories will stay separate."
        }
    }

    private func mutationOwner(currentOwner: String?, requestedOwner: String?) throws -> String? {
        guard let currentOwner else { return requestedOwner }
        guard let requestedOwner, requestedOwner != currentOwner else { return currentOwner }
        throw SyncMutationOwnershipError.ownerMismatch
    }
}
