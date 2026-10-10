import SwiftData
import XCTest
@testable import Baros

@MainActor
final class LocalDataResetServiceTests: XCTestCase {
    func testFailedResetRestoresGraphAndPreservesUnrelatedPendingEdits() throws {
        try verifyFailedResetRecovery(withExistingUndoManager: false)
    }

    func testFailedResetPreservesExistingUndoManagerAndPendingDeletion() throws {
        try verifyFailedResetRecovery(withExistingUndoManager: true)
    }

    private func verifyFailedResetRecovery(withExistingUndoManager: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reset.store")
        let schema = Schema(BarosSchema.models)
        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
            let context = container.mainContext
            context.autosaveEnabled = false
            let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5)
            let exercise = Exercise(name: "Saved Lift", category: .strength,
                                    equipment: .barbell, primaryMuscleGroup: .chest)
            let occurrence = LoggedExercise(orderIndex: 0, exercise: exercise, sets: [set])
            context.insert(Exercise(name: "Already Removed", category: .strength,
                                    equipment: .barbell, primaryMuscleGroup: .chest))
            context.insert(WorkoutSession(title: "Keep Me", startedAt: .now, status: .completed,
                                          source: .blank, loggedExercises: [occurrence]))
            try SeedDataService.seedIfNeeded(context: context)
        }
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url, allowsSave: false))
        let context = container.mainContext
        context.autosaveEnabled = false
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let originalUndoManager = withExistingUndoManager ? UndoManager() : nil
        context.undoManager = originalUndoManager
        session.notes = "Unrelated unsaved correction"
        let unsavedExercise = Exercise(name: "Pending Custom Lift", category: .strength,
                                       equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(unsavedExercise)
        let pendingDeletion = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Already Removed" })
        context.delete(pendingDeletion)
        let originalExerciseCount = try context.fetch(FetchDescriptor<Exercise>()).count
        let originalExercise = try XCTUnwrap(session.loggedExercises.first?.exercise)

        // A repeated failure must not accumulate replacement defaults either.
        XCTAssertThrowsError(try LocalDataResetService().reset(context: context))
        XCTAssertThrowsError(try LocalDataResetService().reset(context: context))

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.map(\.id), [session.id])
        XCTAssertEqual(session.notes, "Unrelated unsaved correction")
        XCTAssertEqual(session.sortedLoggedExercises.count, 1)
        XCTAssertEqual(session.sortedLoggedExercises.first?.sortedSets.first?.weight, 185)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).contains { $0.id == unsavedExercise.id })
        XCTAssertTrue(context.insertedModelsArray.contains { $0.persistentModelID == unsavedExercise.persistentModelID })
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, originalExerciseCount)
        XCTAssertEqual(session.loggedExercises.first?.exercise?.id, originalExercise.id)
        XCTAssertEqual(context.deletedModelsArray.map(\.persistentModelID), [pendingDeletion.persistentModelID])
        XCTAssertTrue(context.hasChanges)
        XCTAssertTrue(context.undoManager === originalUndoManager)
        if withExistingUndoManager {
            XCTAssertTrue(try XCTUnwrap(originalUndoManager).canUndo)
        }
    }

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

        session.notes = "Pending edit that a successful reset should discard"
        context.insert(Exercise(name: "Pending insertion", category: .strength,
                                equipment: .barbell, primaryMuscleGroup: .chest))

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
        XCTAssertFalse(context.hasChanges)
        try context.save()
        let freshContext = ModelContext(container)
        XCTAssertTrue(try freshContext.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        XCTAssertEqual(try freshContext.fetch(FetchDescriptor<Exercise>()).count, SeedDataService.exerciseSeeds.count)
    }
}
