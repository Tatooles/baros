import SwiftData
import XCTest
@testable import Baros

@MainActor
final class LocalDataResetServiceTests: XCTestCase {
    func testResetClearsUserDataSyncMetadataAndReseedsLocalDefaults() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5)
        let loggedExercise = LoggedExercise(orderIndex: 0, sets: [set])
        let session = WorkoutSession(
            title: "Delete Me",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "issuer|owner_a",
            loggedExercises: [loggedExercise]
        )
        let customExercise = Exercise(
            name: "Custom Row",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .upperBack,
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )
        let settings = UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a")
        let outbox = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: customExercise.id,
            operation: .update,
            ownerTokenIdentifier: "issuer|owner_a"
        )
        let cursor = SyncCursorState(ownerTokenIdentifier: "issuer|owner_a")

        context.insert(session)
        context.insert(customExercise)
        context.insert(settings)
        context.insert(outbox)
        context.insert(cursor)
        try context.save()

        try LocalDataResetService().reset(context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LoggedExercise>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LoggedSet>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncCursorState>()).count, 0)

        let settingsRecords = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(settingsRecords.count, 1)
        XCTAssertNil(settingsRecords.first?.syncOwnerTokenIdentifier)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.count, SeedDataService.exerciseSeeds.count)
        XCTAssertTrue(exercises.allSatisfy(\.isSeeded))
        XCTAssertTrue(exercises.allSatisfy { $0.syncOwnerTokenIdentifier == nil })
    }
}
