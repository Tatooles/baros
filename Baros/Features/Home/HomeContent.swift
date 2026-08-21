import Foundation

struct HomePrimaryWorkoutPresentation: Equatable {
    let title: String
    let detail: String?
    let accessibilityIdentifier: String
    let isActive: Bool

    init(activeSession: WorkoutSession?, now: Date) {
        guard let activeSession else {
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
    let completedAt: Date

    init(session: WorkoutSession) {
        completedAt = session.endedAt ?? session.startedAt
    }
}

struct HomeContent {
    let completedSessions: [WorkoutSession]
    let weeklyActivity: HomeWeeklyActivity

    var lastWorkout: WorkoutSession? {
        completedSessions.first
    }

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
        weeklyActivity = HomeWeeklyActivity(
            completedSessions: completedSessions,
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

struct HomeWeeklyActivity: Equatable {
    struct Day: Identifiable, Equatable {
        let date: Date
        let hasCompletedWorkout: Bool
        let isToday: Bool

        var id: Date { date }
    }

    let days: [Day]
    let completedWorkoutCount: Int

    init(
        completedSessions: [WorkoutSession],
        now: Date,
        calendar: Calendar
    ) {
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let weekStart = weekInterval?.start ?? calendar.startOfDay(for: now)
        let weekEnd = weekInterval?.end
            ?? calendar.date(byAdding: .day, value: 7, to: weekStart)
            ?? weekStart
        let sessionsThisWeek = completedSessions.filter { session in
            session.startedAt >= weekStart && session.startedAt < weekEnd
        }

        completedWorkoutCount = sessionsThisWeek.count
        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }
            return Day(
                date: date,
                hasCompletedWorkout: sessionsThisWeek.contains { session in
                    calendar.isDate(session.startedAt, inSameDayAs: date)
                },
                isToday: calendar.isDate(date, inSameDayAs: now)
            )
        }
    }

    func accessibilityDescription(
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let workoutLabel = completedWorkoutCount == 1 ? "workout" : "workouts"
        let completedDays = days.filter(\.hasCompletedWorkout)
        guard !completedDays.isEmpty else {
            return "\(completedWorkoutCount) \(workoutLabel) completed this week."
        }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = locale
        weekdayFormatter.timeZone = calendar.timeZone
        weekdayFormatter.dateFormat = "EEEE"
        let weekdayNames = completedDays.map { weekdayFormatter.string(from: $0.date) }
        let listFormatter = ListFormatter()
        listFormatter.locale = locale
        let dayList = listFormatter.string(from: weekdayNames) ?? weekdayNames.joined(separator: ", ")
        return "\(completedWorkoutCount) \(workoutLabel) completed this week: \(dayList)."
    }
}
