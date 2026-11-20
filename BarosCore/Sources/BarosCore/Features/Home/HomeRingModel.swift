import Foundation

public struct RingWorkout: Equatable {
    let date: Date
    let duration: TimeInterval
    var id: UUID? = nil
    var title: String = WorkoutSession.defaultTitle

    public static func ringWorkouts(from sessions: [WorkoutSession], now: Date) -> [RingWorkout] {
        sessions.compactMap { session in
            let end = session.endedAt ?? session.startedAt
            guard end <= now else { return nil }
            return RingWorkout(date: session.startedAt, duration: TimeInterval(session.effectiveDurationSeconds(now: now)),
                               id: session.id, title: session.title)
        }
    }
}

public enum HomeRingPeriod: String, CaseIterable {
    case month, year

    public var title: String { self == .month ? "Month" : "Year" }
    public var slotCount: Int { self == .month ? 30 : 52 }

    public static let storageKey = "HomeRingPeriod"

    public static func resetForUITestingIfRequested(arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--uitest-reset-home-ring-period") else { return }
        defaults.removeObject(forKey: storageKey)
    }
}

public struct HomeRingSpoke: Equatable {
    public let angleIndex: Int
    public let normalizedLength: Double
    public let lap: Int

    public var monthLengthFraction: Double {
        0.024 + min(1, max(0, normalizedLength)) * 0.136
    }
}

public struct HomeRingModel: Equatable {
    public let totalWorkouts: Int
    let monthWorkoutCount: Int
    let yearWorkoutCount: Int
    let monthSpokes: [HomeRingSpoke]
    public let yearSpokes: [HomeRingSpoke]
    let monthSlotWorkouts: [Int: [RingWorkout]]
    let yearSlotWorkouts: [Int: [RingWorkout]]
    let today: Date
    let thisWeek: Date

    public var showsPeriodToggle: Bool { totalWorkouts > monthWorkoutCount }

    static func cappedDailyMinutes(_ seconds: TimeInterval) -> Double {
        min(90, max(20, seconds.isFinite ? seconds / 60 : 0))
    }

    public init(workouts: [RingWorkout], now: Date, calendar: Calendar) {
        let past = workouts.filter { $0.date <= now }
        totalWorkouts = past.count
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let daily = Dictionary(grouping: past, by: { calendar.startOfDay(for: $0.date) })
        var months: [HomeRingSpoke] = []
        var weeklyMinutes: [Int: Double] = [:]
        var monthCount = 0
        var yearCount = 0
        var monthSlots: [Int: [RingWorkout]] = [:]
        var yearSlots: [Int: [RingWorkout]] = [:]

        for (day, workoutsOnDay) in daily {
            let minutes = Self.cappedDailyMinutes(workoutsOnDay.reduce(0) { $0 + max(0, $1.duration) })
            let daysBack = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            if (0..<30).contains(daysBack) {
                months.append(HomeRingSpoke(angleIndex: daysBack, normalizedLength: (minutes - 20) / 70, lap: 0))
                monthCount += workoutsOnDay.count
                monthSlots[daysBack] = workoutsOnDay
            }
            let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            // Calendar days, rather than seconds / 604800, preserve DST boundaries.
            let weeksBack = (calendar.dateComponents([.day], from: week, to: thisWeek).day ?? 0) / 7
            if (0..<208).contains(weeksBack) {
                weeklyMinutes[weeksBack, default: 0] += minutes
                if weeksBack < 52 {
                    yearCount += workoutsOnDay.count
                    yearSlots[weeksBack, default: []].append(contentsOf: workoutsOnDay)
                }
            }
        }
        monthWorkoutCount = monthCount
        yearWorkoutCount = yearCount
        monthSlotWorkouts = monthSlots.mapValues { $0.sorted { $0.date < $1.date } }
        yearSlotWorkouts = yearSlots.mapValues { $0.sorted { $0.date < $1.date } }
        self.today = today
        self.thisWeek = thisWeek
        monthSpokes = months.sorted { $0.angleIndex > $1.angleIndex }
        yearSpokes = weeklyMinutes.keys.sorted(by: >).map { weeksBack in
            HomeRingSpoke(
                angleIndex: weeksBack % 52,
                normalizedLength: min(1, weeklyMinutes[weeksBack, default: 0] / (90 * 4)),
                lap: weeksBack / 52
            )
        }
    }

    public func spokes(for period: HomeRingPeriod) -> [HomeRingSpoke] {
        period == .month ? monthSpokes : yearSpokes
    }

    public func emptySlotIndices(for period: HomeRingPeriod) -> [Int] {
        let trained = Set(spokes(for: period).filter { $0.lap == 0 }.map(\.angleIndex))
        return (0..<period.slotCount).reversed().filter { !trained.contains($0) }
    }

    public func workouts(for period: HomeRingPeriod, at index: Int) -> [RingWorkout] {
        (period == .month ? monthSlotWorkouts : yearSlotWorkouts)[index] ?? []
    }

    func slotStart(for period: HomeRingPeriod, at index: Int, calendar: Calendar) -> Date {
        period == .month
            ? calendar.date(byAdding: .day, value: -index, to: today) ?? today
            : calendar.date(byAdding: .day, value: -7 * index, to: thisWeek) ?? thisWeek
    }

    public func workoutCount(for period: HomeRingPeriod) -> Int {
        period == .month ? monthWorkoutCount : yearWorkoutCount
    }

    public func countCaption(for period: HomeRingPeriod) -> String {
        let noun = workoutCount(for: period) == 1 ? "workout" : "workouts"
        return "\(noun) in the past \(period == .month ? "30 days" : "year")"
    }

    public func accessibilitySummary(period: HomeRingPeriod) -> String {
        guard totalWorkouts > 0 else { return "No workouts yet." }
        let count = workoutCount(for: period)
        let summary = "\(count) \(countCaption(for: period))."
        guard period == .year else { return summary }
        let weeks = yearSpokes.filter { $0.lap == 0 }.count
        return summary + " Trained in \(weeks) \(weeks == 1 ? "week" : "weeks")."
    }
}

public struct HomeRingSlotPreview: Equatable {
    public struct Row: Equatable {
        public let label: String?
        public let title: String
    }

    static let maximumRows = 5

    public let dateText: String
    public let title: String?
    public let rows: [Row]
    public let hiddenCount: Int
    public let detail: String?
    public let workoutIDs: [UUID]

    public var accessibilityValue: String {
        let listed = rows.map { [$0.label, $0.title].compactMap { $0 }.joined(separator: " ") }
        let more = hiddenCount > 0 ? ["\(hiddenCount) more"] : []
        return ([dateText, title].compactMap { $0 } + listed + more + [detail].compactMap { $0 }).joined(separator: ". ")
    }

    public init(model: HomeRingModel, period: HomeRingPeriod, index: Int, calendar: Calendar,
         exerciseCount: (UUID) -> Int?) {
        let workouts = model.workouts(for: period, at: index)
        let start = model.slotStart(for: period, at: index, calendar: calendar)
        workoutIDs = workouts.compactMap(\.id)
        switch period {
        case .month:
            dateText = index == 0 ? "Today" : index == 1 ? "Yesterday"
                : start.formatted(Self.dateStyle(calendar).weekday(.abbreviated).month(.abbreviated).day())
        case .year:
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            dateText = index == 0 ? "This week" : (start..<end).formatted(Date.IntervalFormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .month(.abbreviated).day())
        }
        if period == .month, workouts.count == 1 {
            title = workouts[0].title
            rows = []
            hiddenCount = 0
            let exercises = workouts[0].id.flatMap(exerciseCount).flatMap { $0 > 0 ? WorkoutFormatters.exerciseCount($0) : nil }
            detail = [Self.durationText(workouts[0].duration), exercises].compactMap { $0 }.joined(separator: " · ")
            return
        }
        title = nil
        let shown = workouts.count > Self.maximumRows ? Self.maximumRows - 1 : workouts.count
        rows = workouts.prefix(shown).map { workout in
            Row(label: period == .year ? workout.date.formatted(Self.dateStyle(calendar).weekday(.abbreviated)) : nil, title: workout.title)
        }
        hiddenCount = workouts.count - shown
        detail = workouts.isEmpty ? (period == .month ? "No workout" : "No workouts") : nil
    }

    private static func dateStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }
}

public enum HomeRingScrubGeometry {
    public static func slotIndex(at location: CGPoint, center: CGPoint, slotCount: Int) -> Int {
        let angle = atan2(location.y - center.y, location.x - center.x)
        let turns = (-Double.pi / 2 - angle) / (2 * .pi)
        let raw = Int((turns * Double(slotCount)).rounded())
        return ((raw % slotCount) + slotCount) % slotCount
    }
}
