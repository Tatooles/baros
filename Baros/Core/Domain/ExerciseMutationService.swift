import Foundation
import SwiftData

@MainActor
struct ExerciseMutationService {
    private let syncOutboxTransaction: SyncOutboxTransaction?

    init(syncOutboxTransaction: SyncOutboxTransaction? = nil) {
        self.syncOutboxTransaction = syncOutboxTransaction
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
        let effectiveOwner = ownerTokenIdentifier ?? syncOutboxTransaction?.currentOwnerTokenIdentifier
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
        if let effectiveOwner {
            guard let syncOutboxTransaction else {
                throw SyncOutboxTransactionError.currentOwnerMismatch
            }
            try syncOutboxTransaction.perform(ownerTokenIdentifier: effectiveOwner) { actions in
                try actions.create(.exerciseLibraryEntry(exercise), now: now) { context in
                    context.insert(exercise)
                }
            }
        } else {
            context.insert(exercise)
            try context.save()
        }
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

        let requestedOwner = ownerTokenIdentifier ?? syncOutboxTransaction?.currentOwnerTokenIdentifier
        let mutation = {
            exercise.update(
                name: name,
                category: category,
                equipment: equipment,
                primaryMuscle: primaryMuscle,
                notes: notes
            )
            exercise.touch(now: now)
        }

        guard let requestedOwner else {
            guard exercise.syncOwnerTokenIdentifier == nil else {
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
            try actions.update(.exerciseLibraryEntry(exercise), now: now) { _ in
                let effectiveOwner = try mutationOwner(
                    currentOwner: exercise.syncOwnerTokenIdentifier,
                    requestedOwner: requestedOwner
                )
                exercise.syncOwnerTokenIdentifier = effectiveOwner
                mutation()
            }
        }
    }

    func removeExercise(
        _ exercise: Exercise,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        let requestedOwner = ownerTokenIdentifier ?? syncOutboxTransaction?.currentOwnerTokenIdentifier
        guard let requestedOwner else {
            guard exercise.syncOwnerTokenIdentifier == nil else {
                throw SyncMutationOwnershipError.ownerMismatch
            }
            _ = try exercise.archiveOrDelete(context: context, now: now)
            try context.save()
            return
        }

        guard let syncOutboxTransaction else {
            throw SyncOutboxTransactionError.currentOwnerMismatch
        }
        let outcome = try exercise.removalOutcome(context: context)
        switch outcome {
        case .archived:
            try syncOutboxTransaction.perform(ownerTokenIdentifier: requestedOwner) { actions in
                try actions.update(.exerciseLibraryEntry(exercise), now: now) { _ in
                    let effectiveOwner = try mutationOwner(
                        currentOwner: exercise.syncOwnerTokenIdentifier,
                        requestedOwner: requestedOwner
                    )
                    exercise.syncOwnerTokenIdentifier = effectiveOwner
                    exercise.applyRemoval(outcome, now: now)
                }
            }
        case .deleted:
            try syncOutboxTransaction.perform(ownerTokenIdentifier: requestedOwner) { actions in
                try actions.delete(.exerciseLibraryEntry(exercise), now: now) { _ in
                    let effectiveOwner = try mutationOwner(
                        currentOwner: exercise.syncOwnerTokenIdentifier,
                        requestedOwner: requestedOwner
                    )
                    exercise.syncOwnerTokenIdentifier = effectiveOwner
                    exercise.applyRemoval(outcome, now: now)
                }
            }
        }
    }

    private func mutationOwner(currentOwner: String?, requestedOwner: String?) throws -> String? {
        guard let currentOwner else { return requestedOwner }
        guard let requestedOwner, requestedOwner != currentOwner else { return currentOwner }
        throw SyncMutationOwnershipError.ownerMismatch
    }
}
