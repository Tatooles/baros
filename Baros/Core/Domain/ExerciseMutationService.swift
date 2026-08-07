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
        guard let syncOutboxTransaction else {
            throw SyncOutboxTransactionError.currentOwnerMismatch
        }
        if let effectiveOwner {
            try syncOutboxTransaction.perform(ownerTokenIdentifier: effectiveOwner) { actions in
                try actions.create(.exerciseLibraryEntry(exercise), now: now) { context in
                    context.insert(exercise)
                }
            }
        } else {
            try syncOutboxTransaction.performUnclaimed { actions in
                try actions.create(.exerciseLibraryEntry(exercise), now: now) { context in
                    context.insert(exercise)
                }
            }
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

        guard let syncOutboxTransaction else {
            throw SyncOutboxTransactionError.currentOwnerMismatch
        }

        guard let requestedOwner else {
            guard exercise.syncOwnerTokenIdentifier == nil else {
                throw SyncMutationOwnershipError.ownerMismatch
            }
            try syncOutboxTransaction.performUnclaimed { actions in
                try actions.update(.exerciseLibraryEntry(exercise), now: now) { _ in mutation() }
            }
            return
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
        guard let syncOutboxTransaction else {
            throw SyncOutboxTransactionError.currentOwnerMismatch
        }

        let outcome = try exercise.removalOutcome(context: context)
        guard let requestedOwner else {
            guard exercise.syncOwnerTokenIdentifier == nil else {
                throw SyncMutationOwnershipError.ownerMismatch
            }
            try syncOutboxTransaction.performUnclaimed { actions in
                switch outcome {
                case .archived:
                    try actions.update(.exerciseLibraryEntry(exercise), now: now) { _ in
                        exercise.applyRemoval(outcome, now: now)
                    }
                case .deleted:
                    try actions.delete(.exerciseLibraryEntry(exercise), now: now) { _ in
                        exercise.applyRemoval(outcome, now: now)
                    }
                }
            }
            return
        }

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
