import Foundation
import SwiftData

#if DEBUG
enum UITestFixtureSeeder {
    static let completedBenchWorkoutArgument = "--uitest-seed-completed-bench-workout"

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
