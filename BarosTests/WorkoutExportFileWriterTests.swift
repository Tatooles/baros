import XCTest
@testable import Baros

final class WorkoutExportFileWriterTests: XCTestCase {
    func testWriteCreatesDatedCSVFileWithUTF8Contents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let writer = WorkoutExportFileWriter(directory: directory)
        let url = try writer.write(csv: "header\nvalue\n", now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(url.lastPathComponent, "baros-workout-history-1970-01-01.csv")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "header\nvalue\n")
    }
}
