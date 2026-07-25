import Foundation

struct ExerciseHistorySummary: Identifiable, Hashable {
    var id: String
    var exerciseID: UUID?
    var name: String
    var equipmentRaw: String?
    var primaryMuscleGroupRaw: String?
    var lastPerformedAt: Date
    var completedSetCount: Int
    var performanceSessionIDs: Set<UUID>
    var snapshotFallbackIdentities: Set<ExerciseHistorySnapshotIdentity>

    var performanceCount: Int {
        performanceSessionIDs.count
    }

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

        return snapshotFallbackIdentities.contains(
            ExerciseHistorySnapshotIdentity(loggedExercise: loggedExercise)
        )
    }

    func matches(_ route: ExerciseHistoryRoute) -> Bool {
        if let routeExerciseID = route.exerciseID {
            return exerciseID == routeExerciseID
        }

        return snapshotFallbackIdentities.contains(
            ExerciseHistorySnapshotIdentity(
                name: route.name,
                equipmentRaw: route.equipmentRaw
            )
        )
    }

    static func makeSummaries(
        from sessions: [WorkoutSession],
        ownerTokenIdentifier: String? = nil
    ) -> [ExerciseHistorySummary] {
        makeIndex(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).summaries
    }

    static func makeIndex(
        from sessions: [WorkoutSession],
        ownerTokenIdentifier: String? = nil
    ) -> ExerciseHistoryIndex {
        let entries = WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).flatMap { session -> [ExerciseHistoryAggregationEntry] in
            session.sortedLoggedExercises.compactMap { loggedExercise -> ExerciseHistoryAggregationEntry? in
                let completedSetCount = loggedExercise.sortedSets.filter(\.isCompleted).count
                guard completedSetCount > 0 else { return nil }

                return ExerciseHistoryAggregationEntry(
                    session: session,
                    loggedExercise: loggedExercise,
                    completedSetCount: completedSetCount
                )
            }
        }

        var linkedExerciseIDsBySnapshotIdentity: [ExerciseHistorySnapshotIdentity: Set<UUID>] = [:]
        for entry in entries {
            if let exerciseID = entry.linkedExerciseID {
                linkedExerciseIDsBySnapshotIdentity[entry.snapshotIdentity, default: []]
                    .insert(exerciseID)
            }
        }
        // Resolve ownership before grouping so counts, routes, and detail sessions all
        // use the same conservative snapshot-attribution decision.
        let snapshotOwners = linkedExerciseIDsBySnapshotIdentity.compactMapValues { exerciseIDs in
            exerciseIDs.count == 1 ? exerciseIDs.first : nil
        }

        var grouped: [ExerciseHistoryIdentity: ExerciseHistorySummary] = [:]
        var linkedOnlyGrouped: [UUID: ExerciseHistorySummary] = [:]
        var snapshotOnlyGrouped: [ExerciseHistorySnapshotIdentity: ExerciseHistorySummary] = [:]
        for entry in entries {
            let attributedExerciseID = entry.linkedExerciseID
                ?? snapshotOwners[entry.snapshotIdentity]
            let key = attributedExerciseID.map(ExerciseHistoryIdentity.exercise)
                ?? .snapshot(entry.snapshotIdentity)
            let recordsSnapshotFallback = entry.linkedExerciseID == nil
                || snapshotOwners[entry.snapshotIdentity] == attributedExerciseID

            accumulate(
                entry,
                key: key,
                historyID: key.id,
                exerciseID: attributedExerciseID,
                recordsSnapshotFallback: recordsSnapshotFallback,
                in: &grouped
            )

            if let linkedExerciseID = entry.linkedExerciseID {
                accumulate(
                    entry,
                    key: linkedExerciseID,
                    historyID: ExerciseHistoryIdentity.exercise(linkedExerciseID).id,
                    exerciseID: linkedExerciseID,
                    recordsSnapshotFallback: false,
                    in: &linkedOnlyGrouped
                )
            }

            if entry.linkedExerciseID == nil {
                accumulate(
                    entry,
                    key: entry.snapshotIdentity,
                    historyID: entry.snapshotIdentity.id,
                    exerciseID: nil,
                    recordsSnapshotFallback: true,
                    in: &snapshotOnlyGrouped
                )
            }
        }

        return ExerciseHistoryIndex(
            summariesByIdentity: grouped,
            linkedOnlySummariesByExerciseID: linkedOnlyGrouped,
            snapshotOnlySummariesByIdentity: snapshotOnlyGrouped,
            linkedExerciseIDsBySnapshotIdentity: linkedExerciseIDsBySnapshotIdentity
        )
    }

    private static func accumulate<Key: Hashable>(
        _ entry: ExerciseHistoryAggregationEntry,
        key: Key,
        historyID: String,
        exerciseID: UUID?,
        recordsSnapshotFallback: Bool,
        in grouped: inout [Key: ExerciseHistorySummary]
    ) {
        if var existing = grouped[key] {
            existing.completedSetCount += entry.completedSetCount
            existing.performanceSessionIDs.insert(entry.session.id)
            if recordsSnapshotFallback {
                existing.snapshotFallbackIdentities.insert(entry.snapshotIdentity)
            }
            if entry.session.startedAt > existing.lastPerformedAt {
                existing.lastPerformedAt = entry.session.startedAt
                existing.name = entry.loggedExercise.exerciseSnapshotName
                existing.equipmentRaw = entry.loggedExercise.resolvedSnapshotEquipmentRaw
                existing.primaryMuscleGroupRaw = entry.loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw
            }
            grouped[key] = existing
        } else {
            grouped[key] = ExerciseHistorySummary(
                id: historyID,
                exerciseID: exerciseID,
                name: entry.loggedExercise.exerciseSnapshotName,
                equipmentRaw: entry.loggedExercise.resolvedSnapshotEquipmentRaw,
                primaryMuscleGroupRaw: entry.loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw,
                lastPerformedAt: entry.session.startedAt,
                completedSetCount: entry.completedSetCount,
                performanceSessionIDs: [entry.session.id],
                snapshotFallbackIdentities: recordsSnapshotFallback
                    ? [entry.snapshotIdentity]
                    : []
            )
        }
    }

    static func find(in summaries: [ExerciseHistorySummary], matching route: ExerciseHistoryRoute) -> ExerciseHistorySummary? {
        summaries.first { $0.matches(route) }
    }
}

struct ExerciseHistoryIndex {
    let summaries: [ExerciseHistorySummary]

    private let summariesByIdentity: [ExerciseHistoryIdentity: ExerciseHistorySummary]
    private let linkedOnlySummariesByExerciseID: [UUID: ExerciseHistorySummary]
    private let snapshotOnlySummariesByIdentity: [ExerciseHistorySnapshotIdentity: ExerciseHistorySummary]
    private let linkedExerciseIDsBySnapshotIdentity: [ExerciseHistorySnapshotIdentity: Set<UUID>]
    private let snapshotOwners: [ExerciseHistorySnapshotIdentity: UUID]

    fileprivate init(
        summariesByIdentity: [ExerciseHistoryIdentity: ExerciseHistorySummary],
        linkedOnlySummariesByExerciseID: [UUID: ExerciseHistorySummary],
        snapshotOnlySummariesByIdentity: [ExerciseHistorySnapshotIdentity: ExerciseHistorySummary],
        linkedExerciseIDsBySnapshotIdentity: [ExerciseHistorySnapshotIdentity: Set<UUID>]
    ) {
        self.summariesByIdentity = summariesByIdentity
        self.linkedOnlySummariesByExerciseID = linkedOnlySummariesByExerciseID
        self.snapshotOnlySummariesByIdentity = snapshotOnlySummariesByIdentity
        self.linkedExerciseIDsBySnapshotIdentity = linkedExerciseIDsBySnapshotIdentity
        self.snapshotOwners = linkedExerciseIDsBySnapshotIdentity.compactMapValues { exerciseIDs in
            exerciseIDs.count == 1 ? exerciseIDs.first : nil
        }
        self.summaries = Self.sortedSummaries(summariesByIdentity.values)
    }

    func summary(
        matching exercise: Exercise,
        visibility: ExerciseHistoryVisibilityScope
    ) -> ExerciseHistorySummary? {
        resolution(matching: exercise, visibility: visibility).summary
    }

    func summaries(
        reconciledFor visibility: ExerciseHistoryVisibilityScope
    ) -> [ExerciseHistorySummary] {
        var consumedIdentities: Set<ExerciseHistoryIdentity> = []
        var consumedSnapshotIdentities: Set<ExerciseHistorySnapshotIdentity> = []
        var reconciledByID: [String: ExerciseHistorySummary] = [:]

        for exercise in visibility.exercises {
            let resolution = resolution(
                matching: exercise,
                visibility: visibility
            )
            consumedIdentities.formUnion(resolution.consumedIdentities)
            consumedSnapshotIdentities.formUnion(resolution.consumedSnapshotIdentities)
            if let summary = resolution.summary {
                reconciledByID[summary.id] = summary
            }
        }

        for (exerciseID, linkedOnlySummary) in linkedOnlySummariesByExerciseID
            where !consumedIdentities.contains(.exercise(exerciseID)) {
            let summary = snapshotOwners.reduce(into: linkedOnlySummary) { result, owner in
                let (snapshotIdentity, ownerExerciseID) = owner
                guard ownerExerciseID == exerciseID,
                      !consumedSnapshotIdentities.contains(snapshotIdentity),
                      let snapshotSummary = snapshotOnlySummariesByIdentity[snapshotIdentity] else {
                    return
                }
                result = Self.merging(result, with: snapshotSummary)
            }
            reconciledByID[summary.id] = summary
        }

        for (snapshotIdentity, summary) in snapshotOnlySummariesByIdentity
            where snapshotOwners[snapshotIdentity] == nil
                && !consumedSnapshotIdentities.contains(snapshotIdentity) {
            reconciledByID[summary.id] = summary
        }

        return Self.sortedSummaries(reconciledByID.values)
    }

    private func resolution(
        matching exercise: Exercise,
        visibility: ExerciseHistoryVisibilityScope
    ) -> ExerciseHistoryResolution {
        let exactIdentity = ExerciseHistoryIdentity.exercise(exercise.id)
        let exactSummary = summariesByIdentity[.exercise(exercise.id)]
        var consumedIdentities: Set<ExerciseHistoryIdentity> = []
        if exactSummary != nil {
            consumedIdentities.insert(exactIdentity)
        }

        let snapshotIdentity = ExerciseHistorySnapshotIdentity(exercise: exercise)
        let hasVisibleLinkedClaim = linkedExerciseIDsBySnapshotIdentity[snapshotIdentity]?
            .contains { visibility.containsExercise(withID: $0) } == true
        // A visible linked claim means this raw snapshot copy was either folded into
        // that exercise already or belongs to another visible exercise.
        guard visibility.allowsSnapshotFallback(for: snapshotIdentity),
              !hasVisibleLinkedClaim,
              let snapshotSummary = snapshotOnlySummariesByIdentity[snapshotIdentity] else {
            return ExerciseHistoryResolution(
                summary: exactSummary,
                consumedIdentities: consumedIdentities,
                consumedSnapshotIdentities: []
            )
        }

        let snapshotHistoryIdentity = ExerciseHistoryIdentity.snapshot(snapshotIdentity)
        if summariesByIdentity[snapshotHistoryIdentity] != nil {
            consumedIdentities.insert(snapshotHistoryIdentity)
        }
        guard let combined = exactSummary else {
            return ExerciseHistoryResolution(
                summary: snapshotSummary,
                consumedIdentities: consumedIdentities,
                consumedSnapshotIdentities: [snapshotIdentity]
            )
        }

        return ExerciseHistoryResolution(
            summary: Self.merging(combined, with: snapshotSummary),
            consumedIdentities: consumedIdentities,
            consumedSnapshotIdentities: [snapshotIdentity]
        )
    }

    func summary(
        matching route: ExerciseHistoryRoute,
        visibility: ExerciseHistoryVisibilityScope
    ) -> ExerciseHistorySummary? {
        let snapshotIdentity = ExerciseHistorySnapshotIdentity(
            name: route.name,
            equipmentRaw: route.equipmentRaw
        )
        guard let exerciseID = route.exerciseID else {
            return summariesByIdentity[.snapshot(snapshotIdentity)]
                ?? summaries.first {
                    $0.snapshotFallbackIdentities.contains(snapshotIdentity)
                }
        }
        guard let exercise = visibility.exercise(withID: exerciseID) else {
            return summariesByIdentity[.exercise(exerciseID)]
        }

        return summary(matching: exercise, visibility: visibility)
    }

    private static func merging(
        _ summary: ExerciseHistorySummary,
        with snapshotSummary: ExerciseHistorySummary
    ) -> ExerciseHistorySummary {
        var combined = summary
        combined.completedSetCount += snapshotSummary.completedSetCount
        combined.performanceSessionIDs.formUnion(snapshotSummary.performanceSessionIDs)
        combined.snapshotFallbackIdentities.formUnion(snapshotSummary.snapshotFallbackIdentities)
        if snapshotSummary.lastPerformedAt >= combined.lastPerformedAt {
            combined.lastPerformedAt = snapshotSummary.lastPerformedAt
            combined.name = snapshotSummary.name
            combined.equipmentRaw = snapshotSummary.equipmentRaw
            combined.primaryMuscleGroupRaw = snapshotSummary.primaryMuscleGroupRaw
        }
        return combined
    }

    private static func sortedSummaries<S: Sequence>(
        _ summaries: S
    ) -> [ExerciseHistorySummary] where S.Element == ExerciseHistorySummary {
        summaries.sorted { lhs, rhs in
            if lhs.lastPerformedAt != rhs.lastPerformedAt {
                return lhs.lastPerformedAt > rhs.lastPerformedAt
            }

            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }
}

private struct ExerciseHistoryResolution {
    let summary: ExerciseHistorySummary?
    let consumedIdentities: Set<ExerciseHistoryIdentity>
    let consumedSnapshotIdentities: Set<ExerciseHistorySnapshotIdentity>
}

struct ExerciseHistoryVisibilityScope {
    let exercises: [Exercise]

    private let exerciseIDs: Set<UUID>
    private let exercisesByID: [UUID: Exercise]
    private let exerciseCountBySnapshotIdentity: [ExerciseHistorySnapshotIdentity: Int]

    init(
        exercises: [Exercise],
        ownerTokenIdentifier: String?
    ) {
        let visibleExercises = Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        self.exercises = visibleExercises
        self.exerciseIDs = Set(visibleExercises.map(\.id))
        self.exercisesByID = Dictionary(
            uniqueKeysWithValues: visibleExercises.map { ($0.id, $0) }
        )
        self.exerciseCountBySnapshotIdentity = Dictionary(
            grouping: visibleExercises,
            by: ExerciseHistorySnapshotIdentity.init(exercise:)
        ).mapValues(\.count)
    }

    fileprivate func exercise(withID exerciseID: UUID) -> Exercise? {
        exercisesByID[exerciseID]
    }

    fileprivate func containsExercise(withID exerciseID: UUID) -> Bool {
        exerciseIDs.contains(exerciseID)
    }

    fileprivate func allowsSnapshotFallback(
        for snapshotIdentity: ExerciseHistorySnapshotIdentity
    ) -> Bool {
        exerciseCountBySnapshotIdentity[snapshotIdentity] == 1
    }
}

private struct ExerciseHistoryAggregationEntry {
    let session: WorkoutSession
    let loggedExercise: LoggedExercise
    let completedSetCount: Int

    var linkedExerciseID: UUID? {
        loggedExercise.exercise?.id
    }

    var snapshotIdentity: ExerciseHistorySnapshotIdentity {
        ExerciseHistorySnapshotIdentity(loggedExercise: loggedExercise)
    }
}

struct ExerciseHistorySnapshotIdentity: Hashable {
    let name: String
    let equipmentRaw: String?

    var id: String {
        "snapshot-\(name)-\(equipmentRaw ?? "unknown")"
    }

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

    init(exercise: Exercise) {
        self.init(
            name: exercise.name,
            equipmentRaw: exercise.equipmentRaw
        )
    }
}

private enum ExerciseHistoryIdentity: Hashable {
    case exercise(UUID)
    case snapshot(ExerciseHistorySnapshotIdentity)

    var id: String {
        switch self {
        case let .exercise(exerciseID):
            "exercise-\(exerciseID.uuidString)"
        case let .snapshot(snapshotIdentity):
            snapshotIdentity.id
        }
    }
}
