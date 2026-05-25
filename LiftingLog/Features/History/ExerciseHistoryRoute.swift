import Foundation

struct ExerciseHistoryRoute: Hashable, Identifiable {
    let exerciseID: UUID?
    let name: String

    var id: String {
        if let exerciseID {
            return "exercise-\(exerciseID.uuidString)"
        }

        return "snapshot-\(name.lowercased())"
    }

    init(exerciseID: UUID?, name: String) {
        self.exerciseID = exerciseID
        self.name = name
    }

    init(summary: ExerciseHistorySummary) {
        self.init(exerciseID: summary.exerciseID, name: summary.name)
    }

    init(loggedExercise: LoggedExercise) {
        self.init(exerciseID: loggedExercise.exercise?.id, name: loggedExercise.exerciseSnapshotName)
    }
}
