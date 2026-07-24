import Foundation

struct ExerciseHistorySummary: Identifiable, Hashable {
    var id: String
    var exerciseID: UUID?
    var name: String
    var equipmentRaw: String?
    var primaryMuscleGroupRaw: String?
    var lastPerformedAt: Date
    var completedSetCount: Int
    var performanceCount: Int = 1
    var performanceSessionIDs: Set<UUID> = []

    var lastPerformedLabel: String {
        WorkoutFormatters.compactDate(lastPerformedAt)
    }

    var performanceSummaryLabel: String {
        let workoutLabel = performanceCount == 1 ? "workout" : "workouts"
        return "Last: \(lastPerformedLabel) · \(performanceCount) \(workoutLabel)"
    }

    var metadataDisplayText: String? {
        guard let equipmentRaw, let primaryMuscleGroupRaw else {
            return nil
        }

        let equipment = ExerciseEquipment(rawValue: equipmentRaw) ?? .other
        let muscleGroup = ExerciseMuscleGroup(rawValue: primaryMuscleGroupRaw) ?? .other
        return "\(equipment.displayName) • \(muscleGroup.displayName)"
    }

    static func makeSummaries(
        from sessions: [WorkoutSession],
        ownerTokenIdentifier: String? = nil
    ) -> [ExerciseHistorySummary] {
        var grouped: [ExerciseHistoryIdentity: ExerciseHistorySummary] = [:]

        for session in WorkoutSession.visibleCompletedSessions(from: sessions, ownerTokenIdentifier: ownerTokenIdentifier) {
            for loggedExercise in session.sortedLoggedExercises {
                let completedSetCount = loggedExercise.sortedSets.filter(\.isCompleted).count
                guard completedSetCount > 0 else { continue }

                let key = ExerciseHistoryIdentity(loggedExercise: loggedExercise)
                let exerciseID = loggedExercise.exercise?.id

                if var existing = grouped[key] {
                    existing.completedSetCount += completedSetCount
                    existing.performanceSessionIDs.insert(session.id)
                    existing.performanceCount = existing.performanceSessionIDs.count
                    if session.startedAt > existing.lastPerformedAt {
                        existing.lastPerformedAt = session.startedAt
                        existing.name = loggedExercise.exerciseSnapshotName
                        existing.equipmentRaw = loggedExercise.resolvedSnapshotEquipmentRaw
                        existing.primaryMuscleGroupRaw = loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw
                    }
                    grouped[key] = existing
                } else {
                    grouped[key] = ExerciseHistorySummary(
                        id: key.id,
                        exerciseID: exerciseID,
                        name: loggedExercise.exerciseSnapshotName,
                        equipmentRaw: loggedExercise.resolvedSnapshotEquipmentRaw,
                        primaryMuscleGroupRaw: loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw,
                        lastPerformedAt: session.startedAt,
                        completedSetCount: completedSetCount,
                        performanceCount: 1,
                        performanceSessionIDs: [session.id]
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

    static func makePerformanceSummary(
        in summaries: [ExerciseHistorySummary],
        matching exercise: Exercise
    ) -> ExerciseHistorySummary? {
        let matchingIdentities = ExerciseHistoryIdentity.matching(exercise)
        let matchingSummaries = summaries.filter {
            matchingIdentities.contains(ExerciseHistoryIdentity(summary: $0))
        }
        guard var combined = matchingSummaries.first else { return nil }

        combined.id = ExerciseHistoryIdentity.exercise(exercise.id).id
        combined.exerciseID = exercise.id
        combined.name = exercise.name
        combined.equipmentRaw = exercise.equipmentRaw
        combined.primaryMuscleGroupRaw = exercise.primaryMuscleGroupRaw
        combined.lastPerformedAt = matchingSummaries.map(\.lastPerformedAt).max()
            ?? combined.lastPerformedAt
        combined.completedSetCount = matchingSummaries.reduce(0) {
            $0 + $1.completedSetCount
        }
        combined.performanceSessionIDs = matchingSummaries.reduce(into: []) {
            $0.formUnion($1.performanceSessionIDs)
        }
        combined.performanceCount = combined.performanceSessionIDs.isEmpty
            ? matchingSummaries.reduce(0) { $0 + $1.performanceCount }
            : combined.performanceSessionIDs.count
        return combined
    }

    static func find(in summaries: [ExerciseHistorySummary], matching route: ExerciseHistoryRoute) -> ExerciseHistorySummary? {
        let routeIdentity = ExerciseHistoryIdentity(route: route)
        return summaries.first { summary in
            ExerciseHistoryIdentity(summary: summary) == routeIdentity
        }
    }
}

private enum ExerciseHistoryIdentity: Hashable {
    case exercise(UUID)
    case snapshot(name: String, equipmentRaw: String?)

    init(loggedExercise: LoggedExercise) {
        if let exerciseID = loggedExercise.exercise?.id {
            self = .exercise(exerciseID)
        } else {
            self = .snapshot(
                name: loggedExercise.exerciseSnapshotName.lowercased(),
                equipmentRaw: loggedExercise.resolvedSnapshotEquipmentRaw?.lowercased()
            )
        }
    }

    init(summary: ExerciseHistorySummary) {
        if let exerciseID = summary.exerciseID {
            self = .exercise(exerciseID)
        } else {
            self = .snapshot(
                name: summary.name.lowercased(),
                equipmentRaw: summary.equipmentRaw?.lowercased()
            )
        }
    }

    init(route: ExerciseHistoryRoute) {
        if let exerciseID = route.exerciseID {
            self = .exercise(exerciseID)
        } else {
            self = .snapshot(
                name: route.name.lowercased(),
                equipmentRaw: route.equipmentRaw?.lowercased()
            )
        }
    }

    static func matching(_ exercise: Exercise) -> Set<ExerciseHistoryIdentity> {
        [
            .exercise(exercise.id),
            .snapshot(
                name: exercise.name.lowercased(),
                equipmentRaw: exercise.equipmentRaw.lowercased()
            ),
        ]
    }

    var id: String {
        switch self {
        case let .exercise(exerciseID):
            "exercise-\(exerciseID.uuidString)"
        case let .snapshot(name, equipmentRaw):
            "snapshot-\(name)-\(equipmentRaw ?? "unknown")"
        }
    }
}
