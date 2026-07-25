import Foundation
import SwiftData

#if DEBUG
enum UITestFixtureSeeder {
    static let completedBenchWorkoutArgument = "--uitest-seed-completed-bench-workout"
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
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
        }

        if arguments.contains(largeActiveWorkoutArgument) {
            try seedLargeActiveWorkout(
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context
            )
        }
    }

    static func seedCompletedBenchWorkout(
        title: String,
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

    static func seedLargeActiveWorkout(
        ownerTokenIdentifier: String? = nil,
        context: ModelContext
    ) throws {
        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: {
            $0.title == largeActiveWorkoutTitle
                && $0.status == .active
                && !$0.isDeleted
                && $0.syncOwnerTokenIdentifier == ownerTokenIdentifier
        }) else {
            return
        }

        let activeStartedAt = Date(timeIntervalSince1970: 1_784_900_000)
        let activeSession = makeLargeSession(
            title: largeActiveWorkoutTitle,
            startedAt: activeStartedAt,
            status: .active,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(activeSession)

        for historyIndex in 0..<100 {
            let startedAt = activeStartedAt.addingTimeInterval(
                -Double(historyIndex + 1) * 86_400
            )
            let completedSession = makeLargeSession(
                title: "Performance History \(String(format: "%03d", historyIndex + 1))",
                startedAt: startedAt,
                status: .completed,
                ownerTokenIdentifier: ownerTokenIdentifier
            )
            context.insert(completedSession)
        }

        try context.save()
    }

    private static func makeLargeSession(
        title: String,
        startedAt: Date,
        status: WorkoutSessionStatus,
        ownerTokenIdentifier: String?
    ) -> WorkoutSession {
        let endedAt = status == .completed
            ? startedAt.addingTimeInterval(3_600)
            : nil
        let updateDate = endedAt ?? startedAt
        let loggedExercises = largeExerciseFixtures.enumerated().map {
            exerciseIndex,
            fixture in
            let sets = (0..<5).map { setIndex in
                LoggedSet(
                    orderIndex: setIndex,
                    weight: 95 + Double(exerciseIndex * 10 + setIndex * 5),
                    reps: 5 + setIndex,
                    rpe: status == .completed ? 7 + (Double(setIndex) * 0.5) : nil,
                    isCompleted: status == .completed,
                    completedAt: endedAt,
                    createdAt: startedAt,
                    updatedAt: updateDate
                )
            }

            return LoggedExercise(
                orderIndex: exerciseIndex,
                exerciseSnapshotName: fixture.name,
                exerciseSnapshotEquipmentRaw: fixture.equipment.rawValue,
                exerciseSnapshotPrimaryMuscleGroupRaw: fixture.muscle.rawValue,
                createdAt: startedAt,
                updatedAt: updateDate,
                sets: sets
            )
        }

        return WorkoutSession(
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: status == .completed ? 3_600 : 0,
            status: status,
            source: .blank,
            createdAt: startedAt,
            updatedAt: updateDate,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            loggedExercises: loggedExercises
        )
    }

    private static let largeExerciseFixtures: [
        (name: String, equipment: ExerciseEquipment, muscle: ExerciseMuscleGroup)
    ] = [
        ("Bench Press", .barbell, .chest),
        ("Back Squat", .barbell, .quads),
        ("Conventional Deadlift", .barbell, .glutes),
        ("Overhead Press", .barbell, .shoulders),
        ("Barbell Row", .barbell, .upperBack),
        ("Pull-Up", .bodyweight, .lats),
        ("Romanian Deadlift", .barbell, .hamstrings),
        ("Incline Dumbbell Press", .dumbbell, .chest),
        ("Lateral Raise", .dumbbell, .shoulders),
        ("Barbell Curl", .barbell, .biceps),
    ]

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
