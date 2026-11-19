import Foundation

public struct ExerciseHistoryRoute: Hashable, Identifiable {
    let exerciseID: UUID?
    let name: String
    let equipmentRaw: String?

    public var id: String {
        if let exerciseID {
            return "exercise-\(exerciseID.uuidString)"
        }

        return ExerciseHistorySnapshotIdentity(
            name: name,
            equipmentRaw: equipmentRaw
        ).id
    }

    init(exerciseID: UUID?, name: String, equipmentRaw: String? = nil) {
        self.exerciseID = exerciseID
        self.name = name
        self.equipmentRaw = equipmentRaw
    }

    public init(summary: ExerciseHistorySummary) {
        self.init(exerciseID: summary.exerciseID, name: summary.name, equipmentRaw: summary.equipmentRaw)
    }

    public init(loggedExercise: LoggedExercise) {
        self.init(
            exerciseID: loggedExercise.exercise?.id,
            name: loggedExercise.exerciseSnapshotName,
            equipmentRaw: loggedExercise.resolvedSnapshotEquipmentRaw
        )
    }
}
