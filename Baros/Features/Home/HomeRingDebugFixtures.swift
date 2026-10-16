// DEBUG-only synthetic history is made from values and is never inserted into SwiftData.
#if DEBUG
import Foundation

enum HomeRingFixture: String, CaseIterable {
    case live, empty, twoWeeks, sixMonths, multiYear, perWeek2, perWeek3, perWeek4, perWeek5

    static var launchFixture: Self {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--home-ring-fixture"), index + 1 < args.count else { return .live }
        return Self(rawValue: args[index + 1]) ?? .live
    }

    func workouts(now: Date, calendar: Calendar) -> [RingWorkout] {
        if let target = weeklyTarget {
            return personaWorkouts(target: target, now: now, calendar: calendar)
        }
        let days: Int
        switch self {
        case .live, .empty: return []
        case .twoWeeks: days = 14
        case .sixMonths: days = 183
        case .multiYear: days = 913
        case .perWeek2, .perWeek3, .perWeek4, .perWeek5: return []
        }
        let durations = [52, 46, 72, 59]
        var result: [RingWorkout] = []
        for age in (0..<days).reversed() {
            let week = age / 7
            // Deterministic 3–4 days / week, with two vacation gaps and occasional doubles.
            guard [0, 2, 4].contains(age % 7) || (age % 7 == 6 && week % 3 == 1) else { continue }
            guard !(week % 26 == 11 || week % 26 == 12) else { continue }
            let type = result.count % durations.count
            guard let day = calendar.date(byAdding: .day, value: -age, to: calendar.startOfDay(for: now)),
                  let date = calendar.date(bySettingHour: age == 0 ? 0 : 17, minute: 0, second: 0, of: day) else { continue }
            let minutes = age == 42 ? 180 : durations[type] + ((age * 7) % 15) - 5
            result.append(RingWorkout(date: date, duration: Double(minutes * 60)))
            if age > 14 && age % 37 == 0 {
                result.append(RingWorkout(date: date.addingTimeInterval(3_600), duration: 40 * 60))
            }
        }
        return result
    }

    var weeklyTarget: Int? {
        switch self {
        case .perWeek2: 2
        case .perWeek3: 3
        case .perWeek4: 4
        case .perWeek5: 5
        default: nil
        }
    }

    private func personaWorkouts(target: Int, now: Date, calendar: Calendar) -> [RingWorkout] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .month, value: -14, to: today) else { return [] }
        // Monday-based preferences are independent of the user's firstWeekday setting.
        let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
        guard let thisMonday = calendar.date(byAdding: .day, value: -mondayOffset, to: today),
              let startMonday = calendar.date(byAdding: .day,
                value: -((calendar.component(.weekday, from: start) + 5) % 7), to: start) else { return [] }
        let weeks = (calendar.dateComponents([.day], from: startMonday, to: thisMonday).day ?? 0) / 7
        let preferred: [Int]
        switch target {
        case 2: preferred = [1, 4] // Tuesday / Friday
        case 3: preferred = [0, 2, 4] // Monday / Wednesday / Friday
        case 4: preferred = [0, 1, 3, 5]
        default: preferred = [0, 1, 2, 4, 5]
        }
        var rng = HomeRingFixtureRandom(seed: 0xBA205 + UInt64(target))
        var result: [RingWorkout] = []
        for weeksBack in (0...weeks).reversed() {
            // Three completely missed weeks per rolling year, including a two-week vacation.
            guard ![15, 16, 37].contains(weeksBack % 52),
                  let monday = calendar.date(byAdding: .day, value: -weeksBack * 7, to: thisMonday) else { continue }
            var days = preferred
            let variation = rng.unit()
            if variation < 0.14 {
                days.remove(at: rng.index(days.count))
            } else if variation < 0.22 {
                let spare = (0..<7).filter { !days.contains($0) }
                days.append(spare[rng.index(spare.count)])
            }
            var occupied: Set<Int> = []
            var addedDouble = false
            var holidaySkips = 0
            for preferredDay in days {
                let shift = rng.unit() < 0.25 ? (rng.unit() < 0.5 ? -1 : 1) : 0
                var dayOffset = min(6, max(0, preferredDay + shift))
                if occupied.contains(dayOffset) {
                    dayOffset = (0..<7).filter { !occupied.contains($0) }
                        .min { abs($0 - preferredDay) < abs($1 - preferredDay) }!
                }
                occupied.insert(dayOffset)
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: monday) else { continue }
                // December is a quieter holiday stretch, not a perfectly maintained schedule.
                let holidayCandidate = calendar.component(.month, from: day) == 12 && rng.unit() < 0.25
                // Keep the holiday stretch distinct from the fully missed vacation/illness weeks.
                let skipsHolidaySession = holidayCandidate && holidaySkips < days.count - 1
                if skipsHolidaySession { holidaySkips += 1 }
                let minutes = rng.durationMinutes()
                guard day >= start, day <= today, !skipsHolidaySession,
                      let date = calendar.date(bySettingHour: day == today ? 0 : 17,
                                               minute: 0, second: 0, of: day), date <= now else { continue }
                result.append(RingWorkout(date: date, duration: minutes * 60))
                // Roughly two double days over fourteen months; sum before daily capping.
                if weeksBack % 29 == 7, !addedDouble, day < today {
                    result.append(RingWorkout(date: date.addingTimeInterval(3_600), duration: 50 * 60))
                    addedDouble = true
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }

}

/// Fixed SplitMix64 seed: never use Swift's randomly seeded Hasher for fixtures.
private struct HomeRingFixtureRandom {
    var seed: UInt64

    mutating func unit() -> Double {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }

    mutating func index(_ count: Int) -> Int { Int(unit() * Double(count)) }

    mutating func durationMinutes() -> Double {
        if unit() < 0.07 { return (20 + unit() * 10).rounded() }
        // Triangular distribution centered on 60 minutes, bounded to 35–85.
        return (35 + (unit() + unit()) * 25).rounded()
    }
}

#endif
