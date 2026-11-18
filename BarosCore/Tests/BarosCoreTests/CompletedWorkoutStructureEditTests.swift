import SwiftData
import XCTest
@testable import BarosCore

/// Adding, removing, reordering, swapping, and grouping exercises while
/// editing a completed workout.
@MainActor
final class CompletedWorkoutStructureEditTests: XCTestCase {
    private let owner = "owner"
    private let start = Date(timeIntervalSince1970: 10_000)
    private let saveTime = Date(timeIntervalSince1970: 50_000)

    // MARK: - Adding

    func testAddedExerciseSavesAtTheEndWithItsFilledSetsAndRecordsCreates() throws {
        let (context, session) = try makeWorkout(names: ["Bench", "Row"])
        let squat = insertExercise("Squat", into: context)
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.appendExercises([squat])
        let addedID = try XCTUnwrap(draft.exercises.last?.id)
        XCTAssertTrue(draft.exercises[2].isNew)
        XCTAssertTrue(draft.hasStructureChange)
        draft.exercises[2].sets[0].weight = 225
        draft.exercises[2].sets[0].reps = 5
        draft.exercises[2].sets[0].isCompleted = true
        draft.exercises[2].notes = "Felt strong"
        draft.exercises[2].sets.append(CompletedWorkoutEditSetDraft(orderIndex: 1))
        try save(draft, session, context)

        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName), ["Bench", "Row", "Squat"])
        let added = try XCTUnwrap(session.sortedLoggedExercises.last)
        XCTAssertEqual(added.id, addedID)
        XCTAssertEqual(added.exercise?.id, squat.id)
        XCTAssertEqual(added.orderIndex, 2)
        XCTAssertEqual(added.notes, "Felt strong")
        XCTAssertEqual(added.createdAt, saveTime)
        // The blank second row isn't saved.
        XCTAssertEqual(added.sortedSets.count, 1)
        XCTAssertEqual(added.sortedSets[0].weight, 225)
        XCTAssertEqual(added.sortedSets[0].completedAt, saveTime)
        XCTAssertEqual(session.updatedAt, saveTime)

        let entries = try outbox(context)
        XCTAssertEqual(entries[added.id], .create)
        XCTAssertEqual(entries[added.sortedSets[0].id], .create)
        XCTAssertEqual(entries[session.id], .update)
        XCTAssertEqual(entries.count, 3)
    }

    func testAddingSkipsExercisesAlreadyInTheWorkoutAndCanAddAsSuperset() throws {
        let (context, session) = try makeWorkout(names: ["Bench"])
        let bench = try XCTUnwrap(session.sortedLoggedExercises[0].exercise)
        let curl = insertExercise("Curl", into: context)
        let pushdown = insertExercise("Pushdown", into: context)
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.appendExercises([bench, curl, pushdown], asSuperset: true)

        XCTAssertEqual(draft.exercises.map(\.name), ["Bench", "Curl", "Pushdown"])
        XCTAssertNil(draft.exercises[0].supersetGroupID)
        XCTAssertNotNil(draft.exercises[1].supersetGroupID)
        XCTAssertEqual(draft.exercises[1].supersetGroupID, draft.exercises[2].supersetGroupID)
        XCTAssertEqual(draft.exerciseIDs, [bench.id, curl.id, pushdown.id])
    }

    func testAddedExerciseGetsSetKindsFromItsLastPerformanceBeforeThisWorkout() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let squat = insertExercise("Squat", into: context)
        _ = insertCompletedWorkout(with: squat, kinds: [.warmup, .working], startedAt: start.addingTimeInterval(-86_400), context: context)
        _ = insertCompletedWorkout(with: squat, kinds: [.working, .drop, .failure], startedAt: start.addingTimeInterval(86_400), context: context)
        let session = try makeWorkout(names: ["Bench"], context: context)
        let history = try context.fetch(FetchDescriptor<WorkoutSession>())
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.appendExercises([squat], history: history, ownerTokenIdentifier: owner)

        // The later workout isn't "last time" for an earlier one.
        XCTAssertEqual(draft.exercises[1].sets.map(\.kind), [.warmup, .working])
    }

    func testArchivedAddedExerciseIsRejectedBeforeAnyChange() throws {
        let (context, session) = try makeWorkout(names: ["Bench"])
        let squat = insertExercise("Squat", into: context)
        var draft = CompletedWorkoutEditDraft(session: session)
        draft.appendExercises([squat])
        draft.exercises[1].sets[0].reps = 5
        draft.title = "Leg day"
        squat.isArchived = true
        try context.save()

        XCTAssertThrowsError(try save(draft, session, context)) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .unavailableExercise)
        }
        XCTAssertEqual(session.title, "Workout")
        XCTAssertEqual(session.sortedLoggedExercises.count, 1)
        XCTAssertTrue(try outbox(context).isEmpty)
    }

    // MARK: - Removing

    func testRemovingExerciseTombstonesItsSetsReindexesAndRecordsDeletes() throws {
        let (context, session) = try makeWorkout(names: ["Bench", "Row", "Squat"])
        let row = session.sortedLoggedExercises[1]
        let rowSetIDs = row.sortedSets.map(\.id)
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.removeExercises([row.id])
        try save(draft, session, context)

        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName), ["Bench", "Squat"])
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1])
        XCTAssertEqual(row.deletedAt, saveTime)
        XCTAssertTrue(row.sets.allSatisfy { $0.deletedAt == saveTime })

        let entries = try outbox(context)
        XCTAssertEqual(entries[row.id], .delete)
        for id in rowSetIDs { XCTAssertEqual(entries[id], .delete) }
        XCTAssertEqual(entries[session.sortedLoggedExercises[1].id], .update)
        XCTAssertNil(entries[session.sortedLoggedExercises[0].id])
    }

    func testRemovingOneOfASupersetPairUngroupsTheOther() throws {
        let (context, session) = try makeWorkout(names: ["Bench", "Row", "Squat"], groups: [0, 0, nil])
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.removeExercises([session.sortedLoggedExercises[1].id])
        try save(draft, session, context)

        XCTAssertEqual(session.sortedLoggedExercises.map(\.supersetGroupID), [nil, nil])
        XCTAssertTrue(session.sortedLoggedExercises[0].hasLocalSupersetChange)
    }

    // MARK: - Reordering and grouping

    func testReorderWritesOrderAndRecordsUpdatesOnlyForMovedExercises() throws {
        let (context, session) = try makeWorkout(names: ["Bench", "Row", "Squat"])
        let ids = session.sortedLoggedExercises.map(\.id)
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.reorderExercises([ids[1], ids[0], ids[2]])
        try save(draft, session, context)

        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName), ["Row", "Bench", "Squat"])
        let entries = try outbox(context)
        XCTAssertEqual(entries[ids[0]], .update)
        XCTAssertEqual(entries[ids[1]], .update)
        XCTAssertNil(entries[ids[2]])
        XCTAssertEqual(entries[session.id], .update)
    }

    func testReorderIgnoresAnIncompleteOrder() throws {
        let (_, session) = try makeWorkout(names: ["Bench", "Row"])
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.reorderExercises([session.sortedLoggedExercises[1].id])

        XCTAssertEqual(draft.exercises.map(\.name), ["Bench", "Row"])
        XCTAssertFalse(draft.hasStructureChange)
    }

    func testMenuSupersetChangesPersistGrouping() throws {
        let (context, session) = try makeWorkout(names: ["Bench", "Row", "Squat"])
        let ids = session.sortedLoggedExercises.map(\.id)
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.changeSuperset(.joinNext, forExerciseID: ids[0])
        draft.changeSuperset(.joinPrevious, forExerciseID: ids[2])
        XCTAssertEqual(Set(draft.exercises.map(\.supersetGroupID)).count, 1)
        draft.changeSuperset(.remove, forExerciseID: ids[2])
        try save(draft, session, context)

        let groups = session.sortedLoggedExercises.map(\.supersetGroupID)
        XCTAssertNotNil(groups[0])
        XCTAssertEqual(groups[0], groups[1])
        XCTAssertNil(groups[2])
        XCTAssertTrue(session.sortedLoggedExercises[0].hasLocalSupersetChange)
        XCTAssertFalse(session.sortedLoggedExercises[2].hasLocalSupersetChange)
        let entries = try outbox(context)
        XCTAssertEqual(entries[ids[0]], .update)
        XCTAssertEqual(entries[ids[1]], .update)
        XCTAssertNil(entries[ids[2]])
    }

    func testSplitAndRejoinedSupersetIsNotAChange() throws {
        let (context, session) = try makeWorkout(names: ["Bench", "Row"], groups: [0, 0])
        let originalGroup = session.sortedLoggedExercises[0].supersetGroupID
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.regroup(SupersetGrouping.togglingLink(draft.exercises.map(\.supersetGroupID), below: 0))
        draft.regroup(SupersetGrouping.togglingLink(draft.exercises.map(\.supersetGroupID), below: 0))

        XCTAssertFalse(draft.hasStructureChange)
        try save(draft, session, context)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.supersetGroupID), [originalGroup, originalGroup])
        XCTAssertTrue(try outbox(context).isEmpty)
    }

    // MARK: - Swapping

    func testSwapReplacesExerciseInPlaceAndKeepsItsSuperset() throws {
        let (context, session) = try makeWorkout(names: ["Bench", "Row", "Squat"], groups: [0, 0, nil])
        let row = session.sortedLoggedExercises[1]
        let pullup = insertExercise("Pull-up", into: context)
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.swapExercise(id: row.id, with: pullup)
        draft.exercises[1].sets[0].reps = 10
        try save(draft, session, context)

        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName), ["Bench", "Pull-up", "Squat"])
        let replacement = session.sortedLoggedExercises[1]
        XCTAssertNotEqual(replacement.id, row.id)
        XCTAssertEqual(replacement.supersetGroupID, session.sortedLoggedExercises[0].supersetGroupID)
        XCTAssertEqual(replacement.sortedSets.map(\.reps), [10])
        XCTAssertNotNil(row.deletedAt)
        XCTAssertTrue(row.sets.allSatisfy { $0.deletedAt != nil })
    }

    func testSwapIgnoresTheSameExerciseButAllowsOneElsewhereInTheWorkout() throws {
        let (_, session) = try makeWorkout(names: ["Bench", "Row"])
        let bench = try XCTUnwrap(session.sortedLoggedExercises[0].exercise)
        let row = try XCTUnwrap(session.sortedLoggedExercises[1].exercise)
        var draft = CompletedWorkoutEditDraft(session: session)

        draft.swapExercise(id: session.sortedLoggedExercises[1].id, with: row)
        XCTAssertFalse(draft.hasStructureChange)

        draft.swapExercise(id: session.sortedLoggedExercises[1].id, with: bench)
        XCTAssertEqual(draft.exercises.map(\.name), ["Bench", "Bench"])
        XCTAssertTrue(draft.exercises[1].isNew)
    }

    // MARK: - Concurrent changes

    func testStructureEditConflictsWithASavedStructureChange() throws {
        let (context, session) = try makeWorkout(names: ["Bench", "Row"])
        let ids = session.sortedLoggedExercises.map(\.id)
        var draft = CompletedWorkoutEditDraft(session: session)
        draft.reorderExercises([ids[1], ids[0]])
        draft.notes = "Local note"

        // Sync groups the two exercises while the editor is open.
        let group = UUID()
        for exercise in session.sortedLoggedExercises { exercise.supersetGroupID = group }
        try context.save()

        XCTAssertThrowsError(try save(draft, session, context)) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .editConflict)
        }
        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), ids)
        XCTAssertEqual(session.notes, "")
        XCTAssertTrue(try outbox(context).isEmpty)
    }

    func testUnchangedListKeepsAnExerciseSavedWhileEditing() throws {
        let (context, session) = try makeWorkout(names: ["Bench"])
        var draft = CompletedWorkoutEditDraft(session: session)
        draft.notes = "Local note"

        let synced = LoggedExercise(orderIndex: 1, exercise: insertExercise("Row", into: context))
        synced.session = session
        context.insert(synced)
        session.loggedExercises.append(synced)
        try context.save()

        try save(draft, session, context)

        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName), ["Bench", "Row"])
        XCTAssertNil(synced.deletedAt)
        XCTAssertEqual(session.notes, "Local note")
    }

    // MARK: - Helpers

    private func makeWorkout(names: [String], groups: [Int?]? = nil) throws -> (ModelContext, WorkoutSession) {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        // Keep the container alive for the test's duration.
        containers.append(container)
        return (context, try makeWorkout(names: names, groups: groups, context: context))
    }

    private var containers: [ModelContainer] = []

    private func makeWorkout(names: [String], groups: [Int?]? = nil, context: ModelContext) throws -> WorkoutSession {
        let groupIDs = [UUID(), UUID()]
        let session = WorkoutSession(
            title: "Workout", startedAt: start, endedAt: start.addingTimeInterval(1_800), durationSeconds: 1_800,
            status: .completed, source: .blank, createdAt: start, updatedAt: start, syncOwnerTokenIdentifier: owner
        )
        context.insert(session)
        for (index, name) in names.enumerated() {
            let logged = LoggedExercise(
                orderIndex: index, exercise: insertExercise(name, into: context),
                supersetGroupID: groups?[index].map { groupIDs[$0] },
                createdAt: start, updatedAt: start
            )
            context.insert(logged)
            logged.session = session
            session.loggedExercises.append(logged)
            for setIndex in 0..<2 {
                let set = LoggedSet(orderIndex: setIndex, weight: 100, reps: 5, isCompleted: true,
                                    completedAt: start, createdAt: start, updatedAt: start)
                context.insert(set)
                set.loggedExercise = logged
                logged.sets.append(set)
            }
        }
        try context.save()
        return session
    }

    private func insertCompletedWorkout(
        with exercise: Exercise, kinds: [SetKind], startedAt: Date, context: ModelContext
    ) -> WorkoutSession {
        let session = WorkoutSession(
            title: "Other", startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600), durationSeconds: 600,
            status: .completed, source: .blank, createdAt: startedAt, updatedAt: startedAt,
            syncOwnerTokenIdentifier: owner
        )
        context.insert(session)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise, createdAt: startedAt, updatedAt: startedAt)
        context.insert(logged)
        logged.session = session
        session.loggedExercises.append(logged)
        for (index, kind) in kinds.enumerated() {
            let set = LoggedSet(orderIndex: index, weight: 100, reps: 5, kind: kind, isCompleted: true,
                                completedAt: startedAt, createdAt: startedAt, updatedAt: startedAt)
            context.insert(set)
            set.loggedExercise = logged
            logged.sets.append(set)
        }
        return session
    }

    private func insertExercise(_ name: String, into context: ModelContext) -> Exercise {
        let exercise = Exercise(
            name: name, category: .strength, equipment: .barbell, primaryMuscleGroup: .chest,
            syncOwnerTokenIdentifier: owner
        )
        context.insert(exercise)
        return exercise
    }

    private func save(_ draft: CompletedWorkoutEditDraft, _ session: WorkoutSession, _ context: ModelContext) throws {
        do {
            try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
                draft, for: session, ownerTokenIdentifier: owner, context: context, now: saveTime
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Active logged-exercise, set, and session entries by entity id.
    private func outbox(_ context: ModelContext) throws -> [UUID: SyncOperation] {
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            .filter { $0.isActive && $0.entityKind != .exercise }
        return Dictionary(entries.compactMap { entry in entry.operation.map { (entry.entityID, $0) } },
                          uniquingKeysWith: { $1 })
    }
}
