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

    func testEmptyStateHasNoSpokesOrFirstDate() {
        let model = HomeRingModel(workouts: [], now: date(), calendar: calendar)
        XCTAssertEqual(model.totalWorkouts, 0)
        XCTAssertNil(model.firstWorkoutDate)
        XCTAssertTrue(model.monthSpokes.isEmpty)
        XCTAssertTrue(model.yearSpokes.isEmpty)
        XCTAssertEqual(model.accessibilitySummary(period: .month, now: date(), calendar: calendar), "No workouts yet.")
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

    func testSingularCaptionAndEarliestDateAcrossAllLaps() {
        let first = date(2025, 8, 20)
        let model = HomeRingModel(workouts: [workout(first, minutes: 60)], now: date(), calendar: calendar)
        XCTAssertEqual(model.firstWorkoutDate, first)
        XCTAssertTrue(model.sinceDescription(now: date(), calendar: calendar, abbreviated: true).hasPrefix("workout since "))
        XCTAssertTrue(model.sinceDescription(now: date(), calendar: calendar, abbreviated: true).contains("2025"))
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

    func testAccessibilitySummariesDescribeTheWindowAndLifetimeHistory() {
        let workouts = [workout(date(2025, 8, 20), minutes: 60), workout(date(), minutes: 60)]
        let model = HomeRingModel(workouts: workouts, now: date(), calendar: calendar)
        XCTAssertTrue(model.accessibilitySummary(period: .month, now: date(), calendar: calendar)
            .hasPrefix("Last 30 days: 1 workout. 2 workouts since"))
        XCTAssertTrue(model.accessibilitySummary(period: .year, now: date(), calendar: calendar)
            .hasPrefix("Last 52 weeks: trained in 1 week. 2 workouts since"))
        let recent = HomeRingModel(workouts: [workout(date(), minutes: 60)], now: date(), calendar: calendar)
        XCTAssertTrue(recent.sinceDescription(now: date(), calendar: calendar, abbreviated: true).contains("2026"))
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

    #if DEBUG
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
