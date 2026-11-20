import Foundation
import Synchronization

public enum WorkoutFormatters {
    public static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainder))"
        }

        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", remainder))"
    }

    public static func setDuration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let remainder = String(format: "%02d", seconds % 60)
        guard seconds >= 3_600 else { return "\(seconds / 60):\(remainder)" }
        return "\(seconds / 3_600):\(String(format: "%02d", seconds % 3_600 / 60)):\(remainder)"
    }

    public static func setDurationAccessibilityDescription(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let parts = [
            (seconds / 3_600, "hour"), (seconds % 3_600 / 60, "minute"), (seconds % 60, "second")
        ].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: ", ")
    }

    public static func elapsedDescription(_ seconds: Int) -> String {
        elapsedCompactDescription(seconds) + " elapsed"
    }

    public static func elapsedCompactDescription(_ seconds: Int) -> String {
        duration(max(0, seconds))
    }

    public static func elapsedAccessibilityDescription(_ seconds: Int) -> String {
        let elapsedSeconds = max(0, seconds)
        let hours = elapsedSeconds / 3_600
        let minutes = (elapsedSeconds % 3_600) / 60
        let seconds = elapsedSeconds % 60
        var parts: [String] = []

        if hours > 0 {
            parts.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        if minutes > 0 {
            parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        parts.append("\(seconds) \(seconds == 1 ? "second" : "seconds")")

        return parts.joined(separator: ", ") + " elapsed"
    }

    static func homeElapsedDescription(_ seconds: Int) -> String {
        let elapsedMinutes = max(0, seconds) / 60
        let hours = elapsedMinutes / 60
        let minutes = elapsedMinutes % 60
        guard hours > 0 else {
            return "\(minutes) min elapsed"
        }

        return "\(hours) hr \(String(format: "%02d", minutes)) min elapsed"
    }

    public static func exerciseCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "exercise" : "exercises")"
    }

    public static func setCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "set" : "sets")"
    }

    public static func exerciseHeaderTitle(_ name: String) -> String {
        name
            .replacingOccurrences(of: " - ", with: "\u{00A0}– ")
            .replacingOccurrences(of: " – ", with: "\u{00A0}– ")
            .replacingOccurrences(of: " — ", with: "\u{00A0}— ")
    }

    public static func date(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    public static func compactDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

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

    public static func number(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        let isWholeNumber = value.rounded() == value

        let formatter = isWholeNumber ? wholeNumberFormatter : fractionalNumberFormatter
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static let groupedNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    public static func groupedNumber(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        return groupedNumberFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func historyDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : compactDate(date)
    }

    public static func volume(canonicalPounds: Double, unit: MeasurementUnit) -> String {
        number(unit.displayWeight(fromCanonicalPounds: canonicalPounds) ?? canonicalPounds)
    }

    private static let inputNumberFormatter = Mutex<NumberFormatter?>(nil)

    static func parseNumber(_ value: String, locale: Locale = .current) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let number = inputNumberFormatter.withLock { cachedFormatter -> Double? in
            let formatter: NumberFormatter
            if let cachedFormatter {
                formatter = cachedFormatter
            } else {
                formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                cachedFormatter = formatter
            }
            if formatter.locale != locale {
                formatter.locale = locale
            }
            return formatter.number(from: trimmed)?.doubleValue
        }
        let parsedNumber = number ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))

        guard let parsedNumber, parsedNumber.isFinite else { return nil }
        return parsedNumber
    }
}
