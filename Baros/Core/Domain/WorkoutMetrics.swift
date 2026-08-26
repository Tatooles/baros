import Foundation

struct WorkoutMetrics: Equatable {
    struct CacheKey: Equatable {
        private struct SetEntry: Equatable {
            let id: UUID
            let isCompleted: Bool
            let weight: Double?
            let reps: Int?
        }

        private let entries: [SetEntry]

        init(session: WorkoutSession) {
            entries = session.sortedLoggedExercises.flatMap { loggedExercise in
                loggedExercise.sortedSets.map { set in
                    SetEntry(
                        id: set.id,
                        isCompleted: set.isCompleted,
                        weight: WorkoutNumericInputPolicy.validatedWeight(set.weight),
                        reps: WorkoutNumericInputPolicy.validatedReps(set.reps)
                    )
                }
            }
        }
    }

    var totalSetCount: Int
    var completedSetCount: Int
    var completedVolume: Double
    var durationSeconds: Int

    init(session: WorkoutSession, now: Date = .now) {
        let sets = session.sortedLoggedExercises.flatMap(\.sortedSets)
        totalSetCount = sets.count
        completedSetCount = sets.filter(\.isCompleted).count
        completedVolume = sets.reduce(0) { $0 + $1.completedVolume }
        durationSeconds = session.effectiveDurationSeconds(now: now)
    }
}
