import Foundation

struct WorkoutExportFileWriter {
    private let directory: URL
    private let calendar: Calendar

    init(
        directory: URL = FileManager.default.temporaryDirectory,
        calendar: Calendar = WorkoutExportFileWriter.makeCalendar()
    ) {
        self.directory = directory
        self.calendar = calendar
    }

    func write(csv: String, now: Date = .now) throws -> URL {
        let url = directory.appendingPathComponent(filename(for: now), isDirectory: false)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func filename(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "baros-workout-history-%04d-%02d-%02d.csv", year, month, day)
    }

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
