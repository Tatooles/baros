import SwiftData
import XCTest
@testable import Baros

@MainActor
final class CompletedWorkoutConcurrentEditTests: XCTestCase {
    func testNotesOnlySavePreparationPreservesNewerTitleWhenOriginalNeedsNormalization() throws {
        for originalTitle in [" Old ", " \n"] {
            let container = try SwiftDataTestSupport.makeInMemoryContainer()
            let context = container.mainContext
            let fixture = makeWorkout(context: context)
            fixture.session.title = originalTitle
            try context.save()
            var draft = CompletedWorkoutEditDraft(session: fixture.session)
            draft.notes = "Local note correction"
            fixture.session.title = "Newer saved title"
            fixture.session.updatedAt = remoteTime
            try context.save()

            // Use the same preparation that the editor performs before saving.
            draft.prepareTitleForSave()
            try save(draft, fixture: fixture, context: context)

            XCTAssertEqual(fixture.session.title, "Newer saved title")
            XCTAssertEqual(fixture.session.notes, "Local note correction")
        }
    }

    func testNotesOnlyEditPreservesNewerUntouchedWorkoutExerciseAndSetFields() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeWorkout(context: context)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: fixture.session)
        draft.notes = "Local note correction"

        fixture.session.title = "Remote title"
        fixture.session.durationSeconds = 2_400
        fixture.session.endedAt = fixture.session.startedAt.addingTimeInterval(2_400)
        fixture.exercise.notes = "Remote exercise note"
        fixture.set.weight = 125
        fixture.set.reps = 8
        fixture.set.rpe = 9
        fixture.set.kind = .failure
        fixture.set.isCompleted = false
        fixture.set.completedAt = nil
        fixture.set.notes = "Remote set note"
        fixture.session.updatedAt = remoteTime
        fixture.exercise.updatedAt = remoteTime
        fixture.set.updatedAt = remoteTime
        try context.save()

        try save(draft, fixture: fixture, context: context)

        XCTAssertEqual(fixture.session.notes, "Local note correction")
        XCTAssertEqual(fixture.session.title, "Remote title")
        XCTAssertEqual(fixture.session.durationSeconds, 2_400)
        XCTAssertEqual(fixture.session.endedAt, fixture.session.startedAt.addingTimeInterval(2_400))
        XCTAssertEqual(fixture.exercise.notes, "Remote exercise note")
        XCTAssertEqual(fixture.exercise.updatedAt, remoteTime)
        XCTAssertEqual(fixture.set.weight, 125)
        XCTAssertEqual(fixture.set.reps, 8)
        XCTAssertEqual(fixture.set.rpe, 9)
        XCTAssertEqual(fixture.set.kind, .failure)
        XCTAssertFalse(fixture.set.isCompleted)
        XCTAssertNil(fixture.set.completedAt)
        XCTAssertEqual(fixture.set.notes, "Remote set note")
        XCTAssertEqual(fixture.set.updatedAt, remoteTime)
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.entityID, fixture.session.id)
    }

    func testConflictingEditsRejectBeforeChangingAnySavedFieldOrOutboxEntry() throws {
        struct Conflict {
            let name: String
            let edit: (inout CompletedWorkoutEditDraft) -> Void
            let updateSaved: (Fixture) -> Void
        }
        let conflicts: [Conflict] = [
            Conflict(name: "title", edit: { $0.title = "Local title" }, updateSaved: { $0.session.title = "Remote title" }),
            Conflict(name: "workout note", edit: { $0.notes = "Local note" }, updateSaved: { $0.session.notes = "Remote note" }),
            Conflict(name: "duration", edit: { $0.durationSeconds = 2_100 }, updateSaved: { $0.session.durationSeconds = 2_400 }),
            Conflict(name: "exercise note", edit: { $0.exercises[0].notes = "Local exercise note" }, updateSaved: { $0.exercise.notes = "Remote exercise note" }),
            Conflict(name: "weight", edit: { $0.exercises[0].sets[0].weight = 150 }, updateSaved: { $0.set.weight = 125 }),
            Conflict(name: "reps", edit: { $0.exercises[0].sets[0].reps = 10 }, updateSaved: { $0.set.reps = 8 }),
            Conflict(name: "RPE", edit: { $0.exercises[0].sets[0].rpe = 10 }, updateSaved: { $0.set.rpe = 9 }),
            Conflict(name: "kind", edit: { $0.exercises[0].sets[0].kind = .warmup }, updateSaved: { $0.set.kind = .failure }),
            Conflict(name: "set note", edit: { $0.exercises[0].sets[0].notes = "Local set note" }, updateSaved: { $0.set.notes = "Remote set note" }),
        ]
        for conflict in conflicts {
            let container = try SwiftDataTestSupport.makeInMemoryContainer()
            let context = container.mainContext
            let fixture = makeWorkout(context: context)
            try context.save()
            var draft = CompletedWorkoutEditDraft(session: fixture.session)
            // This independent local change must also remain unapplied when a later field conflicts.
            draft.exercises[0].sets.append(CompletedWorkoutEditSetDraft(orderIndex: 1, weight: 50, reps: 10))
            conflict.edit(&draft)
            conflict.updateSaved(fixture)
            fixture.session.updatedAt = remoteTime
            fixture.exercise.updatedAt = remoteTime
            fixture.set.updatedAt = remoteTime
            try context.save()
            let savedDraft = CompletedWorkoutEditDraft(session: fixture.session)

            XCTAssertThrowsError(try save(draft, fixture: fixture, context: context), conflict.name) { error in
                XCTAssertEqual(error as? WorkoutHistoryMutationError, .editConflict)
            }

            XCTAssertEqual(fixture.session.title, savedDraft.title, conflict.name)
            XCTAssertEqual(fixture.session.notes, savedDraft.notes, conflict.name)
            XCTAssertEqual(fixture.session.durationSeconds, savedDraft.durationSeconds, conflict.name)
            XCTAssertEqual(fixture.exercise.notes, savedDraft.exercises[0].notes, conflict.name)
            XCTAssertEqual(fixture.set.weight, savedDraft.exercises[0].sets[0].weight, conflict.name)
            XCTAssertEqual(fixture.set.reps, savedDraft.exercises[0].sets[0].reps, conflict.name)
            XCTAssertEqual(fixture.set.rpe, savedDraft.exercises[0].sets[0].rpe, conflict.name)
            XCTAssertEqual(fixture.set.kind, savedDraft.exercises[0].sets[0].kind, conflict.name)
            XCTAssertEqual(fixture.set.notes, savedDraft.exercises[0].sets[0].notes, conflict.name)
            XCTAssertEqual(fixture.exercise.sortedSets.count, 1, conflict.name)
            XCTAssertEqual(fixture.session.updatedAt, remoteTime, conflict.name)
            XCTAssertFalse(context.hasChanges, conflict.name)
            XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty, conflict.name)
        }
    }

    func testUnchangedSavePreservesNewerWorkoutNoteWithoutCreatingSyncWork() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeWorkout(context: context)
        try context.save()
        let draft = CompletedWorkoutEditDraft(session: fixture.session)
        fixture.session.notes = "Newer saved note"
        fixture.session.updatedAt = remoteTime
        try context.save()

        try save(draft, fixture: fixture, context: context)

        XCTAssertEqual(fixture.session.notes, "Newer saved note")
        XCTAssertEqual(fixture.session.updatedAt, remoteTime)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testDifferentFieldsOnSameSetMergeAndPreserveNewlySavedSets() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeWorkout(context: context)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: fixture.session)
        draft.exercises[0].sets[0].weight = 150
        fixture.set.reps = 8
        fixture.set.updatedAt = remoteTime
        let remoteSet = LoggedSet(orderIndex: 1, weight: 75, reps: 12, isCompleted: true)
        remoteSet.loggedExercise = fixture.exercise
        context.insert(remoteSet)
        fixture.exercise.sets.append(remoteSet)
        try context.save()

        try save(draft, fixture: fixture, context: context)

        XCTAssertEqual(fixture.set.weight, 150)
        XCTAssertEqual(fixture.set.reps, 8)
        XCTAssertEqual(fixture.exercise.sortedSets.map(\.id), [fixture.set.id, remoteSet.id])
        XCTAssertEqual(remoteSet.weight, 75)
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(Set(entries.map(\.entityID)), [fixture.set.id, fixture.session.id])
    }

    func testIdenticalConcurrentSetEditsConvergeWithoutChangingCompletionTimeOrQueuingWrites() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeWorkout(context: context)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: fixture.session)
        draft.exercises[0].sets[0].weight = 125
        draft.exercises[0].sets[0].isCompleted = false
        fixture.set.weight = 125
        fixture.set.isCompleted = false
        fixture.set.completedAt = nil
        fixture.set.updatedAt = remoteTime
        try context.save()

        try save(draft, fixture: fixture, context: context)

        XCTAssertEqual(fixture.set.weight, 125)
        XCTAssertFalse(fixture.set.isCompleted)
        XCTAssertNil(fixture.set.completedAt)
        XCTAssertEqual(fixture.set.updatedAt, remoteTime)
        XCTAssertEqual(fixture.session.updatedAt, originalTime)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRemovingASetWithNewerSavedValuesRequiresReviewingAFreshDraft() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeWorkout(context: context)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: fixture.session)
        draft.exercises[0].sets[0].isRemoved = true
        fixture.set.weight = 125
        fixture.set.updatedAt = remoteTime
        try context.save()

        XCTAssertThrowsError(try save(draft, fixture: fixture, context: context)) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .editConflict)
            XCTAssertTrue(error.localizedDescription.contains("Cancel and reopen Edit"))
        }
        XCTAssertFalse(fixture.set.isDeleted)
        XCTAssertEqual(fixture.set.weight, 125)
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)

        var refreshedDraft = CompletedWorkoutEditDraft(session: fixture.session)
        refreshedDraft.exercises[0].sets[0].isRemoved = true
        try save(refreshedDraft, fixture: fixture, context: context)
        XCTAssertTrue(fixture.set.isDeleted)
    }

    func testNumericRoundTripWithinExistingToleranceDoesNotBecomeAConflictingEdit() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeWorkout(context: context)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: fixture.session)
        draft.notes = "Local note correction"
        draft.exercises[0].sets[0].weight = 100.00001
        draft.exercises[0].sets[0].rpe = 8.00001
        fixture.set.weight = 125
        fixture.set.rpe = 9
        fixture.set.updatedAt = remoteTime
        try context.save()

        try save(draft, fixture: fixture, context: context)

        XCTAssertEqual(fixture.set.weight, 125)
        XCTAssertEqual(fixture.set.rpe, 9)
        XCTAssertEqual(fixture.set.updatedAt, remoteTime)
    }

    private let originalTime = Date(timeIntervalSince1970: 1_000)
    private let remoteTime = Date(timeIntervalSince1970: 2_000)
    private let saveTime = Date(timeIntervalSince1970: 3_000)

    private struct Fixture {
        let session: WorkoutSession
        let exercise: LoggedExercise
        let set: LoggedSet
    }

    private func makeWorkout(context: ModelContext) -> Fixture {
        let set = LoggedSet(orderIndex: 0, weight: 100, reps: 5, rpe: 8, isCompleted: true,
                            completedAt: originalTime, createdAt: originalTime, updatedAt: originalTime)
        let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench", notes: "Original exercise note",
                                      createdAt: originalTime, updatedAt: originalTime, sets: [set])
        let session = WorkoutSession(title: "Original title", startedAt: originalTime,
                                     endedAt: originalTime.addingTimeInterval(1_800), durationSeconds: 1_800,
                                     notes: "Original workout note", status: .completed, source: .blank,
                                     createdAt: originalTime, updatedAt: originalTime,
                                     syncOwnerTokenIdentifier: "owner", loggedExercises: [exercise])
        context.insert(session)
        return Fixture(session: session, exercise: exercise, set: set)
    }

    private func save(_ draft: CompletedWorkoutEditDraft, fixture: Fixture, context: ModelContext) throws {
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft, for: fixture.session, ownerTokenIdentifier: "owner", context: context, now: saveTime
        )
    }
}
