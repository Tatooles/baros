import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class SyncOutboxIntegrationTests: XCTestCase {
    func testExerciseServiceCreatesUpdatesAndDeletesOutboxIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let service = ExerciseMutationService()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let deletedAt = Date(timeIntervalSince1970: 300)

        let exercise = try service.createExercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            notes: "",
            context: context,
            now: createdAt
        )

        try service.updateExercise(
            exercise,
            name: "Barbell Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            notes: "Pause reps",
            context: context,
            now: updatedAt
        )

        var entries = try fetchEntries(context)
        var entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.entityKind, .exercise)
        XCTAssertEqual(entry.entityID, exercise.id)
        XCTAssertEqual(entry.operation, .create)
        XCTAssertEqual(entry.createdAt, createdAt)
        XCTAssertEqual(entry.updatedAt, updatedAt)

        try service.removeExercise(exercise, context: context, now: deletedAt)

        entries = try fetchEntries(context)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(exercise.isDeleted)

        let existing = Exercise(
            name: "Deadlift",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Back"
        )
        context.insert(existing)
        try context.save()

        try service.removeExercise(existing, context: context, now: deletedAt)

        entries = try fetchEntries(context)
        entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.entityKind, .exercise)
        XCTAssertEqual(entry.entityID, existing.id)
        XCTAssertEqual(entry.operation, .delete)
    }

    func testRemovingSeededExerciseArchivesAndRecordsUpdateIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let service = ExerciseMutationService()
        let exercise = Exercise(
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads",
            isSeeded: true
        )
        context.insert(exercise)
        try context.save()

        try service.removeExercise(exercise, context: context, now: Date(timeIntervalSince1970: 100))

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertTrue(exercise.isArchived)
        XCTAssertFalse(exercise.isDeleted)
        XCTAssertEqual(entry.entityKind, .exercise)
        XCTAssertEqual(entry.entityID, exercise.id)
        XCTAssertEqual(entry.operation, .update)
    }

    func testSettingsWeightUnitConversionRecordsSettingsAndConvertedSetUpdates() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let service = SettingsMutationService()
        let settings = UserSettings(weightUnit: .pounds)
        let completedSet = LoggedSet(orderIndex: 0, weight: 225, reps: 5, isCompleted: true)
        let placeholderSet = LoggedSet(orderIndex: 1, placeholderWeight: 135, placeholderReps: 8)
        let deletedSet = LoggedSet(
            orderIndex: 2,
            weight: 315,
            reps: 3,
            placeholderWeight: 315,
            placeholderReps: 3,
            isCompleted: true,
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        deletedSet.markDeleted(now: Date(timeIntervalSince1970: 60))
        context.insert(settings)
        context.insert(completedSet)
        context.insert(placeholderSet)
        context.insert(deletedSet)
        try context.save()

        try service.updateWeightUnit(
            .kilograms,
            settings: settings,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(settings.weightUnit, .kilograms)
        XCTAssertEqual(completedSet.weight ?? 0, 102.058, accuracy: 0.001)
        XCTAssertEqual(placeholderSet.placeholderWeight ?? 0, 61.235, accuracy: 0.001)
        XCTAssertEqual(deletedSet.weight, 315)
        XCTAssertEqual(deletedSet.placeholderWeight, 315)

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 3)
        assertEntry(entries, kind: .userSettings, id: settings.id, operation: .update)
        assertEntry(entries, kind: .loggedSet, id: completedSet.id, operation: .update)
        assertEntry(entries, kind: .loggedSet, id: placeholderSet.id, operation: .update)
        XCTAssertFalse(entries.contains { $0.entityID == deletedSet.id })
    }

    func testSettingsWeightUnitConversionKeepsActiveDraftSetOutboxLocalUntilFinish() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(weightUnit: .pounds)
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(settings)
        context.insert(exercise)

        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = try XCTUnwrap(loggedExercise.sets.first)
        try engine.updateSet(set, weight: 225, reps: 5, rpe: 8, context: context)

        try SettingsMutationService().updateWeightUnit(
            .kilograms,
            settings: settings,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(set.weight ?? 0, 102.058, accuracy: 0.001)
        var entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 1)
        assertEntry(entries, kind: .userSettings, id: settings.id, operation: .update)
        XCTAssertFalse(entries.contains { $0.entityKind == .loggedSet })
        XCTAssertFalse(entries.contains { $0.entityKind == .loggedExercise })
        XCTAssertFalse(entries.contains { $0.entityKind == .workoutSession })

        try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 400))

        entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 4)
        assertEntry(entries, kind: .userSettings, id: settings.id, operation: .update)
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .create)
        assertEntry(entries, kind: .loggedExercise, id: loggedExercise.id, operation: .create)
        assertEntry(entries, kind: .loggedSet, id: set.id, operation: .create)
    }

    func testRestTimerUpdateRecordsSettingsUpdateIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(defaultRestTimerSeconds: 90)
        context.insert(settings)
        try context.save()

        try SettingsMutationService().updateDefaultRestTimerSeconds(
            120,
            settings: settings,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(settings.defaultRestTimerSeconds, 120)
        XCTAssertEqual(entry.entityKind, .userSettings)
        XCTAssertEqual(entry.entityID, settings.id)
        XCTAssertEqual(entry.operation, .update)
    }

    func testSettingsMutationUsesCurrentSyncOwnerAndRequestsSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(defaultRestTimerSeconds: 90)
        context.insert(settings)
        try context.save()

        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        try SettingsMutationService(syncScheduler: scheduler).updateDefaultRestTimerSeconds(
            120,
            settings: settings,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(settings.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entry.ownerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testExerciseMutationUsesCurrentSyncOwnerAndRequestsSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        let exercise = try ExerciseMutationService(syncScheduler: scheduler).createExercise(
            name: "Owner Bench",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            notes: "",
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        let entry = try XCTUnwrap(fetchEntries(context).first)
        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entry.ownerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testConfiguredSchedulerRunsRequestedSync() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        let scheduler = SyncScheduler(coordinator: coordinator, modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        scheduler.requestSync()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertEqual(client.fetchRequests.count, 1)
        XCTAssertEqual(client.fetchRequests.first?.cursors, SyncChangeCursors(userSettings: 0, exercises: 0))
    }

    func testExerciseUpdateWithoutChangesDoesNotRecordOrRequestSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            notes: "Pause"
        )
        context.insert(exercise)
        try context.save()

        try ExerciseMutationService(syncScheduler: scheduler).updateExercise(
            exercise,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            notes: "Pause",
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(try fetchEntries(context).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

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
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let firstSet = try XCTUnwrap(loggedExercise.sets.first)
        try engine.updateSet(firstSet, weight: 185, reps: 5, rpe: 8, context: context)
        let secondSet = try engine.addSet(to: loggedExercise, context: context)

        try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 400))

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 4)
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .create)
        assertEntry(entries, kind: .loggedExercise, id: loggedExercise.id, operation: .create)
        assertEntry(entries, kind: .loggedSet, id: firstSet.id, operation: .create)
        assertEntry(entries, kind: .loggedSet, id: secondSet.id, operation: .create)
    }

    func testFinishingWorkoutSkipsDeletedDraftChildrenWhenRecordingCreateIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let bench = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        let squat = Exercise(
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        context.insert(bench)
        context.insert(squat)

        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let visibleLoggedExercise = try engine.addExercise(bench, to: session, context: context)
        let deletedSet = try XCTUnwrap(visibleLoggedExercise.sets.first)
        let visibleSet = try engine.addSet(to: visibleLoggedExercise, context: context)
        let deletedLoggedExercise = try engine.addExercise(squat, to: session, context: context)
        let deletedLoggedExerciseSet = try XCTUnwrap(deletedLoggedExercise.sets.first)

        try engine.removeSet(deletedSet, context: context, now: Date(timeIntervalSince1970: 200))
        try engine.removeLoggedExercise(deletedLoggedExercise, context: context, now: Date(timeIntervalSince1970: 300))

        try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 400))

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 3)
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .create)
        assertEntry(entries, kind: .loggedExercise, id: visibleLoggedExercise.id, operation: .create)
        assertEntry(entries, kind: .loggedSet, id: visibleSet.id, operation: .create)
        XCTAssertFalse(entries.contains { $0.entityID == deletedSet.id })
        XCTAssertFalse(entries.contains { $0.entityID == deletedLoggedExercise.id })
        XCTAssertFalse(entries.contains { $0.entityID == deletedLoggedExerciseSet.id })
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
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let firstSet = try XCTUnwrap(loggedExercise.sets.first)
        try engine.updateSet(firstSet, weight: 185, reps: 5, rpe: 8, context: context)
        _ = try engine.addSet(to: loggedExercise, context: context)
        try engine.toggleSetCompletion(firstSet, context: context)

        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testDeletingWorkoutHistoryRecordsGraphDeleteIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        let session = WorkoutSession(title: "Push", startedAt: .now, status: .completed, source: .blank)
        let firstLoggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        firstLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true),
            LoggedSet(orderIndex: 1, weight: 195, reps: 3, rpe: 9, isCompleted: true)
        ]
        let secondLoggedExercise = LoggedExercise(orderIndex: 1, exercise: exercise, exerciseSnapshotName: exercise.name)
        secondLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 205, reps: 2, rpe: 9, isCompleted: true)
        ]
        session.loggedExercises = [firstLoggedExercise, secondLoggedExercise]
        context.insert(exercise)
        context.insert(session)
        try context.save()

        try WorkoutHistoryMutationService().deleteWorkoutHistory(
            session,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 6)
        XCTAssertTrue(session.isDeleted)
        XCTAssertTrue(session.loggedExercises.allSatisfy(\.isDeleted))
        XCTAssertTrue(session.loggedExercises.flatMap(\.sets).allSatisfy(\.isDeleted))
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .delete)
        assertEntry(entries, kind: .loggedExercise, id: firstLoggedExercise.id, operation: .delete)
        assertEntry(entries, kind: .loggedExercise, id: secondLoggedExercise.id, operation: .delete)
        for set in firstLoggedExercise.sets + secondLoggedExercise.sets {
            assertEntry(entries, kind: .loggedSet, id: set.id, operation: .delete)
        }
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
