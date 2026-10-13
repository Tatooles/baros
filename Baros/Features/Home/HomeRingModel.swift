import Foundation

/// Store-independent input. Durations are elapsed seconds, not active-set time.
struct RingWorkout: Equatable {
    let date: Date
    let duration: TimeInterval
}

enum HomeRingPeriod: String, CaseIterable {
    case month, year

    var title: String { self == .month ? "Month" : "Year" }
    var slotCount: Int { self == .month ? 30 : 52 }
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
    let firstWorkoutDate: Date?
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
        firstWorkoutDate = past.map(\.date).min()
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

    func sinceDescription(now: Date, calendar: Calendar, abbreviated: Bool) -> String {
        guard let firstWorkoutDate else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(abbreviated ? "MMMyyyy" : "MMMMyyyy")
        return "\(totalWorkouts == 1 ? "workout" : "workouts") since \(formatter.string(from: firstWorkoutDate))"
    }

    func accessibilitySummary(period: HomeRingPeriod, now: Date, calendar: Calendar) -> String {
        guard totalWorkouts > 0 else { return "No workouts yet." }
        let window: String
        if period == .month {
            window = "Last 30 days: \(monthWorkoutCount) \(monthWorkoutCount == 1 ? "workout" : "workouts")."
        } else {
            let weeks = yearSpokes.filter { $0.lap == 0 }.count
            window = "Last 52 weeks: trained in \(weeks) \(weeks == 1 ? "week" : "weeks")."
        }
        return "\(window) \(totalWorkouts) \(sinceDescription(now: now, calendar: calendar, abbreviated: false))."
    }
}
