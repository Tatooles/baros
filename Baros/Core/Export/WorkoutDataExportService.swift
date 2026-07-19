import Foundation

struct WorkoutDataExportService {
    private let dateFormatter: ISO8601DateFormatter

    init(dateFormatter: ISO8601DateFormatter = WorkoutDataExportService.makeDateFormatter()) {
        self.dateFormatter = dateFormatter
    }

    static func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    func csv(
        for sessions: [WorkoutSession],
        unit: MeasurementUnit,
        ownerTokenIdentifier: String? = nil
    ) -> String {
        var rows: [[String]] = [Self.header]

        for session in sortedCompletedSessions(from: sessions, ownerTokenIdentifier: ownerTokenIdentifier) {
            for loggedExercise in sortedLoggedExercises(from: session) {
                for set in sortedSets(from: loggedExercise) {
                    rows.append(row(for: set, loggedExercise: loggedExercise, session: session, unit: unit))
                }
            }
        }

        return rows
            .map { $0.map(Self.escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    private static let header = [
        "workout_date",
        "workout_title",
        "workout_notes",
        "exercise_order",
        "exercise_name",
        "exercise_notes",
        "set_order",
        "set_kind",
        "is_completed",
        "weight",
        "reps",
        "unit",
        "rpe",
        "set_notes",
        "completed_at",
        "workout_id",
        "logged_exercise_id",
        "set_id"
    ]

    private func sortedCompletedSessions(
        from sessions: [WorkoutSession],
        ownerTokenIdentifier: String?
    ) -> [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(from: sessions, ownerTokenIdentifier: ownerTokenIdentifier)
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt {
                    return lhs.startedAt < rhs.startedAt
                }

                if lhs.title != rhs.title {
                    return lhs.title < rhs.title
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func sortedLoggedExercises(from session: WorkoutSession) -> [LoggedExercise] {
        session.loggedExercises
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func sortedSets(from loggedExercise: LoggedExercise) -> [LoggedSet] {
        loggedExercise.sets
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func row(
        for set: LoggedSet,
        loggedExercise: LoggedExercise,
        session: WorkoutSession,
        unit: MeasurementUnit
    ) -> [String] {
        [
            formatDate(session.startedAt),
            Self.neutralizedText(session.title),
            Self.neutralizedText(session.notes),
            String(loggedExercise.orderIndex + 1),
            Self.neutralizedText(loggedExercise.exerciseSnapshotName),
            Self.neutralizedText(loggedExercise.notes),
            String(set.orderIndex + 1),
            set.kind.rawValue,
            String(set.isCompleted),
            unit.displayWeight(fromCanonicalPounds: set.weight).map(Self.formatDouble) ?? "",
            set.reps.map(String.init) ?? "",
            unit.rawValue,
            set.rpe.map(Self.formatDouble) ?? "",
            Self.neutralizedText(set.notes),
            set.completedAt.map(formatDate) ?? "",
            session.id.uuidString,
            loggedExercise.id.uuidString,
            set.id.uuidString
        ]
    }

    private func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func formatDouble(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        var formatted = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)

        while formatted.last == "0" {
            formatted.removeLast()
        }

        if formatted.last == "." {
            formatted.removeLast()
        }

        return formatted == "-0" ? "0" : formatted
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }

        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func neutralizedText(_ value: String) -> String {
        let formulaCharacterIndex = value.firstIndex { character in
            !character.unicodeScalars.allSatisfy { CharacterSet.controlCharacters.contains($0) }
        }

        guard let formulaCharacterIndex,
              Self.formulaPrefixCharacters.contains(value[formulaCharacterIndex])
        else {
            return value
        }

        return "'\(value)"
    }

    private static let formulaPrefixCharacters: Set<Character> = ["=", "+", "-", "@", "＝", "＋", "－", "＠"]
}
