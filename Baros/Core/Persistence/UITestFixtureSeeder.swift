import Foundation
import SwiftData

#if DEBUG
enum UITestFixtureSeeder {
    static let completedBenchWorkoutArgument = "--uitest-seed-completed-bench-workout"
    static let historyExerciseNoteArgument = "--uitest-seed-history-exercise-note"
    static let exerciseHistoryPerformanceArgument = "--uitest-seed-exercise-history-performance"
    static let matchingExercisePerformanceWorkoutsArgument =
        "--uitest-seed-matching-exercise-performance-workouts"
    static let largeActiveWorkoutArgument = "--uitest-seed-large-active-workout"
    static let largeActiveWorkoutTitle = "Performance Workout 10x5"

    static func seedFixtures(
        from arguments: [String],
        ownerTokenIdentifier: String? = nil,
        context: ModelContext
    ) throws {
        for title in values(after: completedBenchWorkoutArgument, in: arguments) {
            try seedCompletedBenchWorkout(
                title: title,
                exerciseNotes: arguments.contains(historyExerciseNoteArgument)
                    ? "Pause at the bottom\nKeep wrists stacked"
                    : "",
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
        }

        if arguments.contains(exerciseHistoryPerformanceArgument) {
            try seedExerciseHistoryPerformanceFixture(
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
        }

        if arguments.contains(matchingExercisePerformanceWorkoutsArgument) {
            try seedMatchingExercisePerformanceWorkouts(
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
        }

        if arguments.contains(largeActiveWorkoutArgument) {
            try seedActiveWorkoutPerformanceFixture(
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
        }
    }

    static func seedCompletedBenchWorkout(
        title: String,
        exerciseNotes: String = "",
        ownerTokenIdentifier: String? = nil,
        context: ModelContext
    ) throws {
        let fixtureTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fixtureTitle.isEmpty else { return }

        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: {
            $0.title == fixtureTitle
                && $0.status == .completed
                && !$0.isDeleted
                && $0.syncOwnerTokenIdentifier == ownerTokenIdentifier
        }) else {
            return
        }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let benchPress = Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: ownerTokenIdentifier)
            .first { $0.seedIdentifier == "bench-press" }

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt = startedAt.addingTimeInterval(3_600)
        let set = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            rpe: 8,
            isCompleted: true,
            completedAt: endedAt,
            createdAt: startedAt,
            updatedAt: endedAt
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: benchPress,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
            notes: exerciseNotes,
            createdAt: startedAt,
            updatedAt: endedAt,
            sets: [set]
        )
        let session = WorkoutSession(
            title: fixtureTitle,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 3_600,
            notes: "Previous workout narrative",
            status: .completed,
            source: .blank,
            createdAt: startedAt,
            updatedAt: endedAt,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            loggedExercises: [loggedExercise]
        )

        context.insert(session)
        try context.save()
    }

    static func seedMatchingExercisePerformanceWorkouts(
        ownerTokenIdentifier: String? = nil,
        context: ModelContext
    ) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        guard let benchPress = Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).first(where: { $0.seedIdentifier == "bench-press" }) else {
            return
        }

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt = startedAt.addingTimeInterval(3_600)

        func loggedExercise(
            id: String,
            orderIndex: Int,
            weight: Double
        ) -> LoggedExercise {
            LoggedExercise(
                id: stableUUID(id),
                orderIndex: orderIndex,
                exercise: benchPress,
                exerciseSnapshotName: "Bench Press",
                exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue,
                exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
                createdAt: startedAt,
                updatedAt: endedAt,
                sets: [
                    LoggedSet(
                        id: stableUUID("\(id)-set"),
                        orderIndex: 0,
                        weight: weight,
                        reps: 5,
                        rpe: 8,
                        isCompleted: true,
                        completedAt: endedAt,
                        createdAt: startedAt,
                        updatedAt: endedAt
                    ),
                ]
            )
        }

        let alphaSession = WorkoutSession(
            id: stableUUID("00000000-0000-4000-8000-000000012601"),
            title: "Matching Push",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 3_600,
            notes: "Identity Alpha",
            status: .completed,
            source: .blank,
            createdAt: startedAt,
            updatedAt: endedAt,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            loggedExercises: [
                loggedExercise(
                    id: "00000000-0000-4000-8000-000000012611",
                    orderIndex: 0,
                    weight: 185
                ),
                loggedExercise(
                    id: "00000000-0000-4000-8000-000000012612",
                    orderIndex: 1,
                    weight: 195
                ),
            ]
        )
        let betaSession = WorkoutSession(
            id: stableUUID("00000000-0000-4000-8000-000000012602"),
            title: "Matching Push",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 3_600,
            notes: "Identity Beta",
            status: .completed,
            source: .blank,
            createdAt: startedAt,
            updatedAt: endedAt,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            loggedExercises: [
                loggedExercise(
                    id: "00000000-0000-4000-8000-000000012621",
                    orderIndex: 0,
                    weight: 225
                ),
            ]
        )

        context.insert(alphaSession)
        context.insert(betaSession)
        try context.save()
    }

    static func seedExerciseHistoryPerformanceFixture(
        ownerTokenIdentifier: String? = nil,
        context: ModelContext
    ) throws {
        let exercises = try context.fetch(
            FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\Exercise.name)])
        ).filter { $0.isVisible(to: ownerTokenIdentifier) }
        let fixtureExercises = Array(exercises.prefix(20))
        guard fixtureExercises.count == 20 else { return }

        for sessionIndex in 0..<100 {
            let startedAt = Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + sessionIndex))
            let loggedExercises = (0..<10).map { exerciseOffset in
                let exercise = fixtureExercises[(sessionIndex + exerciseOffset) % fixtureExercises.count]
                let sets = (0..<3).map { setIndex in
                    LoggedSet(
                        orderIndex: setIndex,
                        weight: Double(100 + sessionIndex + setIndex),
                        reps: 5 + setIndex,
                        rpe: 8,
                        isCompleted: true,
                        completedAt: startedAt,
                        createdAt: startedAt,
                        updatedAt: startedAt
                    )
                }
                return LoggedExercise(
                    orderIndex: exerciseOffset,
                    exercise: exercise,
                    exerciseSnapshotName: exercise.name,
                    exerciseSnapshotEquipmentRaw: exercise.equipmentRaw,
                    exerciseSnapshotPrimaryMuscleGroupRaw: exercise.primaryMuscleGroupRaw,
                    createdAt: startedAt,
                    updatedAt: startedAt,
                    sets: sets
                )
            }
            context.insert(
                WorkoutSession(
                    title: "Performance Workout \(sessionIndex)",
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(3_600),
                    durationSeconds: 3_600,
                    status: .completed,
                    source: .blank,
                    createdAt: startedAt,
                    updatedAt: startedAt,
                    syncOwnerTokenIdentifier: ownerTokenIdentifier,
                    loggedExercises: loggedExercises
                )
            )
        }
        try context.save()
    }

    static func seedActiveWorkoutPerformanceFixture(
        ownerTokenIdentifier: String? = nil,
        context: ModelContext
    ) throws {
        let exercises = try context.fetch(
            FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\Exercise.name)])
        ).filter { $0.isVisible(to: ownerTokenIdentifier) }
        let fixtureExercises = Array(exercises.prefix(10))
        guard fixtureExercises.count == 10 else { return }

        let baseDate = Date(timeIntervalSince1970: 1_700_100_000)
        let activeTitle = largeActiveWorkoutTitle
        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: {
            $0.title == activeTitle
                && $0.status == .active
                && !$0.isDeleted
                && $0.syncOwnerTokenIdentifier == ownerTokenIdentifier
        }) else { return }

        let activeSession = makePerformanceSession(
            id: stableUUID("00000000-0000-4000-8000-000000000001"),
            title: activeTitle,
            startedAt: baseDate,
            status: .active,
            exercises: fixtureExercises,
            setCount: 5,
            ownerTokenIdentifier: ownerTokenIdentifier,
            stableIDSeed: "00000000-0000-4000-8000-0000001"
        )
        context.insert(activeSession)

        for sessionIndex in 0..<100 {
            let startedAt = baseDate.addingTimeInterval(-Double((sessionIndex + 1) * 86_400))
            let completedSession = makePerformanceSession(
                id: stableUUID(String(format: "00000000-0000-4000-8000-%012d", sessionIndex + 2)),
                title: String(format: "Performance History %03d", sessionIndex + 1),
                startedAt: startedAt,
                status: .completed,
                exercises: fixtureExercises,
                setCount: 5,
                ownerTokenIdentifier: ownerTokenIdentifier,
                stableIDSeed: String(format: "00000000-0000-4000-8001-%07d", sessionIndex + 1)
            )
            context.insert(completedSession)
        }

        try context.save()
    }

    private static func makePerformanceSession(
        id: UUID,
        title: String,
        startedAt: Date,
        status: WorkoutSessionStatus,
        exercises: [Exercise],
        setCount: Int,
        ownerTokenIdentifier: String?,
        stableIDSeed: String
    ) -> WorkoutSession {
        let endedAt = status == .completed ? startedAt.addingTimeInterval(3_600) : nil
        let loggedExercises = exercises.enumerated().map { exerciseIndex, exercise in
            let sets = (0..<setCount).map { setIndex in
                LoggedSet(
                    id: stableUUID("\(stableIDSeed)-\(exerciseIndex)-\(setIndex)"),
                    orderIndex: setIndex,
                    weight: Double(100 + exerciseIndex),
                    reps: 5,
                    rpe: 8,
                    isCompleted: status == .completed,
                    completedAt: endedAt,
                    createdAt: startedAt,
                    updatedAt: endedAt ?? startedAt
                )
            }
            return LoggedExercise(
                id: stableUUID("\(stableIDSeed)-exercise-\(exerciseIndex)"),
                orderIndex: exerciseIndex,
                exercise: exercise,
                exerciseSnapshotName: exercise.name,
                exerciseSnapshotEquipmentRaw: exercise.equipmentRaw,
                exerciseSnapshotPrimaryMuscleGroupRaw: exercise.primaryMuscleGroupRaw,
                createdAt: startedAt,
                updatedAt: endedAt ?? startedAt,
                sets: sets
            )
        }
        return WorkoutSession(
            id: id,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: status == .completed ? 3_600 : 0,
            status: status,
            source: .blank,
            createdAt: startedAt,
            updatedAt: endedAt ?? startedAt,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            loggedExercises: loggedExercises
        )
    }

    private static func stableUUID(_ string: String) -> UUID {
        if let uuid = UUID(uuidString: string) {
            return uuid
        }

        var hash = UInt64(1469598103934665603)
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let suffix = String(format: "%012llx", hash & 0x0000_FFFF_FFFF_FFFF)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
    }

    private static func values(after argument: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == argument else { return nil }
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { return nil }
            return arguments[valueIndex]
        }
    }
}
#endif
