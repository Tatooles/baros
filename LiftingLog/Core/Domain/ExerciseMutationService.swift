import Foundation
import SwiftData

@MainActor
struct ExerciseMutationService {
    private let recorder = SyncOutboxRecorder()

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
        let exercise = Exercise(
            name: name,
            category: category,
            equipment: equipment,
            primaryMuscle: primaryMuscle,
            notes: notes,
            createdAt: now,
            updatedAt: now
        )
        context.insert(exercise)
        try recorder.recordCreate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
        try context.save()
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
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
        try context.save()
    }

    func removeExercise(
        _ exercise: Exercise,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        let outcome = try exercise.archiveOrDelete(context: context, now: now)
        switch outcome {
        case .archived:
            try recorder.recordUpdate(
                entityKind: .exercise,
                entityID: exercise.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        case .deleted:
            try recorder.recordDelete(
                entityKind: .exercise,
                entityID: exercise.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }
        try context.save()
    }
}
