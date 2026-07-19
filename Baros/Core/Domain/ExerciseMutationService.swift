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
        now: Date = .now
    ) throws {
        let effectiveOwner = try mutationOwner(
            currentOwner: exercise.syncOwnerTokenIdentifier,
            requestedOwner: ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        )
        exercise.syncOwnerTokenIdentifier = effectiveOwner ?? exercise.syncOwnerTokenIdentifier
        let outcome = try exercise.archiveOrDelete(context: context, now: now)
        switch outcome {
        case .archived:
            try recorder.recordUpdate(
                entityKind: .exercise,
                entityID: exercise.id,
                ownerTokenIdentifier: effectiveOwner,
                context: context,
                now: now
            )
        case .deleted:
            try recorder.recordDelete(
                entityKind: .exercise,
                entityID: exercise.id,
                ownerTokenIdentifier: effectiveOwner,
                context: context,
                now: now
            )
        }
        try context.save()
        syncScheduler?.requestSync()
    }

    private func mutationOwner(currentOwner: String?, requestedOwner: String?) throws -> String? {
        guard let currentOwner else { return requestedOwner }
        guard let requestedOwner, requestedOwner != currentOwner else { return currentOwner }
        throw SyncMutationOwnershipError.ownerMismatch
    }
}
