import Foundation
import SwiftData
import XCTest
@testable import Baros

@MainActor
final class HomeRingModelTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Chicago")!
        result.firstWeekday = 2
        result.minimumDaysInFirstWeek = 4
        return result
    }

    private func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int = 9, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func workout(_ date: Date, minutes: Double) -> RingWorkout {
        RingWorkout(date: date, duration: minutes * 60)
    }

    func testSessionAdaptationUsesSavedDurationWithoutEndDate() {
        let session = WorkoutSession(title: "Workout", startedAt: date(hour: 7), durationSeconds: 3_600,
                                     status: .completed, source: .blank)
        XCTAssertEqual(RingWorkout.ringWorkouts(from: [session], now: date()),
                       [RingWorkout(date: session.startedAt, duration: 3_600, id: session.id, title: "Workout")])
    }

    func testSessionAdaptationFallsBackToElapsedDuration() {
        let start = date(hour: 7)
        let session = WorkoutSession(title: "Workout", startedAt: start, endedAt: start.addingTimeInterval(45 * 60),
                                     durationSeconds: 0, status: .completed, source: .blank)
        XCTAssertEqual(RingWorkout.ringWorkouts(from: [session], now: date()),
                       [RingWorkout(date: start, duration: 2_700, id: session.id, title: "Workout")])
    }

    func testSessionAdaptationExcludesFutureEndDate() {
        let session = WorkoutSession(title: "Workout", startedAt: date(hour: 7), endedAt: date(hour: 13),
                                     durationSeconds: 3_600, status: .completed, source: .blank)
        XCTAssertTrue(RingWorkout.ringWorkouts(from: [session], now: date()).isEmpty)
    }

    func testDayBucketingCombinesDoubleWorkoutBeforeCapping() {
        let now = date()
        let model = HomeRingModel(workouts: [workout(date(hour: 7), minutes: 55), workout(date(hour: 10), minutes: 50)], now: now, calendar: calendar)
        XCTAssertEqual(model.totalWorkouts, 2)
        XCTAssertEqual(model.monthWorkoutCount, 2)
        XCTAssertEqual(model.monthSpokes, [HomeRingSpoke(angleIndex: 0, normalizedLength: 1, lap: 0)])
    }

    func testDoubleShortWorkoutsAreSummedBeforeApplyingFloor() {
        let model = HomeRingModel(workouts: [workout(date(hour: 7), minutes: 15), workout(date(hour: 10), minutes: 15)], now: date(), calendar: calendar)
        XCTAssertEqual(model.monthSpokes[0].normalizedLength, 10 / 70, accuracy: 0.0001)
    }

    func testDurationFloorAndCapUseFixedScale() {
        XCTAssertEqual(HomeRingModel.cappedDailyMinutes(5 * 60), 20)
        XCTAssertEqual(HomeRingModel.cappedDailyMinutes(180 * 60), 90)
        XCTAssertEqual(HomeRingModel.cappedDailyMinutes(55 * 60), 55)
        let model = HomeRingModel(workouts: [workout(date(2026, 10, 7), minutes: 5), workout(date(2026, 10, 8), minutes: 180), workout(date(hour: 7), minutes: 55)], now: date(), calendar: calendar)
        XCTAssertEqual(model.monthSpokes.map(\.normalizedLength), [0, 1, 0.5])
    }

    private func monthLength(minutes: Double, diameter: Double = 350) -> Double {
        let model = HomeRingModel(workouts: [workout(date(), minutes: minutes)], now: date(), calendar: calendar)
        return model.monthSpokes[0].monthLengthFraction * diameter
    }

    func testMonthLengthClampsToClearlyVisibleMinimumAndLayoutMaximum() {
        XCTAssertEqual(monthLength(minutes: -10), 8.4, accuracy: 0.001)
        XCTAssertEqual(monthLength(minutes: 5), 8.4, accuracy: 0.001)
        XCTAssertEqual(monthLength(minutes: 20), 8.4, accuracy: 0.001)
        XCTAssertEqual(monthLength(minutes: 90), 56, accuracy: 0.001)
        XCTAssertEqual(monthLength(minutes: 180), 56, accuracy: 0.001)
        XCTAssertGreaterThan(monthLength(minutes: 5), 7.5) // Rest ticks are thinner and neutral gray.
        for diameter in [280.0, 320, 350] {
            let outerEdge = diameter * 0.308 + 6 + monthLength(minutes: 180, diameter: diameter) + 5.5 / 2
            XCTAssertLessThanOrEqual(outerEdge, diameter / 2)
        }
    }

    func testMonthLengthIsStrictlyMonotonicAcrossUnclampedDurations() {
        let lengths = stride(from: 20.0, through: 90, by: 5).map { monthLength(minutes: $0) }
        for (shorter, longer) in zip(lengths, lengths.dropFirst()) {
            XCTAssertLessThan(shorter, longer)
        }
    }

    func test80MinuteMonthSpokeIsNoticeablyLongerThan40Minutes() {
        let forty = monthLength(minutes: 40)
        let eighty = monthLength(minutes: 80)
        XCTAssertEqual(forty, 22, accuracy: 0.001)
        XCTAssertEqual(eighty, 49.2, accuracy: 0.001)
        XCTAssertGreaterThan(eighty / forty, 2)
        XCTAssertGreaterThan(eighty - forty, 25)
    }

    func testRestTicksFillOnlyUntrainedCurrentSlots() {
        let now = date()
        let previousYear = calendar.date(byAdding: .weekOfYear, value: -53, to: now)!
        let model = HomeRingModel(workouts: [workout(now, minutes: 5), workout(previousYear, minutes: 60)],
                                  now: now, calendar: calendar)
        XCTAssertEqual(model.emptySlotIndices(for: .month), Array((1..<30).reversed()))
        XCTAssertEqual(model.emptySlotIndices(for: .year), Array((1..<52).reversed()))
        XCTAssertTrue(model.yearSpokes.contains { $0.angleIndex == 1 && $0.lap == 1 })
        // A tree-ring workout never suppresses a current-year rest tick.
        XCTAssertTrue(model.emptySlotIndices(for: .year).contains(1))
    }

    func testEmptyRingHasAll30DailyOr52WeeklyTicks() {
        let model = HomeRingModel(workouts: [], now: date(), calendar: calendar)
        XCTAssertEqual(model.emptySlotIndices(for: .month), Array((0..<30).reversed()))
        XCTAssertEqual(model.emptySlotIndices(for: .year), Array((0..<52).reversed()))
    }

    func testMonthOnlyIncludesTodayThrough29DaysBack() {
        let now = date()
        let workouts = [0, 29, 30].map { workout(calendar.date(byAdding: .day, value: -$0, to: now)!, minutes: 60) }
        let model = HomeRingModel(workouts: workouts, now: now, calendar: calendar)
        XCTAssertEqual(model.monthSpokes.map(\.angleIndex), [29, 0])
        XCTAssertEqual(model.totalWorkouts, 3)
        XCTAssertEqual(model.monthWorkoutCount, 2)
    }

    func testPeriodToggleIsHiddenForEmptyAndRecentHistory() {
        let now = date()
        XCTAssertFalse(HomeRingModel(workouts: [], now: now, calendar: calendar).showsPeriodToggle)
        let recent = [0, 14, 29].map {
            workout(calendar.date(byAdding: .day, value: -$0, to: now)!, minutes: 60)
        }
        XCTAssertFalse(HomeRingModel(workouts: recent, now: now, calendar: calendar).showsPeriodToggle)
    }

    func testPeriodToggleUsesTheSameCalendarDayBoundaryAsMonth() {
        let now = date()
        let earliestMonthDay = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
        let included = workout(earliestMonthDay, minutes: 60)
        let inside = HomeRingModel(workouts: [included], now: now, calendar: calendar)
        XCTAssertEqual(inside.monthWorkoutCount, 1)
        XCTAssertFalse(inside.showsPeriodToggle)

        let justOutside = workout(earliestMonthDay.addingTimeInterval(-1), minutes: 60)
        let outside = HomeRingModel(workouts: [included, justOutside], now: now, calendar: calendar)
        XCTAssertEqual(outside.monthWorkoutCount, 1)
        XCTAssertTrue(outside.showsPeriodToggle)
    }

    func testFutureWorkoutsDoNotExposePeriodToggle() {
        let future = workout(calendar.date(byAdding: .day, value: 1, to: date())!, minutes: 60)
        XCTAssertFalse(HomeRingModel(workouts: [future], now: date(), calendar: calendar).showsPeriodToggle)
    }

    func testWeeksUseCappedDailyTotalsDividedByFour90MinuteDays() {
        let model = HomeRingModel(workouts: [workout(date(2026, 10, 5), minutes: 180), workout(date(2026, 10, 6), minutes: 90), workout(date(2026, 10, 4), minutes: 60)], now: date(), calendar: calendar)
        XCTAssertEqual(model.yearSpokes.count, 2)
        XCTAssertEqual(model.yearSpokes[0].angleIndex, 1)
        XCTAssertEqual(model.yearSpokes[1].normalizedLength, 0.5)
        XCTAssertEqual(model.yearSpokes[1].angleIndex, 0)
    }

    func testWeeklyLengthCapsAtOne() {
        let workouts = (5...9).map { workout(date(2026, 10, $0, hour: 7), minutes: 90) }
        let model = HomeRingModel(workouts: workouts, now: date(), calendar: calendar)
        XCTAssertEqual(model.yearSpokes[0].normalizedLength, 1)
    }

    func testLapBoundariesAndThreeInnerLapLimit() {
        let now = date()
        let ages = [51, 52, 103, 104, 155, 156, 207, 208]
        let workouts = ages.map { workout(calendar.date(byAdding: .weekOfYear, value: -$0, to: now)!, minutes: 60) }
        let model = HomeRingModel(workouts: workouts, now: now, calendar: calendar)
        XCTAssertEqual(model.yearSpokes.map(\.lap), [3, 3, 2, 2, 1, 1, 0])
        XCTAssertEqual(model.yearSpokes.map(\.angleIndex), [51, 0, 51, 0, 51, 0, 51])
        XCTAssertEqual(model.totalWorkouts, 8) // Lifetime count includes older history.
        XCTAssertEqual(model.yearWorkoutCount, 1)
    }

    func testEmptyStateHasNoSpokes() {
        let model = HomeRingModel(workouts: [], now: date(), calendar: calendar)
        XCTAssertEqual(model.totalWorkouts, 0)
        XCTAssertTrue(model.monthSpokes.isEmpty)
        XCTAssertTrue(model.yearSpokes.isEmpty)
        XCTAssertEqual(model.accessibilitySummary(period: .month), "No workouts yet.")
    }

    func testInjectedTimeZoneDeterminesLocalDay() {
        let now = date(hour: 1)
        let beforeMidnight = date(2026, 10, 8, hour: 23).addingTimeInterval(59 * 60)
        let afterMidnight = date(hour: 0).addingTimeInterval(60)
        let workouts = [workout(beforeMidnight, minutes: 50), workout(afterMidnight, minutes: 50)]
        let local = HomeRingModel(workouts: workouts, now: now, calendar: calendar)
        XCTAssertEqual(local.monthSpokes.map(\.angleIndex), [1, 0])
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let universal = HomeRingModel(workouts: workouts, now: now, calendar: utc)
        XCTAssertEqual(universal.monthSpokes.count, 1)
        XCTAssertEqual(universal.monthSpokes[0].normalizedLength, 1)
    }

    func testDayAndWeekOffsetsSurviveDaylightSavingTime() {
        let now = date(2026, 3, 9)
        let model = HomeRingModel(workouts: [workout(date(2026, 3, 8), minutes: 60)], now: now, calendar: calendar)
        XCTAssertEqual(model.monthSpokes[0].angleIndex, 1)
        XCTAssertEqual(model.yearSpokes[0].angleIndex, 1)
    }

    func testFutureWorkoutsDoNotCount() {
        let model = HomeRingModel(workouts: [workout(date(2026, 10, 10), minutes: 60)], now: date(), calendar: calendar)
        XCTAssertEqual(model.totalWorkouts, 0)
        XCTAssertTrue(model.yearSpokes.isEmpty)
    }

    func testCenterCountAndCaptionFollowTheSelectedPeriod() {
        let workouts = [
            workout(date(2024, 8, 20), minutes: 60), // Inner lap: lifetime only.
            workout(date(2026, 6, 1), minutes: 60), // Past year, outside 30 days.
            workout(date(), minutes: 60),
        ]
        let model = HomeRingModel(workouts: workouts, now: date(), calendar: calendar)
        XCTAssertEqual(model.workoutCount(for: .month), 1)
        XCTAssertEqual(model.countCaption(for: .month), "workout in the past 30 days")
        XCTAssertEqual(model.workoutCount(for: .year), 2)
        XCTAssertEqual(model.countCaption(for: .year), "workouts in the past year")
    }

    func testCenterCountIsZeroWhenThePeriodHasNoWorkouts() {
        let model = HomeRingModel(workouts: [workout(date(2026, 6, 1), minutes: 60)], now: date(), calendar: calendar)
        XCTAssertEqual(model.workoutCount(for: .month), 0)
        XCTAssertEqual(model.countCaption(for: .month), "workouts in the past 30 days")
    }

    func testWeekBucketingRespectsLocaleFirstWeekdayAcrossNewYear() {
        let now = date(2026, 1, 5)
        let sunday = workout(date(2026, 1, 4), minutes: 60)
        let december = workout(date(2025, 12, 31), minutes: 60)
        let mondayBased = HomeRingModel(workouts: [sunday, december], now: now, calendar: calendar)
        XCTAssertEqual(mondayBased.yearSpokes.map(\.angleIndex), [1])
        var sundayCalendar = calendar
        sundayCalendar.firstWeekday = 1
        sundayCalendar.minimumDaysInFirstWeek = 1
        let sundayBased = HomeRingModel(workouts: [sunday, december], now: now, calendar: sundayCalendar)
        XCTAssertEqual(sundayBased.yearSpokes.map(\.angleIndex), [1, 0])
        XCTAssertEqual(sundayBased.monthSpokes.map(\.angleIndex), [5, 1])
    }

    func testWeeklyOffsetsAcrossSpringAndFallDSTForBothWeekStarts() {
        for now in [date(2026, 3, 9), date(2026, 11, 2)] {
            for firstWeekday in [1, 2] {
                var c = calendar
                c.firstWeekday = firstWeekday
                let weekStart = c.dateInterval(of: .weekOfYear, for: now)!.start
                let dates = [0, 1, 51, 52, 103, 104, 155].map {
                    workout(c.date(byAdding: .weekOfYear, value: -$0, to: weekStart)!, minutes: 60)
                }
                let model = HomeRingModel(workouts: dates, now: now, calendar: c)
                XCTAssertEqual(model.yearSpokes.map(\.lap), [2, 2, 1, 1, 0, 0, 0])
                XCTAssertEqual(model.yearSpokes.map(\.angleIndex), [51, 0, 51, 0, 51, 1, 0])
            }
        }
    }

    func testAccessibilitySummariesMatchTheCenterCount() {
        let workouts = [workout(date(2025, 8, 20), minutes: 60), workout(date(), minutes: 60)]
        let model = HomeRingModel(workouts: workouts, now: date(), calendar: calendar)
        XCTAssertEqual(model.accessibilitySummary(period: .month), "1 workout in the past 30 days.")
        XCTAssertEqual(model.accessibilitySummary(period: .year), "1 workout in the past year. Trained in 1 week.")
    }

    func testThreeYear500WorkoutBucketingPerformance() {
        let now = date()
        let workouts = (0..<500).map { index in
            workout(calendar.date(byAdding: .day, value: -(index * 1095 / 499), to: now)!, minutes: 60)
        }
        measure {
            let model = HomeRingModel(workouts: workouts, now: now, calendar: calendar)
            XCTAssertEqual(model.totalWorkouts, 500)
            XCTAssertEqual(Set(model.yearSpokes.map(\.lap)), [0, 1, 2, 3])
            XCTAssertEqual(model.monthWorkoutCount, 14)
        }
    }

    // MARK: Scrubbing

    private func named(_ date: Date, _ title: String, minutes: Double = 60, id: UUID = UUID()) -> RingWorkout {
        RingWorkout(date: date, duration: minutes * 60, id: id, title: title)
    }

    private func preview(_ workouts: [RingWorkout], _ period: HomeRingPeriod, _ index: Int,
                         exercises: [UUID: Int] = [:]) -> HomeRingSlotPreview {
        HomeRingSlotPreview(model: HomeRingModel(workouts: workouts, now: date(), calendar: calendar),
                            period: period, index: index, calendar: calendar, exerciseCount: { exercises[$0] })
    }

    func testScrubSlotsHoldWorkoutsOldestFirstAndOnlyTheOuterYearLap() {
        let morning = named(date(hour: 7), "Lift")
        let later = named(date(hour: 10), "Run")
        let lastYear = named(calendar.date(byAdding: .weekOfYear, value: -53, to: date())!, "Old")
        let model = HomeRingModel(workouts: [later, lastYear, morning], now: date(), calendar: calendar)
        XCTAssertEqual(model.workouts(for: .month, at: 0), [morning, later])
        XCTAssertEqual(model.workouts(for: .year, at: 0), [morning, later])
        // Tree-ring workouts share an angle with the outer lap but are not scrubbable.
        XCTAssertTrue(model.yearSpokes.contains { $0.angleIndex == 1 && $0.lap == 1 })
        XCTAssertTrue(model.workouts(for: .year, at: 1).isEmpty)
        XCTAssertEqual(model.slotStart(for: .month, at: 3, calendar: calendar), date(2026, 10, 6, hour: 0))
        XCTAssertEqual(model.slotStart(for: .year, at: 2, calendar: calendar), date(2026, 9, 21, hour: 0))
    }

    func testMonthPreviewForOneWorkoutShowsNameDurationAndExerciseCount() {
        let id = UUID()
        let result = preview([named(date(hour: 7), "Push Day", minutes: 65, id: id)], .month, 0, exercises: [id: 5])
        XCTAssertEqual(result.dateText, "Today")
        XCTAssertEqual(result.title, "Push Day")
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.detail, "1 hr 5 min · 5 exercises")
        XCTAssertEqual(result.workoutIDs, [id])
        XCTAssertEqual(result.accessibilityValue, "Today. Push Day. 1 hr 5 min · 5 exercises")
        // Value-only fixtures have no store identity, so they preview without exercises and never open.
        let fixture = preview([RingWorkout(date: date(hour: 7), duration: 45 * 60)], .month, 0)
        XCTAssertEqual(fixture.detail, "45 min")
        XCTAssertTrue(fixture.workoutIDs.isEmpty)
    }

    func testMonthPreviewListsEveryWorkoutOnADoubleDayWithoutTotals() {
        let first = named(date(2026, 10, 8, hour: 7), "Lift")
        let second = named(date(2026, 10, 8, hour: 17), "Run")
        let result = HomeRingSlotPreview(
            model: HomeRingModel(workouts: [second, first], now: date(), calendar: calendar),
            period: .month, index: 1, calendar: calendar,
            exerciseCount: { _ in XCTFail("A list never loads logged exercises"); return nil }
        )
        XCTAssertEqual(result.dateText, "Yesterday")
        XCTAssertNil(result.title)
        XCTAssertEqual(result.rows, [.init(label: nil, title: "Lift"), .init(label: nil, title: "Run")])
        XCTAssertNil(result.detail)
        XCTAssertEqual(result.workoutIDs, [first.id!, second.id!])
    }

    func testRestSlotPreviewsStateOnlyTheDateAndNothingOpens() {
        let month = preview([named(date(hour: 7), "Lift")], .month, 3)
        XCTAssertTrue(month.dateText.contains("Oct 6"), month.dateText)
        XCTAssertEqual(month.detail, "No workout")
        XCTAssertTrue(month.workoutIDs.isEmpty)
        let year = preview([named(date(hour: 7), "Lift")], .year, 5)
        XCTAssertEqual(year.detail, "No workouts")
        XCTAssertTrue(year.workoutIDs.isEmpty)
        XCTAssertEqual(preview([], .year, 0).dateText, "This week")
    }

    func testYearPreviewListsWeekdayAndNameAndSummarizesOverflow() {
        let titles = ["Push Day", "Lower Body Strength", "Pull Day", "Zone 2", "Upper", "Full Body", "Long Run"]
        let week = titles.enumerated().map { offset, title in
            named(calendar.date(byAdding: .day, value: offset, to: date(2026, 9, 28, hour: 7))!, title)
        }
        let full = preview(week, .year, 1)
        XCTAssertTrue(full.dateText.contains("Sep 28"), full.dateText)
        XCTAssertEqual(full.rows.map(\.label), ["Mon", "Tue", "Wed", "Thu"])
        XCTAssertEqual(full.rows.map(\.title), Array(titles.prefix(4)))
        XCTAssertEqual(full.hiddenCount, 3)
        XCTAssertNil(full.detail)
        XCTAssertEqual(full.workoutIDs.count, 7)
        XCTAssertTrue(full.accessibilityValue.hasSuffix("Mon Push Day. Tue Lower Body Strength. Wed Pull Day. Thu Zone 2. 3 more"))

        let five = preview(Array(week.prefix(5)), .year, 1)
        XCTAssertEqual(five.rows.count, HomeRingSlotPreview.maximumRows)
        XCTAssertEqual(five.hiddenCount, 0)
    }

    func testScrubAngleMapsToSlotsCounterclockwiseFromTwelve() {
        func slot(_ x: CGFloat, _ y: CGFloat, _ count: Int) -> Int {
            HomeRingScrubGeometry.slotIndex(at: CGPoint(x: x, y: y), center: CGPoint(x: 100, y: 100), slotCount: count)
        }
        // A Month quarter turn is 7.5 slots, so probe just past 9 and 3 o'clock instead of on a boundary.
        XCTAssertEqual([slot(100, 0, 30), slot(0, 110, 30), slot(100, 200, 30), slot(200, 90, 30)], [0, 8, 15, 23])
        XCTAssertEqual([slot(100, 0, 52), slot(0, 100, 52), slot(100, 200, 52), slot(200, 100, 52)], [0, 13, 26, 39])
        // Left of 12 o'clock is yesterday; right of it wraps to the oldest slot.
        XCTAssertEqual(slot(70, 0, 30), 1)
        XCTAssertEqual(slot(130, 0, 30), 29)
    }

    func testPreviewDurationText() {
        XCTAssertEqual(HomeRingSlotPreview.durationText(45 * 60), "45 min")
        XCTAssertEqual(HomeRingSlotPreview.durationText(3_600), "1 hr")
        XCTAssertEqual(HomeRingSlotPreview.durationText(3_660), "1 hr 1 min")
        XCTAssertEqual(HomeRingSlotPreview.durationText(-5), "0 min")
    }

    #if DEBUG
    func testScrubHistorySeedsStressCasesAtStraightDragSlots() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try UITestFixtureSeeder.seedHomeRingScrubHistory(ownerTokenIdentifier: nil, context: context,
                                                         now: date(), calendar: calendar)
        let firstCount = try context.fetchCount(FetchDescriptor<WorkoutSession>())
        try UITestFixtureSeeder.seedHomeRingScrubHistory(ownerTokenIdentifier: nil, context: context,
                                                         now: date(), calendar: calendar)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, firstCount)
        let model = HomeRingModel(workouts: RingWorkout.ringWorkouts(from: sessions, now: date()),
                                  now: date(), calendar: calendar)
        XCTAssertEqual([8, 15, 22].map { model.workouts(for: .month, at: $0).count }, [1, 2, 3])
        XCTAssertEqual([13, 26, 39].map { model.workouts(for: .year, at: $0).count }, [7, 5, 6])
        XCTAssertTrue(model.showsPeriodToggle)
    }

    func testSaved500WorkoutHistoryIsIdempotentAndUsesLiveOwnerFiltering() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try UITestFixtureSeeder.seedHomeRingHistory(ownerTokenIdentifier: "owner-a", context: context,
                                                   now: date(), calendar: calendar)
        try UITestFixtureSeeder.seedHomeRingHistory(ownerTokenIdentifier: "owner-a", context: context,
                                                   now: date(), calendar: calendar)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 500)
        let visible = HomeContent(sessions: sessions, ownerTokenIdentifier: "owner-a", now: date())
        let model = HomeRingModel(workouts: visible.completedSessions.map {
            RingWorkout(date: $0.startedAt, duration: $0.endedAt!.timeIntervalSince($0.startedAt))
        }, now: date(), calendar: calendar)
        XCTAssertEqual(model.totalWorkouts, 500)
        XCTAssertEqual(model.monthWorkoutCount, 14)
        XCTAssertTrue(model.showsPeriodToggle)
        XCTAssertEqual(Set(model.yearSpokes.map(\.lap)), [0, 1, 2, 3])
        XCTAssertTrue(HomeContent(sessions: sessions, ownerTokenIdentifier: "owner-b", now: date()).completedSessions.isEmpty)
    }

    private var personas: [HomeRingFixture] { [.perWeek2, .perWeek3, .perWeek4, .perWeek5] }

    func testFixturePeriodToggleVisibility() {
        for fixture in [HomeRingFixture.empty, .twoWeeks] {
            let model = HomeRingModel(workouts: fixture.workouts(now: date(), calendar: calendar), now: date(), calendar: calendar)
            XCTAssertFalse(model.showsPeriodToggle, fixture.rawValue)
        }
        for fixture in [HomeRingFixture.sixMonths, .multiYear] + personas {
            let model = HomeRingModel(workouts: fixture.workouts(now: date(), calendar: calendar), now: date(), calendar: calendar)
            XCTAssertTrue(model.showsPeriodToggle, fixture.rawValue)
        }
    }

    func testPersonaFixturesAreDeterministicWithinTheSameDay() {
        for fixture in personas {
            let first = fixture.workouts(now: date(), calendar: calendar)
            XCTAssertEqual(first, fixture.workouts(now: date(), calendar: calendar), fixture.rawValue)
            XCTAssertEqual(first, fixture.workouts(now: date(hour: 23), calendar: calendar), fixture.rawValue)
            XCTAssertNotEqual(first, (fixture == .perWeek5 ? HomeRingFixture.perWeek2 : .perWeek5).workouts(now: date(), calendar: calendar))
        }
    }

    func testPersonaAverageFrequencyAndDateBoundsAcrossSeasons() {
        // Include a leap year, holiday months, DST, and midnight launches.
        let dates = [date(2024, 2, 29, hour: 0), date(2025, 1, 1, hour: 0),
                     date(2026, 3, 9, hour: 0), date(2026, 7, 1, hour: 0),
                     date(2026, 10, 11, hour: 0), date(2026, 12, 31, hour: 0)]
        for now in dates {
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .month, value: -14, to: today)!
            let weeks = Double(calendar.dateComponents([.day], from: start, to: today).day! + 1) / 7
            for fixture in personas {
                let workouts = fixture.workouts(now: now, calendar: calendar)
                let ratio = Double(workouts.count) / weeks / Double(fixture.weeklyTarget!)
                XCTAssertGreaterThanOrEqual(ratio, 0.85, "\(fixture.rawValue) at \(now): \(ratio)")
                XCTAssertLessThanOrEqual(ratio, 0.95, "\(fixture.rawValue) at \(now): \(ratio)")
                XCTAssertTrue(workouts.allSatisfy { $0.date >= start && $0.date <= now })
                XCTAssertEqual(workouts, workouts.sorted { $0.date < $1.date })
                XCTAssertLessThan(calendar.dateComponents([.day], from: start, to: workouts.first!.date).day!, 7)
            }
        }
    }

    func testPersonasHaveMissedWeeksPartialInnerRingAndCappedDoubleDays() {
        let now = date(2026, 10, 11)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        for fixture in personas {
            let workouts = fixture.workouts(now: now, calendar: calendar)
            let model = HomeRingModel(workouts: workouts, now: now, calendar: calendar)
            let outer = model.yearSpokes.filter { $0.lap == 0 }
            XCTAssertEqual(outer.count, 49, fixture.rawValue) // 52 weeks minus three fully missed.
            XCTAssertTrue(outer.allSatisfy { ![15, 16, 37].contains($0.angleIndex) })
            let inner = model.yearSpokes.filter { $0.lap == 1 }
            XCTAssertTrue((7...10).contains(inner.count))
            XCTAssertTrue(model.yearSpokes.allSatisfy { $0.lap <= 1 })
            let daily = Dictionary(grouping: workouts, by: { calendar.startOfDay(for: $0.date) })
            let doubles = daily.values.filter { $0.count > 1 }
            XCTAssertEqual(doubles.count, 2, fixture.rawValue)
            XCTAssertTrue(doubles.contains { $0.reduce(0) { $0 + $1.duration } > 90 * 60 })
            XCTAssertTrue(workouts.allSatisfy { (20 * 60...85 * 60).contains($0.duration) })
            XCTAssertTrue(workouts.contains { $0.duration <= 30 * 60 })
            let december = workouts.filter { calendar.component(.month, from: $0.date) == 12 }
            XCTAssertLessThan(Double(december.count) / (31 / 7.0), Double(fixture.weeklyTarget!))
            let weeklyCounts = Dictionary(grouping: workouts) {
                calendar.dateInterval(of: .weekOfYear, for: $0.date)!.start
            }.filter { $0.key < thisWeek }
            XCTAssertTrue(weeklyCounts.values.contains { $0.count == fixture.weeklyTarget! - 1 })
            XCTAssertTrue(weeklyCounts.values.contains { $0.count == fixture.weeklyTarget! + 1 })
        }
    }
    #endif
}
