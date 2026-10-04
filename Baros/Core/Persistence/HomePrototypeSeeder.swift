// PROTOTYPE — throwaway. Seeds ~10 weeks of a Push/Pull/Legs rotation for the Home redesign
// prototype. Launch with `--prototype-seed-home`. Lives on branch prototype/home-redesign only.
#if DEBUG
import Foundation
import SwiftData

extension UITestFixtureSeeder {
    static let prototypeHomeArgument = "--prototype-seed-home"

    private struct PrototypeExercise {
        let name: String
        let equipment: ExerciseEquipment
        let weight: Double?
        let reps: Int
        let sets: Int
    }

    static func seedPrototypeHome(ownerTokenIdentifier: String?, context: ModelContext) throws {
        let rotation: [(String, [PrototypeExercise])] = [
            ("Push Day", [
                .init(name: "Bench Press", equipment: .barbell, weight: 185, reps: 5, sets: 4),
                .init(name: "Overhead Press", equipment: .barbell, weight: 105, reps: 6, sets: 3),
                .init(name: "Incline Dumbbell Press", equipment: .dumbbell, weight: 55, reps: 10, sets: 3),
                .init(name: "Triceps Pushdown", equipment: .cable, weight: 50, reps: 12, sets: 3),
                .init(name: "Lateral Raise", equipment: .dumbbell, weight: 20, reps: 15, sets: 3),
            ]),
            ("Pull Day", [
                .init(name: "Deadlift", equipment: .barbell, weight: 295, reps: 5, sets: 3),
                .init(name: "Pull-Up", equipment: .bodyweight, weight: nil, reps: 8, sets: 3),
                .init(name: "Barbell Row", equipment: .barbell, weight: 145, reps: 8, sets: 3),
                .init(name: "Face Pull", equipment: .cable, weight: 40, reps: 15, sets: 3),
                .init(name: "Hammer Curl", equipment: .dumbbell, weight: 30, reps: 10, sets: 3),
            ]),
            ("Leg Day", [
                .init(name: "Back Squat", equipment: .barbell, weight: 225, reps: 5, sets: 4),
                .init(name: "Romanian Deadlift", equipment: .barbell, weight: 185, reps: 8, sets: 3),
                .init(name: "Leg Press", equipment: .machine, weight: 340, reps: 10, sets: 3),
                .init(name: "Walking Lunge", equipment: .dumbbell, weight: 35, reps: 12, sets: 3),
                .init(name: "Standing Calf Raise", equipment: .machine, weight: 135, reps: 15, sets: 3),
            ]),
        ]

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Days-ago for each workout, oldest first. Mon/Wed/Fri-ish, a skipped week, a light week.
        var daysAgo: [Int] = []
        for week in stride(from: 9, through: 0, by: -1) where week != 4 {
            let base = week * 7
            daysAgo += week == 7 ? [base + 6, base + 3] : [base + 6, base + 4, base + 2]
        }

        for (index, ago) in daysAgo.enumerated() {
            let (title, exercises) = rotation[index % rotation.count]
            let progress = Double(index / rotation.count) * 5
            guard let day = calendar.date(byAdding: .day, value: -ago, to: today),
                  let startedAt = calendar.date(byAdding: .hour, value: 18, to: day) else { continue }
            let duration = 3_300 + (index % 4) * 420
            let endedAt = startedAt.addingTimeInterval(TimeInterval(duration))

            let loggedExercises = exercises.enumerated().map { exerciseIndex, exercise in
                LoggedExercise(
                    orderIndex: exerciseIndex,
                    exerciseSnapshotName: exercise.name,
                    exerciseSnapshotEquipmentRaw: exercise.equipment.rawValue,
                    createdAt: startedAt,
                    updatedAt: endedAt,
                    sets: (0..<exercise.sets).map { setIndex in
                        LoggedSet(
                            orderIndex: setIndex,
                            weight: exercise.weight.map { $0 + (exerciseIndex < 2 ? progress : progress / 2) },
                            reps: exercise.reps,
                            isCompleted: true,
                            completedAt: endedAt,
                            createdAt: startedAt,
                            updatedAt: endedAt
                        )
                    }
                )
            }

            context.insert(WorkoutSession(
                title: title,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: duration,
                status: .completed,
                source: .blank,
                createdAt: startedAt,
                updatedAt: endedAt,
                syncOwnerTokenIdentifier: ownerTokenIdentifier,
                loggedExercises: loggedExercises
            ))
        }
        try context.save()
    }
}
#endif
