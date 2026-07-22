import Foundation

enum WorkoutNumericInputPolicy {
    /// 10,000 canonical pounds is intentionally well above plausible workout
    /// equipment while still rejecting values that are clearly accidental.
    static let maximumWeightPounds = 10_000.0

    /// 1,000 reps accommodates unusual endurance sets while rejecting accidental
    /// extra digits. A recorded set must contain at least one repetition.
    static let repsRange = 1...1_000

    /// RPE uses the standard 1-to-10 exertion scale. The quick-pick UI emphasizes
    /// 6 through 10, but manual entry supports the full scale.
    static let rpeRange = 1.0...10.0

    static func validatedWeight(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...maximumWeightPounds).contains(value) else {
            return nil
        }
        return value
    }

    static func parseWeight(
        _ text: String,
        unit: MeasurementUnit,
        locale: Locale = .current
    ) -> Double? {
        let displayWeight = WorkoutFormatters.parseNumber(text, locale: locale)
        return validatedWeight(unit.canonicalWeight(fromDisplayWeight: displayWeight))
    }

    static func validatedReps(_ value: Int?) -> Int? {
        guard let value, repsRange.contains(value) else { return nil }
        return value
    }

    static func parseReps(_ text: String) -> Int? {
        validatedReps(Int(text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    static func validatedRPE(_ value: Double?) -> Double? {
        guard let value, value.isFinite, rpeRange.contains(value) else { return nil }
        return value
    }

    static func parseRPE(_ text: String, locale: Locale = .current) -> Double? {
        validatedRPE(WorkoutFormatters.parseNumber(text, locale: locale))
    }
}
