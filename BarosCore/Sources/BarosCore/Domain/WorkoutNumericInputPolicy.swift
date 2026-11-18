import Foundation

public enum WorkoutNumericInputPolicy {
    /// 10,000 canonical pounds is intentionally well above plausible workout
    /// equipment while still rejecting values that are clearly accidental.
    static let maximumWeightPounds = 10_000.0

    /// 1,000 reps accommodates unusual endurance sets while rejecting accidental
    /// extra digits. A recorded set must contain at least one repetition.
    static let repsRange = 1...1_000

    /// A timed set lasts at least a second. The cap is the longest time the
    /// picker's wheels can show, 23:59:59.
    static let durationSecondsRange = 1...86_399

    /// RPE uses the standard 1-to-10 exertion scale. The quick-pick UI emphasizes
    /// 6 through 10, but manual entry supports the full scale.
    static let rpeRange = 1.0...10.0

    public static func validatedWeight(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...maximumWeightPounds).contains(value) else {
            return nil
        }
        return value
    }

    public static func parseWeight(
        _ text: String,
        unit: MeasurementUnit,
        locale: Locale = .current
    ) -> Double? {
        let displayWeight = WorkoutFormatters.parseNumber(text, locale: locale)
        return validatedWeight(unit.canonicalWeight(fromDisplayWeight: displayWeight))
    }

    public static func validatedReps(_ value: Int?) -> Int? {
        guard let value, repsRange.contains(value) else { return nil }
        return value
    }

    public static func parseReps(_ text: String, locale: Locale = .current) -> Int? {
        guard let parsed = WorkoutFormatters.parseNumber(text, locale: locale),
              parsed.rounded() == parsed,
              (Double(repsRange.lowerBound)...Double(repsRange.upperBound)).contains(parsed)
        else {
            return nil
        }

        return Int(parsed)
    }

    public static func validatedRPE(_ value: Double?) -> Double? {
        guard let value, value.isFinite, rpeRange.contains(value) else { return nil }
        return value
    }

    public static func parseRPE(_ text: String, locale: Locale = .current) -> Double? {
        validatedRPE(WorkoutFormatters.parseNumber(text, locale: locale))
    }

    public static func validatedDuration(_ seconds: Int?) -> Int? {
        guard let seconds, durationSecondsRange.contains(seconds) else { return nil }
        return seconds
    }
}
