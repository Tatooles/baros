import Foundation

/// Store-independent input. Durations are elapsed seconds, not active-set time.
struct RingWorkout: Equatable {
    let date: Date
    let duration: TimeInterval

    static func ringWorkouts(from sessions: [WorkoutSession], now: Date) -> [RingWorkout] {
        sessions.compactMap { session in
            let end = session.endedAt ?? session.startedAt
            guard end <= now else { return nil }
            return RingWorkout(date: session.startedAt, duration: TimeInterval(session.effectiveDurationSeconds(now: now)))
        }
    }
}

enum HomeRingPeriod: String, CaseIterable {
    case month, year

    var title: String { self == .month ? "Month" : "Year" }
    var slotCount: Int { self == .month ? 30 : 52 }

    static let storageKey = "HomeRingPeriod"

    static func resetForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--uitest-reset-home-ring-period") else { return }
        defaults.removeObject(forKey: storageKey)
    }
}

struct HomeRingSpoke: Equatable {
    /// Zero is today / this week. Increasing indices run counterclockwise.
    let angleIndex: Int
    let normalizedLength: Double
    /// Zero is the outer lap; 1...3 are earlier 52-week windows.
    let lap: Int

    /// Month length as a fraction of the dial diameter: 8.4...56 pt at 350 pt.
    /// The daily 20...90 minute scale is linear; Year keeps its existing scale.
    var monthLengthFraction: Double {
        0.024 + min(1, max(0, normalizedLength)) * 0.136
    }
}

struct HomeRingModel: Equatable {
    let totalWorkouts: Int
    let monthWorkoutCount: Int
    let yearWorkoutCount: Int
    let monthSpokes: [HomeRingSpoke]
    let yearSpokes: [HomeRingSpoke]

    /// Year adds history only when a past workout falls outside Month's daily window.
    var showsPeriodToggle: Bool { totalWorkouts > monthWorkoutCount }

    static func cappedDailyMinutes(_ seconds: TimeInterval) -> Double {
        min(90, max(20, seconds.isFinite ? seconds / 60 : 0))
    }

    init(workouts: [RingWorkout], now: Date, calendar: Calendar) {
        let past = workouts.filter { $0.date <= now }
        totalWorkouts = past.count
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let daily = Dictionary(grouping: past, by: { calendar.startOfDay(for: $0.date) })
        var months: [HomeRingSpoke] = []
        var weeklyMinutes: [Int: Double] = [:]
        var monthCount = 0
        var yearCount = 0

        for (day, workoutsOnDay) in daily {
            // Sum first: a double workout still occupies exactly one day on the dial.
            let minutes = Self.cappedDailyMinutes(workoutsOnDay.reduce(0) { $0 + max(0, $1.duration) })
            let daysBack = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            if (0..<30).contains(daysBack) {
                months.append(HomeRingSpoke(angleIndex: daysBack, normalizedLength: (minutes - 20) / 70, lap: 0))
                monthCount += workoutsOnDay.count
            }
            let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            // Calendar days, rather than seconds / 604800, preserve DST boundaries.
            let weeksBack = (calendar.dateComponents([.day], from: week, to: thisWeek).day ?? 0) / 7
            if (0..<208).contains(weeksBack) {
                weeklyMinutes[weeksBack, default: 0] += minutes
                if weeksBack < 52 { yearCount += workoutsOnDay.count }
            }
        }
        monthWorkoutCount = monthCount
        yearWorkoutCount = yearCount
        monthSpokes = months.sorted { $0.angleIndex > $1.angleIndex }
        yearSpokes = weeklyMinutes.keys.sorted(by: >).map { weeksBack in
            HomeRingSpoke(
                angleIndex: weeksBack % 52,
                normalizedLength: min(1, weeklyMinutes[weeksBack, default: 0] / (90 * 4)),
                lap: weeksBack / 52
            )
        }
    }

    func spokes(for period: HomeRingPeriod) -> [HomeRingSpoke] {
        period == .month ? monthSpokes : yearSpokes
    }

    /// Rest ticks belong only to the current lap, never to the historical tree rings.
    func emptySlotIndices(for period: HomeRingPeriod) -> [Int] {
        let trained = Set(spokes(for: period).filter { $0.lap == 0 }.map(\.angleIndex))
        return (0..<period.slotCount).reversed().filter { !trained.contains($0) }
    }

    func workoutCount(for period: HomeRingPeriod) -> Int {
        period == .month ? monthWorkoutCount : yearWorkoutCount
    }

    /// Caption under the center count; it names the same window the dial draws.
    func countCaption(for period: HomeRingPeriod) -> String {
        let noun = workoutCount(for: period) == 1 ? "workout" : "workouts"
        return "\(noun) in the past \(period == .month ? "30 days" : "year")"
    }

    func accessibilitySummary(period: HomeRingPeriod) -> String {
        guard totalWorkouts > 0 else { return "No workouts yet." }
        let count = workoutCount(for: period)
        let summary = "\(count) \(countCaption(for: period))."
        guard period == .year else { return summary }
        let weeks = yearSpokes.filter { $0.lap == 0 }.count
        return summary + " Trained in \(weeks) \(weeks == 1 ? "week" : "weeks")."
    }
}
