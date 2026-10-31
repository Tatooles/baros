import Foundation

/// Store-independent input. Durations are elapsed seconds, not active-set time.
struct RingWorkout: Equatable {
    let date: Date
    let duration: TimeInterval
    /// Nil for value-only DEBUG fixtures, which preview but never open.
    var id: UUID? = nil
    var title: String = WorkoutSession.defaultTitle

    /// Reads only stored attributes; exercise counts are resolved for the scrubbed slot, not all history.
    static func ringWorkouts(from sessions: [WorkoutSession], now: Date) -> [RingWorkout] {
        sessions.compactMap { session in
            let end = session.endedAt ?? session.startedAt
            guard end <= now else { return nil }
            return RingWorkout(date: session.startedAt, duration: TimeInterval(session.effectiveDurationSeconds(now: now)),
                               id: session.id, title: session.title)
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
    /// Scrubbable slots keyed by angle index, oldest first: Month days and the outer Year lap's weeks.
    let monthSlotWorkouts: [Int: [RingWorkout]]
    let yearSlotWorkouts: [Int: [RingWorkout]]
    let today: Date
    let thisWeek: Date

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
        var monthSlots: [Int: [RingWorkout]] = [:]
        var yearSlots: [Int: [RingWorkout]] = [:]

        for (day, workoutsOnDay) in daily {
            // Sum first: a double workout still occupies exactly one day on the dial.
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

    func spokes(for period: HomeRingPeriod) -> [HomeRingSpoke] {
        period == .month ? monthSpokes : yearSpokes
    }

    /// Rest ticks belong only to the current lap, never to the historical tree rings.
    func emptySlotIndices(for period: HomeRingPeriod) -> [Int] {
        let trained = Set(spokes(for: period).filter { $0.lap == 0 }.map(\.angleIndex))
        return (0..<period.slotCount).reversed().filter { !trained.contains($0) }
    }

    func workouts(for period: HomeRingPeriod, at index: Int) -> [RingWorkout] {
        (period == .month ? monthSlotWorkouts : yearSlotWorkouts)[index] ?? []
    }

    /// The day (Month) or week start (Year) that a slot stands for.
    func slotStart(for period: HomeRingPeriod, at index: Int, calendar: Calendar) -> Date {
        period == .month
            ? calendar.date(byAdding: .day, value: -index, to: today) ?? today
            : calendar.date(byAdding: .day, value: -7 * index, to: thisWeek) ?? thisWeek
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

/// Facts about one scrubbed slot, shown in the ring's center. It never suggests what to do next.
struct HomeRingSlotPreview: Equatable {
    struct Row: Equatable {
        /// The weekday in Year view, where a slot spans a week.
        let label: String?
        let title: String
    }

    static let maximumRows = 5

    let dateText: String
    /// A lone Month workout gets a large title; everything else is a list of workouts.
    let title: String?
    let rows: [Row]
    /// Workouts beyond `maximumRows`, summarized as "+N more".
    let hiddenCount: Int
    let detail: String?
    /// Oldest first. Empty for rest slots and value-only fixtures, which never open.
    let workoutIDs: [UUID]

    var accessibilityValue: String {
        let listed = rows.map { [$0.label, $0.title].compactMap { $0 }.joined(separator: " ") }
        let more = hiddenCount > 0 ? ["\(hiddenCount) more"] : []
        return ([dateText, title].compactMap { $0 } + listed + more + [detail].compactMap { $0 }).joined(separator: ". ")
    }

    /// `exerciseCount` loads logged exercises, so it runs only for a lone Month workout.
    init(model: HomeRingModel, period: HomeRingPeriod, index: Int, calendar: Calendar,
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

    /// Labels follow the ring's calendar and time zone, so a slot never reads as a neighboring day.
    private static func dateStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }
}

/// Maps a touch to the slot under it. Index zero sits at 12 o'clock and indices run counterclockwise.
enum HomeRingScrubGeometry {
    static func slotIndex(at location: CGPoint, center: CGPoint, slotCount: Int) -> Int {
        let angle = atan2(location.y - center.y, location.x - center.x)
        let turns = (-Double.pi / 2 - angle) / (2 * .pi)
        let raw = Int((turns * Double(slotCount)).rounded())
        return ((raw % slotCount) + slotCount) % slotCount
    }
}
