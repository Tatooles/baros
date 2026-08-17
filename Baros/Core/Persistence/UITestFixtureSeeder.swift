import Foundation
import SwiftData

#if DEBUG
enum UITestFixtureSeeder {
    static let completedBenchWorkoutArgument = "--uitest-seed-completed-bench-workout"
    static let historyExerciseNoteArgument = "--uitest-seed-history-exercise-note"
    static let exerciseHistoryPerformanceArgument = "--uitest-seed-exercise-history-performance"

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
