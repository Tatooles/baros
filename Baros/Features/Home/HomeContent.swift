import Foundation

struct HomePrimaryWorkoutPresentation: Equatable {
    let title: String
    let detail: String?
    let accessibilityIdentifier: String
    let isActive: Bool

    init(
        activeSession: WorkoutSession?,
        sessionIDHiddenDuringLaunchHandoff: UUID? = nil,
        now: Date
    ) {
        guard let activeSession,
              activeSession.id != sessionIDHiddenDuringLaunchHandoff else {
            title = "Start Workout"
            detail = nil
            accessibilityIdentifier = "StartWorkoutButton"
            isActive = false
            return
        }

        title = "Return to Workout"
        detail = "\(activeSession.title) · "
            + WorkoutFormatters.homeElapsedDescription(activeSession.effectiveDurationSeconds(now: now))
        accessibilityIdentifier = "ReturnToActiveWorkoutButton"
        isActive = true
    }
}

struct HomePastWorkoutReviewPresentation: Equatable {
    struct Exercise: Equatable, Identifiable {
        let id: UUID
        let name: String
        let equipment: String?
        let copiedSetCount: Int

        var copiedSetDescription: String {
            "\(copiedSetCount) \(copiedSetCount == 1 ? "set" : "sets")"
        }
    }

    let completedAt: Date
    let copiedSetCount: Int
    let exercises: [Exercise]

    var structureSummary: String {
        let exerciseLabel = exercises.count == 1 ? "exercise" : "exercises"
        let setLabel = copiedSetCount == 1 ? "set" : "sets"
        return "\(exercises.count) \(exerciseLabel) · \(copiedSetCount) \(setLabel)"
    }

    init(session: WorkoutSession) {
        completedAt = session.endedAt ?? session.startedAt
        exercises = session.sortedLoggedExercises.map { loggedExercise in
            Exercise(
                id: loggedExercise.id,
                name: loggedExercise.exerciseSnapshotName,
                equipment: loggedExercise.snapshotEquipment?.displayName,
                copiedSetCount: loggedExercise.sortedSets.count
            )
        }
        copiedSetCount = exercises.reduce(0) { $0 + $1.copiedSetCount }
    }
}

struct HomeContent {
    let completedSessions: [WorkoutSession]
    let trainingCalendar: HomeTrainingCalendar
    let quickStartWorkouts: [HomeQuickStartWorkout]

    init(
        sessions: [WorkoutSession],
        ownerTokenIdentifier: String?,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        completedSessions = WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        trainingCalendar = HomeTrainingCalendar(
            completedSessions: completedSessions,
            now: now,
            calendar: calendar
        )
        quickStartWorkouts = HomeQuickStartWorkout.workouts(
            from: completedSessions,
            now: now,
            calendar: calendar
        )
    }

    func pastWorkouts(matching query: String) -> [WorkoutSession] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return completedSessions
        }

        return completedSessions.filter { session in
            session.title.localizedCaseInsensitiveContains(normalizedQuery)
                || session.sortedLoggedExercises.contains { loggedExercise in
                    loggedExercise.exerciseSnapshotName.localizedCaseInsensitiveContains(normalizedQuery)
                }
        }
    }
}

/// A recent distinct completed workout that Home offers to repeat.
struct HomeQuickStartWorkout: Identifiable {
    static let maximumCount = 5
    static let previewExerciseCount = 3

    let session: WorkoutSession
    let lastCompletedDescription: String
    let previewExerciseNames: [String]

    var id: UUID { session.id }
    var title: String { session.title }

    /// Expects `completedSessions` newest first. Custom titles group by title; workouts still using the
    /// default title group by their ordered exercises so unrenamed workouts stay distinguishable.
    static func workouts(
        from completedSessions: [WorkoutSession],
        now: Date,
        calendar: Calendar
    ) -> [HomeQuickStartWorkout] {
        var seenKeys = Set<String>()
        var workouts: [HomeQuickStartWorkout] = []
        for session in completedSessions where workouts.count < maximumCount {
            let exerciseNames = session.sortedLoggedExercises.map(\.exerciseSnapshotName)
            guard !exerciseNames.isEmpty,
                  seenKeys.insert(groupingKey(title: session.title, exerciseNames: exerciseNames)).inserted else {
                continue
            }
            workouts.append(HomeQuickStartWorkout(
                session: session,
                lastCompletedDescription: lastCompletedDescription(
                    for: session.startedAt,
                    now: now,
                    calendar: calendar
                ),
                previewExerciseNames: Array(exerciseNames.prefix(previewExerciseCount))
            ))
        }
        return workouts
    }

    private static func groupingKey(title: String, exerciseNames: [String]) -> String {
        let normalizedTitle = normalized(title)
        guard normalizedTitle == normalized(WorkoutSession.defaultTitle) else {
            return "title:\(normalizedTitle)"
        }
        return "exercises:" + exerciseNames.map(normalized).joined(separator: "\u{1F}")
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Days for the first two weeks, weeks until two calendar months, months for the first year, then years.
    private static func lastCompletedDescription(for date: Date, now: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        let months = calendar.dateComponents([.month], from: day, to: today).month ?? 0
        switch (days, months) {
        case (...0, _): return "Today"
        case (1, _): return "Yesterday"
        case (2..<14, _): return "\(days) days ago"
        case (_, ..<2): return "\(days / 7) weeks ago"
        case (_, ..<12): return "\(months) months ago"
        default:
            let years = months / 12
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }
    }
}

/// Calendar weeks of completed workouts, starting at the week of the first one so earlier weeks never
/// read as missed.
struct HomeTrainingCalendar: Equatable {
    static let maximumWeekCount = 12
    static let minimumVisibleWeekCount = 4

    enum DayState: Equatable {
        case completed
        case noWorkout
        case beforeFirstWorkout
        case upcoming
    }

    struct Day: Identifiable, Equatable {
        let date: Date
        let state: DayState
        let isToday: Bool

        var id: Date { date }
    }

    struct Week: Identifiable, Equatable {
        let start: Date
        let days: [Day]
        let completedWorkoutCount: Int
        let isCurrent: Bool

        var id: Date { start }
    }

    /// Oldest first; the last week is the current one.
    let weeks: [Week]
    let hasCompletedWorkouts: Bool

    init(completedSessions: [WorkoutSession], now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let firstWorkoutDate = completedSessions.map(\.startedAt).min()
        let historyStart = min(calendar.startOfDay(for: firstWorkoutDate ?? now), today)
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: historyStart)?.start ?? currentWeekStart
        let daysOfHistory = calendar.dateComponents([.day], from: firstWeekStart, to: currentWeekStart).day ?? 0
        let weekCount = min(daysOfHistory / 7 + 1, Self.maximumWeekCount)

        hasCompletedWorkouts = firstWorkoutDate != nil
        weeks = (0..<weekCount).reversed().compactMap { weeksBack in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: currentWeekStart),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else {
                return nil
            }
            let sessionsInWeek = completedSessions.filter { session in
                session.startedAt >= start && session.startedAt < end
            }
            let days = (0..<7).compactMap { offset -> Day? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                    return nil
                }
                let state: DayState = if sessionsInWeek.contains(where: {
                    calendar.isDate($0.startedAt, inSameDayAs: date)
                }) {
                    .completed
                } else if date > today {
                    .upcoming
                } else if date < historyStart {
                    .beforeFirstWorkout
                } else {
                    .noWorkout
                }
                return Day(date: date, state: state, isToday: date == today)
            }
            return Week(
                start: start,
                days: days,
                completedWorkoutCount: sessionsInWeek.count,
                isCurrent: weeksBack == 0
            )
        }
    }

    /// The most recent weeks that fit `capacity` rows, never fewer than the minimum (or all history if shorter).
    func visibleWeeks(fitting capacity: Int) -> ArraySlice<Week> {
        weeks.suffix(min(weeks.count, max(capacity, Self.minimumVisibleWeekCount)))
    }

    func accessibilityDescription(for visibleWeeks: ArraySlice<Week>) -> String {
        let thisWeek = visibleWeeks.last?.completedWorkoutCount ?? 0
        var description = "\(thisWeek) \(Self.workoutLabel(thisWeek)) this week."
        if visibleWeeks.count > 1 {
            let total = visibleWeeks.reduce(0) { $0 + $1.completedWorkoutCount }
            description += " \(total) \(Self.workoutLabel(total)) in the last \(visibleWeeks.count) weeks."
        }
        return description
    }

    private static func workoutLabel(_ count: Int) -> String {
        count == 1 ? "workout" : "workouts"
    }
}

/// Measured Home heights used to fit as many calendar weeks as the screen allows.
struct HomeLayoutMetrics: Equatable {
    var viewportHeight: CGFloat = 0
    var headerHeight: CGFloat = 0
    var actionsHeight: CGFloat = 0
    var calendarCardHeight: CGFloat = 0
    var calendarRowsHeight: CGFloat = 0
    var calendarRowCount = 0

    func calendarWeekCapacity(rowSpacing: CGFloat, fixedSpacing: CGFloat) -> Int {
        guard viewportHeight > 0, calendarRowCount > 0, calendarRowsHeight > 0 else { return 0 }
        let cardChrome = calendarCardHeight - calendarRowsHeight
        let rowPitch = (calendarRowsHeight + rowSpacing) / CGFloat(calendarRowCount)
        let available = viewportHeight - fixedSpacing - headerHeight - actionsHeight - cardChrome
        return max(0, Int(((available + rowSpacing) / rowPitch).rounded(.down)))
    }
}
