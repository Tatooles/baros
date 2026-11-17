import SwiftData
import XCTest
@testable import BarosCore

@MainActor
final class SyncCursorStateTests: XCTestCase {
    func testCursorStateLookupCreatesMissingOwnerState() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        let state = try SyncCursorState.state(for: "issuer|owner_a", context: context)
        try context.save()

        XCTAssertEqual(state.ownerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(state.userSettingsCursor, 0)
        XCTAssertEqual(state.exercisesCursor, 0)
        XCTAssertEqual(state.workoutSessionsCursor, 0)
        XCTAssertEqual(state.loggedExercisesCursor, 0)
        XCTAssertEqual(state.loggedSetsCursor, 0)
        XCTAssertFalse(state.hasBootstrappedSettingsExercises)
        XCTAssertFalse(state.hasBootstrappedWorkoutGraph)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncCursorState>()).count, 1)
    }

    func testCursorStateLookupReturnsExistingOwnerState() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let existing = SyncCursorState(
            ownerTokenIdentifier: "issuer|owner_a",
            userSettingsCursor: 12,
            exercisesCursor: 34
        )
        context.insert(existing)
        try context.save()

        let state = try SyncCursorState.state(for: "issuer|owner_a", context: context)
        try context.save()

        XCTAssertEqual(state.id, existing.id)
        XCTAssertEqual(state.userSettingsCursor, 12)
        XCTAssertEqual(state.exercisesCursor, 34)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncCursorState>()).count, 1)
    }

    func testCursorStateLookupReturnsUnsavedInsertedOwnerState() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        let first = try SyncCursorState.state(for: "issuer|owner_a", context: context)
        let second = try SyncCursorState.state(for: "issuer|owner_a", context: context)
        try context.save()

        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncCursorState>()).count, 1)
    }
}
