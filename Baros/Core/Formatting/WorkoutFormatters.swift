import Foundation

enum WorkoutFormatters {
    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainder))"
        }

        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", remainder))"
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func compactDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    // NumberFormatter allocation is expensive and number(_:) runs for every set
    // row on every workout-form render, so both variants are cached. Main-thread
    // use only: NumberFormatter is not thread-safe.
    private static let wholeNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let fractionalNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        let isWholeNumber = value.rounded() == value

        let formatter = isWholeNumber ? wholeNumberFormatter : fractionalNumberFormatter
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func volume(canonicalPounds: Double, unit: MeasurementUnit) -> String {
        number(unit.displayWeight(fromCanonicalPounds: canonicalPounds) ?? canonicalPounds)
    }

    static func parseNumber(_ value: String, locale: Locale = .current) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal

        let parsedNumber: Double?
        if let number = formatter.number(from: trimmed) {
            parsedNumber = number.doubleValue
        } else {
            parsedNumber = Double(trimmed.replacingOccurrences(of: ",", with: "."))
        }

        guard let parsedNumber, parsedNumber.isFinite else { return nil }
        return parsedNumber
    }
}
