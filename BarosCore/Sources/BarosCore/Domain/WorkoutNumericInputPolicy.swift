import Foundation

public enum WorkoutNumericInputPolicy {
    static let maximumWeightPounds = 10_000.0

    static let repsRange = 1...1_000

    public static let durationSecondsRange = 1...3_599

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
