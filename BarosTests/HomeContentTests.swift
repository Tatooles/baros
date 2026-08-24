import Foundation
import XCTest
@testable import Baros

final class HomeContentTests: XCTestCase {
    func testPrimaryWorkoutPresentationStartsWhenThereIsNoActiveWorkout() {
        let presentation = HomePrimaryWorkoutPresentation(activeSession: nil, now: date(2026, 8, 19))

        XCTAssertEqual(presentation.title, "Start Workout")
        XCTAssertNil(presentation.detail)
        XCTAssertEqual(presentation.accessibilityIdentifier, "StartWorkoutButton")
    }

    func testPrimaryWorkoutPresentationReturnsWithNameAndMinuteElapsedTime() {
        let activeSession = session(
            title: "Upper Body",
            startedAt: date(2026, 8, 19, hour: 10),
            status: .active
        )

        let presentation = HomePrimaryWorkoutPresentation(
            activeSession: activeSession,
            now: date(2026, 8, 19, hour: 10).addingTimeInterval(3_899)
        )

        XCTAssertEqual(presentation.title, "Return to Workout")
        XCTAssertEqual(presentation.detail, "Upper Body · 1 hr 04 min elapsed")
        XCTAssertEqual(presentation.accessibilityIdentifier, "ReturnToActiveWorkoutButton")
    }

    func testPrimaryWorkoutPresentationStaysInStartStateDuringNewWorkoutLaunchHandoff() {
        let activeSession = session(
            title: "Upper Body",
            startedAt: date(2026, 8, 19, hour: 10),
            status: .active
        )

        let presentation = HomePrimaryWorkoutPresentation(
            activeSession: activeSession,
            sessionIDHiddenDuringLaunchHandoff: activeSession.id,
            now: date(2026, 8, 19, hour: 10)
        )

        XCTAssertEqual(presentation.title, "Start Workout")
        XCTAssertNil(presentation.detail)
        XCTAssertEqual(presentation.accessibilityIdentifier, "StartWorkoutButton")
    }

    func testContentUsesVisibleCompletedWorkoutsNewestFirstAndKeepsRecencyBasedOnStartDate() {
        let now = date(2026, 8, 19, hour: 12)
        let newest = session(
            title: "Newest by Start",
            startedAt: date(2026, 8, 18),
            updatedAt: date(2026, 8, 18)
        )
        let recentlyEditedOlder = session(
            title: "Edited Older",
            startedAt: date(2026, 8, 17),
            updatedAt: date(2026, 8, 19)
        )
        let active = session(
            title: "Active",
            startedAt: date(2026, 8, 19),
            status: .active
        )
        let deleted = session(
            title: "Deleted",
            startedAt: date(2026, 8, 19),
            deletedAt: now
        )

        let content = HomeContent(
            sessions: [recentlyEditedOlder, active, newest, deleted],
            ownerTokenIdentifier: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content.completedSessions.map(\.id), [newest.id, recentlyEditedOlder.id])
        XCTAssertEqual(content.lastWorkout?.id, newest.id)
    }

    func testContentAppliesCurrentOwnerVisibilityToEveryHomeCollection() {
        let unclaimed = session(title: "Unclaimed", startedAt: date(2026, 8, 18))
        let ownerA = session(
            title: "Owner A",
            startedAt: date(2026, 8, 19),
            ownerTokenIdentifier: "issuer|owner_a"
        )
        let ownerB = session(
            title: "Owner B",
            startedAt: date(2026, 8, 17),
            ownerTokenIdentifier: "issuer|owner_b"
        )

        let content = HomeContent(
            sessions: [ownerB, unclaimed, ownerA],
            ownerTokenIdentifier: "issuer|owner_a",
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(content.completedSessions.map(\.id), [ownerA.id, unclaimed.id])
        XCTAssertEqual(content.lastWorkout?.id, ownerA.id)
        XCTAssertEqual(content.weeklyActivity.completedWorkoutCount, 2)
    }

    func testPastWorkoutSearchMatchesTitlesAndExerciseNamesCaseInsensitivelyButNotNotes() {
        let titleMatch = session(
            title: "Upper Body",
            startedAt: date(2026, 8, 19),
            workoutNotes: "unrelated"
        )
        let exerciseMatch = session(
            title: "Strength",
            startedAt: date(2026, 8, 18),
            exerciseName: "Bench Press",
            exerciseNotes: "unrelated"
        )
        let workoutNoteOnly = session(
            title: "Lower Body",
            startedAt: date(2026, 8, 17),
            workoutNotes: "bench press"
        )
        let exerciseNoteOnly = session(
            title: "Conditioning",
            startedAt: date(2026, 8, 16),
            exerciseName: "Row",
            exerciseNotes: "upper body"
        )
        let content = HomeContent(
            sessions: [exerciseNoteOnly, workoutNoteOnly, exerciseMatch, titleMatch],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(content.pastWorkouts(matching: "upper BODY").map(\.id), [titleMatch.id])
        XCTAssertEqual(content.pastWorkouts(matching: "bEnCh").map(\.id), [exerciseMatch.id])
    }

    func testPastWorkoutSearchReturnsEveryEligibleWorkoutWithoutACap() {
        let sessions = (0..<12).map { index in
            session(
                title: "Workout \(index)",
                startedAt: date(2026, 8, 19).addingTimeInterval(TimeInterval(-index))
            )
        }
        let content = HomeContent(
            sessions: sessions.reversed(),
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(content.pastWorkouts(matching: "").count, 12)
        XCTAssertEqual(content.pastWorkouts(matching: "  ").count, 12)
        XCTAssertEqual(content.pastWorkouts(matching: "Workout 11").map(\.title), ["Workout 11"])
    }

    func testWeeklyActivityUsesStartDateWithBinaryDayMarkersAndCountsEveryCompletion() throws {
        let now = date(2026, 8, 19, hour: 12)
        let mondayMorning = session(title: "Monday One", startedAt: date(2026, 8, 17, hour: 8))
        let mondayEvening = session(title: "Monday Two", startedAt: date(2026, 8, 17, hour: 20))
        let wednesdayCrossMidnight = session(
            title: "Wednesday",
            startedAt: date(2026, 8, 19, hour: 23),
            endedAt: date(2026, 8, 20, hour: 1)
        )
        let priorSunday = session(title: "Prior Week", startedAt: date(2026, 8, 16, hour: 23))

        let content = HomeContent(
            sessions: [priorSunday, wednesdayCrossMidnight, mondayEvening, mondayMorning],
            ownerTokenIdentifier: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content.weeklyActivity.completedWorkoutCount, 3)
        XCTAssertEqual(content.weeklyActivity.days.count, 7)
        XCTAssertEqual(content.weeklyActivity.days.filter(\.hasCompletedWorkout).count, 2)
        XCTAssertTrue(try XCTUnwrap(content.weeklyActivity.days.first).hasCompletedWorkout)
        XCTAssertTrue(try XCTUnwrap(content.weeklyActivity.days.first(where: \.isToday)).hasCompletedWorkout)
    }

    func testWeeklyActivityAccessibilitySummaryNamesCompletedDaysOnce() {
        let content = HomeContent(
            sessions: [
                session(title: "Monday One", startedAt: date(2026, 8, 17, hour: 8)),
                session(title: "Monday Two", startedAt: date(2026, 8, 17, hour: 20)),
                session(title: "Wednesday", startedAt: date(2026, 8, 19, hour: 8)),
            ],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        let summary = content.weeklyActivity.accessibilityDescription(
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(summary, "3 workouts completed this week: Monday and Wednesday.")
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func session(
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        updatedAt: Date? = nil,
        status: WorkoutSessionStatus = .completed,
        deletedAt: Date? = nil,
        ownerTokenIdentifier: String? = nil,
        workoutNotes: String = "",
        exerciseName: String? = nil,
        exerciseNotes: String = ""
    ) -> WorkoutSession {
        let loggedExercises = exerciseName.map { name in
            [
                LoggedExercise(
                    orderIndex: 0,
                    exerciseSnapshotName: name,
                    notes: exerciseNotes,
                    sets: [LoggedSet(orderIndex: 0, isCompleted: true)]
                ),
            ]
        } ?? []
        return WorkoutSession(
            title: title,
            startedAt: startedAt,
            endedAt: endedAt ?? startedAt.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            notes: workoutNotes,
            status: status,
            source: .blank,
            updatedAt: updatedAt ?? startedAt,
            deletedAt: deletedAt,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            loggedExercises: loggedExercises
        )
    }
}
