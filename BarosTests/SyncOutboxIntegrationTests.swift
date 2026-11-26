import SwiftData
import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class SyncOutboxIntegrationTests: XCTestCase {
    func testFinishingWorkoutRecordsCompletedGraphCreateIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(exercise)
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let loggedExercise = try engine.addExercises([exercise], to: session, context: context)[0]
        let firstSet = try XCTUnwrap(loggedExercise.sets.first)
        try engine.commitActiveSetDraft(
            firstSet,
            values: .init(weight: 185, reps: 5),
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try RPEChipSelectionAction.apply(value: 8, to: firstSet, engine: engine, context: context)
        XCTAssertTrue(firstSet.isCompleted)
        XCTAssertNotNil(firstSet.completedAt)
        let secondSet = try engine.addSet(to: loggedExercise, context: context)

        try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 400))

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 4)
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .create)
        assertEntry(entries, kind: .loggedExercise, id: loggedExercise.id, operation: .create)
        assertEntry(entries, kind: .loggedSet, id: firstSet.id, operation: .create)
        assertEntry(entries, kind: .loggedSet, id: secondSet.id, operation: .create)

        let setPayload = SyncPayloadMapper.loggedSetPayload(from: firstSet)
        XCTAssertEqual(setPayload.weight, 185)
        XCTAssertEqual(setPayload.reps, 5)
        XCTAssertEqual(setPayload.rpe, 8)
        XCTAssertEqual(setPayload.loggedExerciseClientId, loggedExercise.id.uuidString.lowercased())
    }

    func testActiveWorkoutDraftEditsProduceNoOutboxEntriesBeforeFinish() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(exercise)

        let session = try engine.startBlankWorkout(context: context)
        let loggedExercise = try engine.addExercises([exercise], to: session, context: context)[0]
        let firstSet = try XCTUnwrap(loggedExercise.sets.first)
        try engine.commitActiveSetDraft(
            firstSet,
            values: .init(weight: 185, reps: 5),
            context: context
        )
        try RPEChipSelectionAction.apply(value: 8, to: firstSet, engine: engine, context: context)
        _ = try engine.addSet(to: loggedExercise, context: context)

        XCTAssertEqual(firstSet.weight, 185)
        XCTAssertEqual(firstSet.reps, 5)
        XCTAssertEqual(firstSet.rpe, 8)
        XCTAssertTrue(firstSet.isCompleted)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    private func fetchEntries(_ context: ModelContext) throws -> [SyncOutboxEntry] {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            .sorted { lhs, rhs in
                if lhs.entityKindRaw == rhs.entityKindRaw {
                    return lhs.entityID.uuidString < rhs.entityID.uuidString
                }
                return lhs.entityKindRaw < rhs.entityKindRaw
            }
    }

    private func assertEntry(
        _ entries: [SyncOutboxEntry],
        kind: SyncEntityKind,
        id: UUID,
        operation: SyncOperation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let entry = entries.first { $0.entityKind == kind && $0.entityID == id }
        XCTAssertNotNil(entry, "Missing \(kind.rawValue) entry for \(id)", file: file, line: line)
        XCTAssertEqual(entry?.operation, operation, file: file, line: line)
        XCTAssertEqual(entry?.status, .pending, file: file, line: line)
    }
}
