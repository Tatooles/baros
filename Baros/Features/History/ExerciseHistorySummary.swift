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
    var snapshotFallbackIdentities: Set<ExerciseHistorySnapshotIdentity> = []

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

    func matches(_ loggedExercise: LoggedExercise) -> Bool {
        if let loggedExerciseID = loggedExercise.exercise?.id {
            return exerciseID == loggedExerciseID
        }

        return effectiveSnapshotFallbackIdentities.contains(
            ExerciseHistorySnapshotIdentity(loggedExercise: loggedExercise)
        )
    }

    func matches(_ route: ExerciseHistoryRoute) -> Bool {
        if let routeExerciseID = route.exerciseID {
            return exerciseID == routeExerciseID
        }

        return effectiveSnapshotFallbackIdentities.contains(
            ExerciseHistorySnapshotIdentity(
                name: route.name,
                equipmentRaw: route.equipmentRaw
            )
        )
    }

    private var effectiveSnapshotFallbackIdentities: Set<ExerciseHistorySnapshotIdentity> {
        guard snapshotFallbackIdentities.isEmpty else {
            return snapshotFallbackIdentities
        }

        return [
            ExerciseHistorySnapshotIdentity(
                name: name,
                equipmentRaw: equipmentRaw
            ),
        ]
    }

    static func makeSummaries(
        from sessions: [WorkoutSession],
        ownerTokenIdentifier: String? = nil
    ) -> [ExerciseHistorySummary] {
        var grouped: [ExerciseHistoryIdentity: ExerciseHistorySummary] = [:]
        var linkedExerciseIDsBySnapshotIdentity: [ExerciseHistorySnapshotIdentity: Set<UUID>] = [:]

        for session in WorkoutSession.visibleCompletedSessions(from: sessions, ownerTokenIdentifier: ownerTokenIdentifier) {
            for loggedExercise in session.sortedLoggedExercises {
                let completedSetCount = loggedExercise.sortedSets.filter(\.isCompleted).count
                guard completedSetCount > 0 else { continue }

                let snapshotIdentity = ExerciseHistorySnapshotIdentity(
                    loggedExercise: loggedExercise
                )
                let key = ExerciseHistoryIdentity(loggedExercise: loggedExercise)
                let exerciseID = loggedExercise.exercise?.id
                if let exerciseID {
                    linkedExerciseIDsBySnapshotIdentity[snapshotIdentity, default: []]
                        .insert(exerciseID)
                }

                if var existing = grouped[key] {
                    existing.completedSetCount += completedSetCount
                    existing.performanceSessionIDs.insert(session.id)
                    existing.performanceCount = existing.performanceSessionIDs.count
                    existing.snapshotFallbackIdentities.insert(snapshotIdentity)
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
                        performanceSessionIDs: [session.id],
                        snapshotFallbackIdentities: [snapshotIdentity]
                    )
                }
            }
        }

        let reconciled = reconcileSnapshotFallbacks(
            in: grouped,
            linkedExerciseIDsBySnapshotIdentity: linkedExerciseIDsBySnapshotIdentity
        )

        return reconciled.values.sorted {
            if $0.lastPerformedAt == $1.lastPerformedAt {
                return $0.name < $1.name
            }
            return $0.lastPerformedAt > $1.lastPerformedAt
        }
    }

    private static func reconcileSnapshotFallbacks(
        in grouped: [ExerciseHistoryIdentity: ExerciseHistorySummary],
        linkedExerciseIDsBySnapshotIdentity: [ExerciseHistorySnapshotIdentity: Set<UUID>]
    ) -> [ExerciseHistoryIdentity: ExerciseHistorySummary] {
        var reconciled = grouped

        for (identity, snapshotSummary) in grouped {
            guard case let .snapshot(snapshotIdentity) = identity,
                  let linkedExerciseIDs = linkedExerciseIDsBySnapshotIdentity[snapshotIdentity],
                  linkedExerciseIDs.count == 1,
                  let exerciseID = linkedExerciseIDs.first,
                  var linkedSummary = reconciled[.exercise(exerciseID)] else {
                continue
            }

            linkedSummary.merge(snapshotSummary)
            reconciled[.exercise(exerciseID)] = linkedSummary
            reconciled.removeValue(forKey: identity)
        }

        return reconciled
    }

    private mutating func merge(_ other: ExerciseHistorySummary) {
        let summedPerformanceCount = performanceCount + other.performanceCount
        completedSetCount += other.completedSetCount
        performanceSessionIDs.formUnion(other.performanceSessionIDs)
        performanceCount = performanceSessionIDs.isEmpty
            ? summedPerformanceCount
            : performanceSessionIDs.count
        snapshotFallbackIdentities.formUnion(other.snapshotFallbackIdentities)

        if other.lastPerformedAt > lastPerformedAt {
            lastPerformedAt = other.lastPerformedAt
            name = other.name
            equipmentRaw = other.equipmentRaw
            primaryMuscleGroupRaw = other.primaryMuscleGroupRaw
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
        summaries.first { $0.matches(route) }
    }
}

struct ExerciseHistorySnapshotIdentity: Hashable {
    let name: String
    let equipmentRaw: String?

    init(name: String, equipmentRaw: String?) {
        self.name = name.lowercased()
        self.equipmentRaw = equipmentRaw?.lowercased()
    }

    init(loggedExercise: LoggedExercise) {
        self.init(
            name: loggedExercise.exerciseSnapshotName,
            equipmentRaw: loggedExercise.resolvedSnapshotEquipmentRaw
        )
    }
}

private enum ExerciseHistoryIdentity: Hashable {
    case exercise(UUID)
    case snapshot(ExerciseHistorySnapshotIdentity)

    init(loggedExercise: LoggedExercise) {
        if let exerciseID = loggedExercise.exercise?.id {
            self = .exercise(exerciseID)
        } else {
            self = .snapshot(ExerciseHistorySnapshotIdentity(loggedExercise: loggedExercise))
        }
    }

    init(summary: ExerciseHistorySummary) {
        if let exerciseID = summary.exerciseID {
            self = .exercise(exerciseID)
        } else {
            self = .snapshot(
                ExerciseHistorySnapshotIdentity(
                    name: summary.name,
                    equipmentRaw: summary.equipmentRaw
                )
            )
        }
    }

    static func matching(_ exercise: Exercise) -> Set<ExerciseHistoryIdentity> {
        [
            .exercise(exercise.id),
            .snapshot(
                ExerciseHistorySnapshotIdentity(
                    name: exercise.name,
                    equipmentRaw: exercise.equipmentRaw
                )
            ),
        ]
    }

    var id: String {
        switch self {
        case let .exercise(exerciseID):
            "exercise-\(exerciseID.uuidString)"
        case let .snapshot(snapshotIdentity):
            "snapshot-\(snapshotIdentity.name)-\(snapshotIdentity.equipmentRaw ?? "unknown")"
        }
    }
}
