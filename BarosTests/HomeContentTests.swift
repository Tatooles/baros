import Foundation
import SwiftData
import XCTest
@testable import Baros

@MainActor
final class HomeContentTests: XCTestCase {
    // Unsaved models duplicate to-many relationships, so fixtures live in an in-memory store.
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try SwiftDataTestSupport.makeInMemoryContainer()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

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

    func testPastWorkoutReviewUsesCompletionDateForCrossMidnightWorkout() {
        let completedWorkout = session(
            title: "Late Workout",
            startedAt: date(2026, 8, 18, hour: 23),
            endedAt: date(2026, 8, 19, hour: 1)
        )

        let presentation = HomePastWorkoutReviewPresentation(session: completedWorkout)

        XCTAssertEqual(presentation.completedAt, date(2026, 8, 19, hour: 1))
    }

    func testPastWorkoutReviewFallsBackToStartDateWithoutCompletionDate() {
        let startedAt = date(2026, 8, 19, hour: 10)
        let completedWorkout = WorkoutSession(
            title: "Workout Without End Date",
            startedAt: startedAt,
            status: .completed,
            source: .blank
        )

        let presentation = HomePastWorkoutReviewPresentation(session: completedWorkout)

        XCTAssertEqual(presentation.completedAt, startedAt)
    }

    func testPastWorkoutReviewCountsEverySetThatWillBeCopied() {
        let completedWorkout = WorkoutSession(
            title: "Push Day",
            startedAt: date(2026, 8, 19),
            status: .completed,
            source: .blank,
            loggedExercises: [
                LoggedExercise(
                    orderIndex: 0,
                    exerciseSnapshotName: "Bench Press",
                    sets: [
                        LoggedSet(orderIndex: 0, isCompleted: true),
                        LoggedSet(orderIndex: 1, isCompleted: false),
                    ]
                ),
            ]
        )

        let presentation = HomePastWorkoutReviewPresentation(session: completedWorkout)
        let copiedSets = completedWorkout.sortedLoggedExercises.flatMap(\.sortedSets)

        XCTAssertGreaterThan(copiedSets.count, copiedSets.filter(\.isCompleted).count)
        XCTAssertEqual(presentation.copiedSetCount, copiedSets.count)
    }

    func testPastWorkoutReviewPresentsCopiedExercisesInSourceOrder() {
        let cableFly = LoggedExercise(
            orderIndex: 1,
            exerciseSnapshotName: "Cable Fly",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.cable.rawValue
        )
        cableFly.sets = [LoggedSet(orderIndex: 0)]
        let benchPress = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue
        )
        benchPress.sets = [
            LoggedSet(orderIndex: 0),
            LoggedSet(orderIndex: 1),
        ]
        let completedWorkout = WorkoutSession(
            title: "Push Day",
            startedAt: date(2026, 8, 19),
            status: .completed,
            source: .blank
        )
        completedWorkout.loggedExercises = [cableFly, benchPress]

        let presentation = HomePastWorkoutReviewPresentation(session: completedWorkout)

        XCTAssertEqual(
            presentation.exercises,
            [
                .init(
                    id: completedWorkout.sortedLoggedExercises[0].id,
                    name: "Bench Press",
                    equipment: "Barbell",
                    copiedSetCount: 2
                ),
                .init(
                    id: completedWorkout.sortedLoggedExercises[1].id,
                    name: "Cable Fly",
                    equipment: "Cable",
                    copiedSetCount: 1
                ),
            ]
        )
        XCTAssertEqual(presentation.structureSummary, "2 exercises · 3 sets")
        XCTAssertEqual(presentation.exercises.map(\.copiedSetDescription), ["2 sets", "1 set"])
    }

    func testPastWorkoutReviewUsesSingularStructureCopy() {
        let exercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Deadlift",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue
        )
        exercise.sets = [LoggedSet(orderIndex: 0)]
        let completedWorkout = WorkoutSession(
            title: "Pull Day",
            startedAt: date(2026, 8, 19),
            status: .completed,
            source: .blank
        )
        completedWorkout.loggedExercises = [exercise]

        let presentation = HomePastWorkoutReviewPresentation(session: completedWorkout)

        XCTAssertEqual(presentation.structureSummary, "1 exercise · 1 set")
        XCTAssertEqual(presentation.exercises[0].copiedSetDescription, "1 set")
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
        XCTAssertEqual(content.trainingCalendar.weeks.last?.completedWorkoutCount, 2)
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

    func testTrainingCalendarWithoutHistoryShowsOnlyTheCurrentWeekWithoutPastMarkers() {
        let content = HomeContent(
            sessions: [],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        let trainingCalendar = content.trainingCalendar
        XCTAssertFalse(trainingCalendar.hasCompletedWorkouts)
        XCTAssertEqual(trainingCalendar.weeks.count, 1)
        let week = trainingCalendar.weeks[0]
        XCTAssertTrue(week.isCurrent)
        XCTAssertEqual(week.start, date(2026, 8, 17))
        XCTAssertEqual(week.completedWorkoutCount, 0)
        XCTAssertEqual(
            week.days.map(\.state),
            [.beforeFirstWorkout, .beforeFirstWorkout, .noWorkout, .upcoming, .upcoming, .upcoming, .upcoming]
        )
        XCTAssertEqual(week.days.map(\.isToday), [false, false, true, false, false, false, false])
    }

    func testTrainingCalendarStartsAtTheWeekOfTheFirstWorkout() {
        let firstWorkout = session(title: "First", startedAt: date(2026, 8, 5, hour: 18))
        let content = HomeContent(
            sessions: [firstWorkout],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        let weeks = content.trainingCalendar.weeks
        XCTAssertTrue(content.trainingCalendar.hasCompletedWorkouts)
        XCTAssertEqual(weeks.map(\.start), [date(2026, 8, 3), date(2026, 8, 10), date(2026, 8, 17)])
        XCTAssertEqual(weeks.map(\.isCurrent), [false, false, true])
        XCTAssertEqual(weeks.map(\.completedWorkoutCount), [1, 0, 0])
        XCTAssertEqual(
            weeks[0].days.map(\.state),
            [.beforeFirstWorkout, .beforeFirstWorkout, .completed, .noWorkout, .noWorkout, .noWorkout, .noWorkout]
        )
        XCTAssertEqual(weeks[1].days.map(\.state), Array(repeating: .noWorkout, count: 7))
    }

    func testTrainingCalendarKeepsAtMostTwelveWeeksOfHistory() {
        let longAgo = session(title: "Long Ago", startedAt: date(2026, 3, 2, hour: 18))
        let content = HomeContent(
            sessions: [longAgo],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        let weeks = content.trainingCalendar.weeks
        XCTAssertEqual(weeks.count, HomeTrainingCalendar.maximumWeekCount)
        XCTAssertEqual(weeks.last?.start, date(2026, 8, 17))
        XCTAssertEqual(weeks.first?.start, date(2026, 6, 1))
        XCTAssertFalse(weeks.flatMap(\.days).contains { $0.state == .beforeFirstWorkout })
    }

    func testTrainingCalendarUsesStartDateWithBinaryDayMarkersAndCountsEveryCompletion() throws {
        let mondayMorning = session(title: "Monday One", startedAt: date(2026, 8, 17, hour: 8))
        let mondayEvening = session(title: "Monday Two", startedAt: date(2026, 8, 17, hour: 20))
        let wednesdayCrossMidnight = session(
            title: "Wednesday",
            startedAt: date(2026, 8, 19, hour: 23),
            endedAt: date(2026, 8, 20, hour: 1)
        )
        let priorSunday = session(title: "Prior Week", startedAt: date(2026, 8, 16, hour: 23))
        let active = session(title: "Active", startedAt: date(2026, 8, 18, hour: 9), status: .active)

        let content = HomeContent(
            sessions: [active, priorSunday, wednesdayCrossMidnight, mondayEvening, mondayMorning],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        let weeks = content.trainingCalendar.weeks
        XCTAssertEqual(weeks.map(\.completedWorkoutCount), [1, 3])
        let currentWeek = try XCTUnwrap(weeks.last)
        XCTAssertEqual(
            currentWeek.days.map(\.state),
            [.completed, .noWorkout, .completed, .upcoming, .upcoming, .upcoming, .upcoming]
        )
        XCTAssertEqual(weeks[0].days.last?.state, .completed)
    }

    func testTrainingCalendarVisibleWeeksFillCapacityWithinMinimumAndHistory() {
        let longHistory = HomeContent(
            sessions: [session(title: "Long Ago", startedAt: date(2026, 3, 2, hour: 18))],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        ).trainingCalendar
        XCTAssertEqual(longHistory.visibleWeeks(fitting: 0).count, HomeTrainingCalendar.minimumVisibleWeekCount)
        XCTAssertEqual(longHistory.visibleWeeks(fitting: 7).count, 7)
        XCTAssertEqual(longHistory.visibleWeeks(fitting: 30).count, 12)
        XCTAssertEqual(longHistory.visibleWeeks(fitting: 7).last?.isCurrent, true)

        let shortHistory = HomeContent(
            sessions: [session(title: "Last Week", startedAt: date(2026, 8, 12, hour: 18))],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        ).trainingCalendar
        XCTAssertEqual(shortHistory.visibleWeeks(fitting: 0).count, 2)
        XCTAssertEqual(shortHistory.visibleWeeks(fitting: 10).count, 2)
    }

    func testTrainingCalendarAccessibilitySummaryCoversVisibleWeeks() {
        let content = HomeContent(
            sessions: [
                session(title: "Earlier", startedAt: date(2026, 8, 4, hour: 8)),
                session(title: "Monday One", startedAt: date(2026, 8, 17, hour: 8)),
                session(title: "Monday Two", startedAt: date(2026, 8, 17, hour: 20)),
                session(title: "Wednesday", startedAt: date(2026, 8, 19, hour: 8)),
            ],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )
        let trainingCalendar = content.trainingCalendar

        XCTAssertEqual(
            trainingCalendar.accessibilityDescription(for: trainingCalendar.visibleWeeks(fitting: 0)),
            "3 workouts this week. 4 workouts in the last 3 weeks."
        )

        let emptyCalendar = HomeContent(
            sessions: [],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19),
            calendar: calendar
        ).trainingCalendar
        XCTAssertEqual(
            emptyCalendar.accessibilityDescription(for: emptyCalendar.visibleWeeks(fitting: 0)),
            "0 workouts this week."
        )
    }

    func testQuickStartGroupsCustomTitlesCaseAndWhitespaceInsensitivelyNewestFirst() {
        let newestPush = session(title: "push  day ", startedAt: date(2026, 8, 19, hour: 8), exerciseNames: ["Bench Press"])
        let pull = session(title: "Pull Day", startedAt: date(2026, 8, 18, hour: 8), exerciseNames: ["Deadlift"])
        let olderPush = session(title: "Push Day", startedAt: date(2026, 8, 17, hour: 8), exerciseNames: ["Overhead Press"])

        let content = HomeContent(
            sessions: [olderPush, pull, newestPush],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(content.quickStartWorkouts.map(\.id), [newestPush.id, pull.id])
    }

    func testQuickStartGroupsDefaultTitledWorkoutsByTheirOrderedExercises() {
        let benchNewest = session(title: "Workout", startedAt: date(2026, 8, 19, hour: 8), exerciseNames: ["Bench Press", "Row"])
        let squat = session(title: "Workout", startedAt: date(2026, 8, 18, hour: 8), exerciseNames: ["Back Squat"])
        let benchOlder = session(title: " workout", startedAt: date(2026, 8, 17, hour: 8), exerciseNames: ["bench press", "row"])
        let reordered = session(title: "Workout", startedAt: date(2026, 8, 16, hour: 8), exerciseNames: ["Row", "Bench Press"])

        let content = HomeContent(
            sessions: [reordered, benchOlder, squat, benchNewest],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(content.quickStartWorkouts.map(\.id), [benchNewest.id, squat.id, reordered.id])
    }

    func testQuickStartKeepsDefaultTitledWorkoutsWithDifferentEquipmentApart() {
        let barbellRow = session(title: "Workout", startedAt: date(2026, 8, 19, hour: 8), exerciseNames: ["Row"])
        barbellRow.sortedLoggedExercises.first?.exerciseSnapshotEquipmentRaw = ExerciseEquipment.barbell.rawValue
        let cableRow = session(title: "Workout", startedAt: date(2026, 8, 18, hour: 8), exerciseNames: ["Row"])
        cableRow.sortedLoggedExercises.first?.exerciseSnapshotEquipmentRaw = ExerciseEquipment.cable.rawValue

        let content = HomeContent(
            sessions: [cableRow, barbellRow],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(content.quickStartWorkouts.map(\.id), [barbellRow.id, cableRow.id])
    }

    func testQuickStartRecencyUsesCompletionTimeForCrossMidnightWorkouts() {
        let lateNight = session(
            title: "Late Night",
            startedAt: date(2026, 8, 18, hour: 23),
            endedAt: date(2026, 8, 19, hour: 1),
            exerciseNames: ["A"]
        )

        let content = HomeContent(
            sessions: [lateNight],
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(content.quickStartWorkouts.first?.lastCompletedDescription, "Today")
        XCTAssertEqual(content.trainingCalendar.weeks.last?.days[1].state, .completed)
    }

    func testQuickStartSkipsWorkoutsWithoutExercisesAndCapsTheRow() {
        let empty = session(title: "Empty", startedAt: date(2026, 8, 19, hour: 9))
        let distinct = (0..<7).map { index in
            session(
                title: "Workout \(index)",
                startedAt: date(2026, 8, 19, hour: 8).addingTimeInterval(TimeInterval(-index * 3_600)),
                exerciseNames: ["Exercise \(index)"]
            )
        }

        let content = HomeContent(
            sessions: [empty] + distinct,
            ownerTokenIdentifier: nil,
            now: date(2026, 8, 19, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(content.quickStartWorkouts.count, HomeQuickStartWorkout.maximumCount)
        XCTAssertEqual(content.quickStartWorkouts.map(\.id), distinct.prefix(5).map(\.id))
    }

    func testQuickStartDescribesRecencyAndPreviewsTheFirstThreeExercises() throws {
        let now = date(2026, 8, 19, hour: 12)
        let workouts = [
            session(title: "Today", startedAt: date(2026, 8, 19, hour: 7), exerciseNames: ["A", "B", "C", "D"]),
            session(title: "Yesterday", startedAt: date(2026, 8, 18, hour: 20), exerciseNames: ["A"]),
            session(title: "Days", startedAt: date(2026, 8, 6, hour: 7), exerciseNames: ["A"]),
            session(title: "Weeks", startedAt: date(2026, 8, 5, hour: 7), exerciseNames: ["A"]),
        ]

        let content = HomeContent(sessions: workouts, ownerTokenIdentifier: nil, now: now, calendar: calendar)

        XCTAssertEqual(
            content.quickStartWorkouts.map(\.lastCompletedDescription),
            ["Today", "Yesterday", "13 days ago", "2 weeks ago"]
        )
        XCTAssertEqual(try XCTUnwrap(content.quickStartWorkouts.first).previewExerciseNames, ["A", "B", "C"])
    }

    func testQuickStartSwitchesFromWeeksToMonthsAtTwoMonthsAndToYearsAtTwelve() {
        let now = date(2026, 8, 19, hour: 12)
        let workouts = [
            session(title: "Eight Weeks", startedAt: date(2026, 6, 20, hour: 7), exerciseNames: ["A"]),
            session(title: "Two Months", startedAt: date(2026, 6, 19, hour: 7), exerciseNames: ["A"]),
            session(title: "Eleven Months", startedAt: date(2025, 9, 19, hour: 7), exerciseNames: ["A"]),
            session(title: "One Year", startedAt: date(2025, 8, 19, hour: 7), exerciseNames: ["A"]),
            session(title: "Two Years", startedAt: date(2024, 2, 1, hour: 7), exerciseNames: ["A"]),
        ]

        let content = HomeContent(sessions: workouts, ownerTokenIdentifier: nil, now: now, calendar: calendar)

        XCTAssertEqual(
            content.quickStartWorkouts.map(\.lastCompletedDescription),
            ["8 weeks ago", "2 months ago", "11 months ago", "1 year ago", "2 years ago"]
        )
    }

    func testCalendarCapacityUsesSpaceLeftAfterHeaderActionsAndCardChrome() {
        var metrics = HomeLayoutMetrics()
        XCTAssertEqual(metrics.calendarWeekCapacity(rowSpacing: 4, fixedSpacing: 40), 0)

        metrics.viewportHeight = 700
        metrics.headerHeight = 80
        metrics.actionsHeight = 220
        metrics.calendarCardHeight = 190
        metrics.calendarRowsHeight = 124
        metrics.calendarRowCount = 4

        // 700 - 40 fixed - 80 header - 220 actions - 66 card chrome leaves 294pt.
        // Rows are 28pt with 4pt spacing: 9 rows take 284pt and 10 would take 316pt.
        XCTAssertEqual(metrics.calendarWeekCapacity(rowSpacing: 4, fixedSpacing: 40), 9)
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
        exerciseNotes: String = "",
        exerciseNames: [String] = []
    ) -> WorkoutSession {
        let names = (exerciseName.map { [$0] } ?? []) + exerciseNames
        let loggedExercises = names.enumerated().map { index, name in
            LoggedExercise(
                orderIndex: index,
                exerciseSnapshotName: name,
                notes: exerciseNotes,
                sets: [LoggedSet(orderIndex: 0, isCompleted: true)]
            )
        }
        let session = WorkoutSession(
            title: title,
            startedAt: startedAt,
            endedAt: endedAt ?? startedAt.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            notes: workoutNotes,
            status: status,
            source: .blank,
            updatedAt: updatedAt ?? startedAt,
            deletedAt: deletedAt,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        container.mainContext.insert(session)
        session.loggedExercises = loggedExercises
        return session
    }
}
