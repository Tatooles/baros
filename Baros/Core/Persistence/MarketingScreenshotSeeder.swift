import Foundation
import SwiftData

#if DEBUG
/// Data and display state for the App Store and baros.fit screenshots that
/// `MarketingScreenshotTests` captures. See `docs/release/listing.md`.
enum MarketingScreenshotSeeder {
    /// Seeds about a year of progressive training plus the matching templates.
    static let seedArgument = "--uitest-seed-marketing"
    /// Hides debug-only chrome, such as the DEV badge, that a shipped build never shows.
    static let captureArgument = "--uitest-marketing-capture"

    static var isCapturing: Bool {
        ProcessInfo.processInfo.arguments.contains(captureArgument)
    }

    private struct Lift {
        let seed: String
        let start: Double
        let end: Double
        let reps: Int
        let sets: Int
        let ratesLastSet: Bool
        /// Neighboring lifts with the same group are logged as a superset.
        var superset: Int? = nil
    }

    private static let plans: [(title: String, lifts: [Lift])] = [
        ("Push Day", [
            Lift(seed: "bench-press", start: 165, end: 205, reps: 5, sets: 4, ratesLastSet: true),
            Lift(seed: "overhead-press", start: 95, end: 125, reps: 6, sets: 3, ratesLastSet: true),
            Lift(seed: "incline-dumbbell-press", start: 50, end: 65, reps: 10, sets: 3, ratesLastSet: false),
            Lift(seed: "triceps-pushdown", start: 50, end: 70, reps: 12, sets: 3, ratesLastSet: false),
        ]),
        ("Pull Day", [
            Lift(seed: "barbell-row", start: 135, end: 175, reps: 8, sets: 4, ratesLastSet: true),
            Lift(seed: "lat-pulldown", start: 120, end: 150, reps: 10, sets: 3, ratesLastSet: false),
            Lift(seed: "seated-cable-row", start: 110, end: 140, reps: 10, sets: 3, ratesLastSet: false),
            Lift(seed: "face-pull", start: 40, end: 55, reps: 15, sets: 3, ratesLastSet: false, superset: 1),
            Lift(seed: "biceps-curl", start: 25, end: 35, reps: 10, sets: 3, ratesLastSet: false, superset: 1),
        ]),
        ("Leg Day", [
            Lift(seed: "back-squat", start: 205, end: 265, reps: 5, sets: 4, ratesLastSet: true),
            Lift(seed: "romanian-deadlift", start: 165, end: 215, reps: 8, sets: 3, ratesLastSet: true),
            Lift(seed: "leg-press", start: 270, end: 360, reps: 10, sets: 3, ratesLastSet: false),
            Lift(seed: "leg-curl", start: 80, end: 105, reps: 12, sets: 3, ratesLastSet: false, superset: 1),
            Lift(seed: "calf-raise", start: 135, end: 180, reps: 12, sets: 3, ratesLastSet: false, superset: 1),
        ]),
        ("Upper Body", [
            Lift(seed: "incline-dumbbell-press", start: 55, end: 75, reps: 10, sets: 3, ratesLastSet: false, superset: 1),
            Lift(seed: "dumbbell-row", start: 55, end: 75, reps: 10, sets: 3, ratesLastSet: false, superset: 1),
            Lift(seed: "lat-pulldown", start: 110, end: 140, reps: 12, sets: 3, ratesLastSet: false),
            Lift(seed: "triceps-pushdown", start: 45, end: 65, reps: 12, sets: 3, ratesLastSet: false),
            Lift(seed: "biceps-curl", start: 25, end: 35, reps: 12, sets: 2, ratesLastSet: false),
        ]),
    ]

    /// Four sessions a week (Mon push, Tue pull, Thu legs, Sat upper) for 48 weeks, with two
    /// vacation weeks, occasional skipped days, deloads every fourth week, and a few notes.
    static func seed(ownerTokenIdentifier: String?, context: ModelContext, now: Date = .now,
                     calendar: Calendar = .current) throws {
        let library = Exercise.visibleActiveExercises(
            from: try context.fetch(FetchDescriptor<Exercise>()),
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        func exercise(_ seed: String) -> Exercise? { library.first { $0.seedIdentifier == seed } }

        for plan in plans {
            let groups = Dictionary(uniqueKeysWithValues: Set(plan.lifts.compactMap(\.superset)).map { ($0, UUID()) })
            let entries = plan.lifts.compactMap { lift -> WorkoutTemplateEntry? in
                exercise(lift.seed).map { WorkoutTemplateEntry(exercise: $0, supersetGroupID: lift.superset.flatMap { groups[$0] }) }
            }
            context.insert(WorkoutTemplate(name: plan.title, entries: entries,
                                           syncOwnerTokenIdentifier: ownerTokenIdentifier))
        }

        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        guard let thisMonday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) else { return }
        let totalWeeks = 48
        let dayOffsets = [0, 1, 3, 5]
        let notes = [
            "Paused the first rep of every bench set.",
            "Felt strong. Add 5 lb next week.",
            "Short on time, kept rest to 2 minutes.",
        ]
        var latestPushDay: WorkoutSession?
        for week in 0..<totalWeeks where week != 13 && week != 30 {
            guard let monday = calendar.date(byAdding: .day, value: -7 * (totalWeeks - 1 - week), to: thisMonday) else {
                continue
            }
            let progress = Double(week) / Double(totalWeeks - 1)
            for (slot, offset) in dayOffsets.enumerated() {
                if slot == 3 && week % 5 == 2 { continue }
                if slot == 1 && week % 9 == 4 { continue }
                guard let day = calendar.date(byAdding: .day, value: offset, to: monday), day < today,
                      let startedAt = calendar.date(bySettingHour: slot == 3 ? 10 : 18,
                                                    minute: [5, 20, 35, 10][(week + slot) % 4], second: 0, of: day)
                else { continue }
                let plan = plans[slot]
                let duration = (50 + (week * 7 + slot * 11) % 24) * 60 + (week * 37 + slot * 13) % 60
                let setCount = plan.lifts.reduce(0) { $0 + $1.sets }
                let groups = Dictionary(uniqueKeysWithValues: Set(plan.lifts.compactMap(\.superset)).map { ($0, UUID()) })
                var elapsed = 4.0 * 60
                let exercises = plan.lifts.enumerated().map { index, lift -> LoggedExercise in
                    let deload = week % 4 == 3 ? 5.0 : 0
                    let increment = lift.start < 60 ? 2.5 : 5
                    let weight = ((lift.start + (lift.end - lift.start) * progress - deload) / increment).rounded() * increment
                    let sets = (0..<lift.sets).map { setIndex -> LoggedSet in
                        let isLast = setIndex == lift.sets - 1
                        elapsed += Double(duration) / Double(setCount + 1)
                        return LoggedSet(
                            orderIndex: setIndex, weight: weight,
                            reps: lift.reps - (isLast && (week + index) % 3 == 0 ? 1 : 0),
                            rpe: lift.ratesLastSet && isLast ? [8, 8.5, 9][(week + setIndex) % 3] : nil,
                            isCompleted: true, completedAt: startedAt.addingTimeInterval(elapsed),
                            createdAt: startedAt, updatedAt: startedAt.addingTimeInterval(elapsed)
                        )
                    }
                    let library = exercise(lift.seed)
                    return LoggedExercise(
                        orderIndex: index, exercise: library,
                        exerciseSnapshotName: library?.name, exerciseSnapshotEquipmentRaw: library?.equipmentRaw,
                        exerciseSnapshotPrimaryMuscleGroupRaw: library?.primaryMuscleGroupRaw,
                        supersetGroupID: lift.superset.flatMap { groups[$0] },
                        createdAt: startedAt, updatedAt: startedAt, sets: sets
                    )
                }
                let endedAt = startedAt.addingTimeInterval(Double(duration))
                let session = WorkoutSession(
                    title: plan.title, startedAt: startedAt, endedAt: endedAt, durationSeconds: duration,
                    notes: (week * 4 + slot) % 11 == 0 ? notes[(week + slot) % notes.count] : "",
                    status: .completed, source: .blank, createdAt: endedAt, updatedAt: endedAt,
                    syncOwnerTokenIdentifier: ownerTokenIdentifier, loggedExercises: exercises
                )
                context.insert(session)
                if slot == 0 { latestPushDay = session }
            }
        }
        // The workout-detail shot opens the latest Push Day, so it carries a note.
        latestPushDay?.notes = notes[0]
        try context.save()
    }
}
#endif
