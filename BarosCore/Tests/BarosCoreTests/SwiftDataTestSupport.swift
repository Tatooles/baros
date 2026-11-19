import XCTest
import Foundation
import SwiftData
@testable import BarosCore

@MainActor
enum SwiftDataTestSupport {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(BarosSchema.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeDiskBackedContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(BarosSchema.models)
        let configuration = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

/// A fixed time after any record a test creates at the real current time.
/// The edit clock never stamps an edit below the version it replaces, so a
/// test that edits at a fixed time must use one later than its fixtures.
func afterFixtureCreation(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 4_000_000_000 + offset)
}

/// An edit stamped at `expected`, or a few `SyncEditClock` steps above it when
/// the same record was stamped more than once at that instant.
func assertStamped(_ stamp: Date, at expected: Date, file: StaticString = #filePath, line: UInt = #line) {
    let offset = stamp.timeIntervalSince(expected)
    XCTAssertTrue(
        offset >= 0 && offset < SyncEditClock.step * 10,
        "Expected \(stamp) to be stamped at \(expected)",
        file: file,
        line: line
    )
}
