import Foundation
import SwiftData

#if DEBUG
/// Data and display state for the App Store and baros.fit screenshots that
/// `MarketingScreenshotTests` captures. See the release skill's LISTING.md.
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

    private struct Plan {
        let title: String
        /// Days before today in the most recent week; each earlier week repeats 7 days back.
        let daysBack: Int
        let lifts: [Lift]
    }

    /// Each library exercise belongs to one plan, so an exercise's "previous" values always
    /// come from the plan the screenshot shows.
    private static let plans: [Plan] = [
        Plan(title: "Push Day", daysBack: 6, lifts: [
            Lift(seed: "bench-press", start: 165, end: 205, reps: 5, sets: 4, ratesLastSet: true),
            Lift(seed: "overhead-press", start: 95, end: 125, reps: 6, sets: 3, ratesLastSet: true),
            Lift(seed: "triceps-pushdown", start: 50, end: 70, reps: 12, sets: 3, ratesLastSet: false),
        ]),
        Plan(title: "Pull Day", daysBack: 5, lifts: [
            Lift(seed: "barbell-row", start: 135, end: 175, reps: 8, sets: 4, ratesLastSet: true),
            Lift(seed: "lat-pulldown", start: 120, end: 150, reps: 10, sets: 3, ratesLastSet: false),
            Lift(seed: "seated-cable-row", start: 110, end: 140, reps: 10, sets: 3, ratesLastSet: false),
            Lift(seed: "face-pull", start: 40, end: 55, reps: 15, sets: 3, ratesLastSet: false, superset: 1),
            Lift(seed: "biceps-curl", start: 25, end: 35, reps: 10, sets: 3, ratesLastSet: false, superset: 1),
        ]),
        Plan(title: "Leg Day", daysBack: 3, lifts: [
            Lift(seed: "back-squat", start: 205, end: 265, reps: 5, sets: 4, ratesLastSet: true),
            Lift(seed: "romanian-deadlift", start: 165, end: 215, reps: 8, sets: 3, ratesLastSet: true),
            Lift(seed: "leg-press", start: 270, end: 360, reps: 10, sets: 3, ratesLastSet: false),
            Lift(seed: "leg-curl", start: 80, end: 105, reps: 12, sets: 3, ratesLastSet: false, superset: 1),
            Lift(seed: "calf-raise", start: 135, end: 180, reps: 12, sets: 3, ratesLastSet: false, superset: 1),
        ]),
        // Opens with its superset, so the superset shot needs no scrolling.
        Plan(title: "Full Body", daysBack: 1, lifts: [
            Lift(seed: "incline-dumbbell-press", start: 55, end: 75, reps: 10, sets: 3, ratesLastSet: false, superset: 1),
            Lift(seed: "dumbbell-row", start: 55, end: 75, reps: 10, sets: 3, ratesLastSet: false, superset: 1),
            Lift(seed: "conventional-deadlift", start: 275, end: 345, reps: 5, sets: 3, ratesLastSet: true),
            Lift(seed: "front-squat", start: 155, end: 205, reps: 6, sets: 3, ratesLastSet: false),
        ]),
    ]

    /// Four sessions a week for 48 weeks, counted back from today so every run produces the
    /// same history: two vacation weeks, occasional skipped sessions, a deload every fourth
    /// week, and a few notes. The three most recent weeks are complete and at full weight,
    /// because they feed the "previous" values and the Start-from pills.
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
        let totalWeeks = 48
        let notes = [
            "Paused the first rep of every bench set.",
            "Felt strong. Add 5 lb next week.",
            "Short on time, kept rest to 2 minutes.",
        ]
        var latestPushDay: WorkoutSession?
        for weeksBack in (0..<totalWeeks).reversed() where weeksBack != 17 && weeksBack != 34 {
            let isRecent = weeksBack < 3
            let progress = Double(totalWeeks - 1 - weeksBack) / Double(totalWeeks - 1)
            let deload = !isRecent && weeksBack % 4 == 1
            for (slot, plan) in plans.enumerated() {
                if !isRecent && slot == 3 && weeksBack % 5 == 2 { continue }
                if !isRecent && slot == 1 && weeksBack % 9 == 4 { continue }
                guard let day = calendar.date(byAdding: .day, value: -(7 * weeksBack + plan.daysBack), to: today),
                      let startedAt = calendar.date(bySettingHour: slot == 3 ? 10 : 18,
                                                    minute: [5, 20, 35, 10][(weeksBack + slot) % 4], second: 0, of: day)
                else { continue }
                let duration = (52 + (weeksBack * 7 + slot * 11) % 24) * 60 + (weeksBack * 37 + slot * 13 + 23) % 60
                let setCount = plan.lifts.reduce(0) { $0 + $1.sets }
                let groups = Dictionary(uniqueKeysWithValues: Set(plan.lifts.compactMap(\.superset)).map { ($0, UUID()) })
                var elapsed = 4.0 * 60
                let exercises = plan.lifts.enumerated().map { index, lift -> LoggedExercise in
                    let increment = lift.start < 60 ? 2.5 : 5
                    let target = lift.start + (lift.end - lift.start) * progress - (deload ? 10 : 0)
                    let weight = (target / increment).rounded() * increment
                    let sets = (0..<lift.sets).map { setIndex -> LoggedSet in
                        let isLast = setIndex == lift.sets - 1
                        elapsed += Double(duration) / Double(setCount + 1)
                        return LoggedSet(
                            orderIndex: setIndex, weight: weight,
                            reps: lift.reps - (!isRecent && isLast && (weeksBack + index) % 3 == 0 ? 1 : 0),
                            rpe: lift.ratesLastSet && isLast ? [8, 8.5, 9][(weeksBack + setIndex) % 3] : nil,
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
                    notes: (weeksBack * 4 + slot) % 11 == 0 ? notes[(weeksBack + slot) % notes.count] : "",
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
