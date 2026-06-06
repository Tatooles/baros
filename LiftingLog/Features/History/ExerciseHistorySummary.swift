import Foundation

struct ExerciseHistorySummary: Identifiable, Hashable {
    var id: String
    var exerciseID: UUID?
    var name: String
    var equipmentRaw: String?
    var primaryMuscleGroupRaw: String?
    var lastPerformedAt: Date
    var completedSetCount: Int

    var lastPerformedLabel: String {
        WorkoutFormatters.compactDate(lastPerformedAt)
    }

    var metadataDisplayText: String? {
        guard let equipmentRaw, let primaryMuscleGroupRaw else {
            return nil
        }

        let equipment = ExerciseEquipment(rawValue: equipmentRaw) ?? .other
        let muscleGroup = ExerciseMuscleGroup(rawValue: primaryMuscleGroupRaw) ?? .other
        return "\(equipment.displayName) • \(muscleGroup.displayName)"
    }

    static func makeSummaries(from sessions: [WorkoutSession]) -> [ExerciseHistorySummary] {
        var grouped: [String: ExerciseHistorySummary] = [:]

        for session in WorkoutSession.visibleCompletedSessions(from: sessions) {
            for loggedExercise in session.sortedLoggedExercises {
                let completedSetCount = loggedExercise.sortedSets.filter(\.isCompleted).count
                guard completedSetCount > 0 else { continue }

                let key: String
                let exerciseID: UUID?
                if let id = loggedExercise.exercise?.id {
                    key = "exercise-\(id.uuidString)"
                    exerciseID = id
                } else {
                    key = "snapshot-\(loggedExercise.exerciseSnapshotName.lowercased())-\((loggedExercise.resolvedSnapshotEquipmentRaw ?? "unknown").lowercased())"
                    exerciseID = nil
                }

                if var existing = grouped[key] {
                    existing.completedSetCount += completedSetCount
                    if session.startedAt > existing.lastPerformedAt {
                        existing.lastPerformedAt = session.startedAt
                        existing.name = loggedExercise.exerciseSnapshotName
                        existing.equipmentRaw = loggedExercise.resolvedSnapshotEquipmentRaw
                        existing.primaryMuscleGroupRaw = loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw
                    }
                    grouped[key] = existing
                } else {
                    grouped[key] = ExerciseHistorySummary(
                        id: key,
                        exerciseID: exerciseID,
                        name: loggedExercise.exerciseSnapshotName,
                        equipmentRaw: loggedExercise.resolvedSnapshotEquipmentRaw,
                        primaryMuscleGroupRaw: loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw,
                        lastPerformedAt: session.startedAt,
                        completedSetCount: completedSetCount
                    )
                }
            }
        }

        return grouped.values.sorted {
            if $0.lastPerformedAt == $1.lastPerformedAt {
                return $0.name < $1.name
            }
            return $0.lastPerformedAt > $1.lastPerformedAt
        }
    }

    static func find(in summaries: [ExerciseHistorySummary], matching route: ExerciseHistoryRoute) -> ExerciseHistorySummary? {
        summaries.first { summary in
            if let exerciseID = route.exerciseID {
                return summary.exerciseID == exerciseID
            }

            return summary.exerciseID == nil
                && summary.name.caseInsensitiveCompare(route.name) == .orderedSame
                && summary.equipmentRaw == route.equipmentRaw
        }
    }
}
