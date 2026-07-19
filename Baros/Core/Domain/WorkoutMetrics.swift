import Foundation

struct WorkoutMetrics: Equatable {
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
