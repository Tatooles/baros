import Foundation
import SwiftData

@MainActor
struct WorkoutHistoryMutationService {
    private let recorder = SyncOutboxRecorder()

    func deleteWorkoutHistory(
        _ session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        session.markDeletedCascade(now: now)
        try recorder.recordDelete(
            entityKind: .workoutSession,
            entityID: session.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )

        for loggedExercise in session.loggedExercises {
            try recorder.recordDelete(
                entityKind: .loggedExercise,
                entityID: loggedExercise.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )

            for set in loggedExercise.sets {
                try recorder.recordDelete(
                    entityKind: .loggedSet,
                    entityID: set.id,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )
            }
        }

        try context.save()
    }
}
