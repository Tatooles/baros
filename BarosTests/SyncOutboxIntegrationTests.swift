import SwiftData
import XCTest
@testable import Baros

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

    func testSettingsWeightUnitChangeRecordsOnlySettingsUpdate() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let service = SettingsMutationService()
        let settings = UserSettings(weightUnit: .pounds)
        let completedUpdatedAt = Date(timeIntervalSince1970: 40)
        let completedSet = LoggedSet(
            orderIndex: 0,
            weight: 225,
            reps: 5,
            isCompleted: true,
            updatedAt: completedUpdatedAt
        )
        context.insert(settings)
        context.insert(completedSet)
        try context.save()

        try service.updateWeightUnit(
            .kilograms,
            settings: settings,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(settings.weightUnit, .kilograms)
        XCTAssertEqual(completedSet.weight, 225)
        XCTAssertEqual(completedSet.updatedAt, completedUpdatedAt)

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 1)
        assertEntry(entries, kind: .userSettings, id: settings.id, operation: .update)
    }

    func testSettingsWeightUnitChangeKeepsActiveDraftSetCanonicalUntilFinish() throws {
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

        XCTAssertEqual(set.weight, 225)
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

    func testSettingsWeightUnitChangeDoesNotClaimOwnerlessCompletedWorkoutGraph() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let settings = UserSettings(weightUnit: .pounds, syncOwnerTokenIdentifier: "issuer|owner_a")
        let session = WorkoutSession(
            title: "Legacy Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let set = LoggedSet(orderIndex: 0, weight: 225, reps: 5, isCompleted: true)
        set.loggedExercise = loggedExercise
        loggedExercise.session = session
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        context.insert(settings)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(set)
        try context.save()

        try SettingsMutationService(syncScheduler: scheduler).updateWeightUnit(
            .kilograms,
            settings: settings,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )

        let entries = try fetchEntries(context)
        XCTAssertEqual(set.weight, 225)
        XCTAssertNil(session.syncOwnerTokenIdentifier)
        XCTAssertEqual(entries.count, 1)
        assertEntry(entries, kind: .userSettings, id: settings.id, operation: .update)
        XCTAssertTrue(entries.allSatisfy { $0.ownerTokenIdentifier == "issuer|owner_a" })
        XCTAssertEqual(scheduler.requestCount, 1)
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

    func testSettingsMutationRejectsDifferentCurrentOwner() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )
        context.insert(settings)
        try context.save()

        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"

        XCTAssertThrowsError(
            try SettingsMutationService(syncScheduler: scheduler).updateDefaultRestTimerSeconds(
                120,
                settings: settings,
                context: context,
                now: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(error as? SyncMutationOwnershipError, .ownerMismatch)
        }

        XCTAssertEqual(settings.defaultRestTimerSeconds, 90)
        XCTAssertEqual(settings.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertTrue(try fetchEntries(context).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testExerciseMutationRejectsDifferentCurrentOwner() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"
        let exercise = Exercise(
            name: "Owner Bench",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )
        context.insert(exercise)
        try context.save()

        XCTAssertThrowsError(
            try ExerciseMutationService(syncScheduler: scheduler).updateExercise(
                exercise,
                name: "Owner Bench Updated",
                category: .strength,
                equipment: .barbell,
                primaryMuscle: "Chest",
                notes: "",
                context: context,
                now: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(error as? SyncMutationOwnershipError, .ownerMismatch)
        }

        XCTAssertEqual(exercise.name, "Owner Bench")
        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertTrue(try fetchEntries(context).isEmpty)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testConfiguredSchedulerRunsRequestedSync() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
        let scheduler = SyncScheduler(coordinator: coordinator, modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let fetchCompleted = expectation(description: "scheduler runs sync fetch")
        client.onFetchChanges = {
            fetchCompleted.fulfill()
        }

        scheduler.requestSync()
        await fulfillment(of: [fetchCompleted], timeout: 1.0)

        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertEqual(client.fetchRequests.count, 1)
        XCTAssertEqual(client.fetchRequests.first?.cursors, SyncChangeCursors(userSettings: 0, exercises: 0))
    }

    func testConfiguredSchedulerSeedsDefaultsForCurrentOwner() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: "issuer|owner_a")

        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: FakeSyncClient()), modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"

        scheduler.seedDefaultsForCurrentOwner()

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: "issuer|owner_b").count,
            1
        )
        XCTAssertEqual(
            Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: "issuer|owner_b")
                .filter(\.isSeeded)
                .count,
            20
        )
    }

    func testConfiguredSchedulerClaimsOwnerlessDefaultsForUnbootstrappedOwner() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context)

        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: FakeSyncClient()), modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        scheduler.seedDefaultsForCurrentOwner()

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: "issuer|owner_a").count,
            1
        )
        XCTAssertEqual(
            Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: "issuer|owner_a")
                .filter(\.isSeeded)
                .count,
            20
        )
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: nil).count,
            0
        )
        XCTAssertTrue(
            Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: nil)
                .filter(\.isSeeded)
                .isEmpty
        )
    }

    func testConfiguredSchedulerDoesNotClaimOwnerlessDefaultsForBootstrappedOwner() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context)
        let state = try SyncCursorState.state(for: "issuer|owner_a", context: context)
        state.hasBootstrappedSettingsExercises = true
        try context.save()

        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: FakeSyncClient()), modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        scheduler.seedDefaultsForCurrentOwner()

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: nil).count,
            1
        )
        XCTAssertEqual(
            Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: nil)
                .filter(\.isSeeded)
                .count,
            20
        )
    }

    func testConfiguredSchedulerSeedsDefaultsForLocalMode() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: "issuer|owner_a")

        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: FakeSyncClient()), modelContext: context)
        scheduler.currentOwnerTokenIdentifier = nil

        scheduler.seedDefaultsForLocalMode()

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: nil)
                .filter { $0.syncOwnerTokenIdentifier == nil }
                .count,
            1
        )
        XCTAssertEqual(
            Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: nil)
                .filter { $0.syncOwnerTokenIdentifier == nil && $0.isSeeded }
                .count,
            20
        )
    }

    func testSchedulerQueuesRequestDuringActiveSync() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
        let scheduler = SyncScheduler(coordinator: coordinator, modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let fetchCompleted = expectation(description: "scheduler runs queued sync fetch")
        fetchCompleted.expectedFulfillmentCount = 2
        client.onFetchChanges = {
            if client.fetchRequests.count == 1 {
                scheduler.requestSync()
            }
            fetchCompleted.fulfill()
        }

        scheduler.requestSync()
        await fulfillment(of: [fetchCompleted], timeout: 1.0)

        XCTAssertEqual(scheduler.requestCount, 2)
        XCTAssertEqual(client.fetchRequests.count, 2)
        XCTAssertEqual(client.fetchRequests.first?.cursors, SyncChangeCursors(userSettings: 0, exercises: 0))
        XCTAssertEqual(client.fetchRequests.last?.cursors, SyncChangeCursors(userSettings: 0, exercises: 0))
    }

    func testSchedulerStopsOldOwnerSyncWhenOwnerChangesDuringRun() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005501")!,
            name: "Owner A Bench",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
        let scheduler = SyncScheduler(coordinator: coordinator, modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let fetchCompleted = expectation(description: "initial old-owner pull runs")
        var didChangeOwner = false
        client.onFetchChanges = {
            if !didChangeOwner {
                didChangeOwner = true
                scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"
                fetchCompleted.fulfill()
            }
        }

        scheduler.requestSync()
        await fulfillment(of: [fetchCompleted], timeout: 1.0)
        try await Task.sleep(nanoseconds: 50_000_000)

        let entries = try fetchEntries(context)
        XCTAssertTrue(client.upsertedExercises.isEmpty)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.entityID, exercise.id)
        XCTAssertEqual(entries.first?.ownerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entries.first?.status, .pending)
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

    func testPrepareForSyncBackfillsOwnedCompletedSetsWhenSetCursorNeverAdvanced() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let state = try SyncCursorState.state(for: owner, context: context)
        state.hasBootstrappedSettingsExercises = true
        state.hasBootstrappedWorkoutGraph = true
        let session = WorkoutSession(
            title: "Partially Bootstrapped",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: owner
        )
        let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true)
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        session.loggedExercises.append(loggedExercise)
        loggedExercise.sets.append(set)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(set)
        try context.save()

        try SyncCoordinator(client: FakeSyncClient()).prepareForSync(
            ownerTokenIdentifier: owner,
            context: context,
            bootstrapScope: .allOwned,
            includeOwnerlessCompletedWorkouts: false
        )

        let entries = try fetchEntries(context)
        XCTAssertFalse(entries.contains { $0.entityKind == .workoutSession })
        XCTAssertFalse(entries.contains { $0.entityKind == .loggedExercise })
        assertEntry(entries, kind: .loggedSet, id: set.id, operation: .create)
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

    func testDeletingOwnedWorkoutHistoryWhileSignedOutRejectsWithoutMutating() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context, ownerTokenIdentifier: "issuer|owner_a")
        try context.save()

        XCTAssertThrowsError(try WorkoutHistoryMutationService().deleteWorkoutHistory(
            session,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .ownerMismatch)
        }

        XCTAssertFalse(session.isDeleted)
        XCTAssertTrue(session.loggedExercises.allSatisfy { !$0.isDeleted })
        XCTAssertTrue(session.loggedExercises.flatMap(\.sets).allSatisfy { !$0.isDeleted })
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testDeletingUnattemptedFinishedWorkoutRemovesCreateIntentInsteadOfTombstoning() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(exercise)
        try context.save()

        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = try XCTUnwrap(loggedExercise.sets.first)
        try engine.updateSet(set, weight: 185, reps: 5, rpe: 8, context: context)
        try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(try fetchEntries(context).count, 3)

        try WorkoutHistoryMutationService().deleteWorkoutHistory(
            session,
            context: context,
            now: Date(timeIntervalSince1970: 250)
        )

        XCTAssertTrue(session.isDeleted)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testDeletingAttemptedFinishedWorkoutKeepsGraphDeleteIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(exercise)
        try context.save()

        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = try XCTUnwrap(loggedExercise.sets.first)
        try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 200))

        let recorder = SyncOutboxRecorder()
        for entry in try fetchEntries(context) {
            recorder.markInFlight(entry, now: Date(timeIntervalSince1970: 225))
        }

        try WorkoutHistoryMutationService().deleteWorkoutHistory(
            session,
            context: context,
            now: Date(timeIntervalSince1970: 250)
        )

        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 3)
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .delete)
        assertEntry(entries, kind: .loggedExercise, id: loggedExercise.id, operation: .delete)
        assertEntry(entries, kind: .loggedSet, id: set.id, operation: .delete)
    }

    func testEditingOwnerlessCompletedWorkoutSessionFieldsBootstrapsGraphForSignedInSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_100)
        let editTime = Date(timeIntervalSince1970: 2_000)
        let session = makeCompletedWorkout(
            context: context,
            title: "Push",
            startedAt: startedAt,
            durationSeconds: 3_600,
            updatedAt: originalUpdatedAt
        )
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.title = "Push corrected"
        draft.notes = "Felt better than logged"
        draft.durationSeconds = 2_700

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: editTime
        )

        let entries = try fetchEntries(context)
        XCTAssertEqual(session.title, "Push corrected")
        XCTAssertEqual(session.notes, "Felt better than logged")
        XCTAssertEqual(session.durationSeconds, 2_700)
        XCTAssertEqual(session.endedAt, startedAt.addingTimeInterval(2_700))
        XCTAssertEqual(session.updatedAt, editTime)
        XCTAssertEqual(session.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entries.count, 4)
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .create)
        assertEntry(entries, kind: .loggedExercise, id: try XCTUnwrap(session.sortedLoggedExercises.first?.id), operation: .create)
        for set in try XCTUnwrap(session.sortedLoggedExercises.first).sortedSets {
            assertEntry(entries, kind: .loggedSet, id: set.id, operation: .create)
        }
    }

    func testEditingOwnerlessCompletedWorkoutSetBootstrapsGraphForSignedInSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context)
        let loggedExercise = try XCTUnwrap(session.sortedLoggedExercises.first)
        let set = try XCTUnwrap(session.sortedLoggedExercises.first?.sortedSets.first)
        let editTime = Date(timeIntervalSince1970: 2_000)
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.exercises[0].sets[0].weight = 225
        draft.exercises[0].sets[0].reps = 8
        draft.exercises[0].sets[0].rpe = 8.5
        draft.exercises[0].sets[0].kind = .warmup
        draft.exercises[0].sets[0].isCompleted = false
        draft.exercises[0].sets[0].notes = "Corrected set"

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "issuer|owner_a",
            context: context,
            now: editTime
        )

        let entries = try fetchEntries(context)
        XCTAssertEqual(session.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(set.weight, 225)
        XCTAssertEqual(set.reps, 8)
        XCTAssertEqual(set.rpe, 8.5)
        XCTAssertEqual(set.kind, .warmup)
        XCTAssertFalse(set.isCompleted)
        XCTAssertNil(set.completedAt)
        XCTAssertEqual(set.notes, "Corrected set")
        XCTAssertEqual(set.updatedAt, editTime)
        XCTAssertEqual(session.updatedAt, editTime)
        XCTAssertEqual(entries.count, 4)
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .create)
        assertEntry(entries, kind: .loggedExercise, id: loggedExercise.id, operation: .create)
        for visibleSet in loggedExercise.sortedSets {
            assertEntry(entries, kind: .loggedSet, id: visibleSet.id, operation: .create)
        }
    }

    func testSavingCompletedWorkoutEditRejectsOutOfPolicyNumericValues() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context)
        let set = try XCTUnwrap(session.sortedLoggedExercises.first?.sortedSets.first)
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.exercises[0].sets[0].weight = 10_001
        draft.exercises[0].sets[0].reps = 1_001
        draft.exercises[0].sets[0].rpe = 10.1

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            context: context
        )

        XCTAssertNil(set.weight)
        XCTAssertNil(set.reps)
        XCTAssertNil(set.rpe)
    }

    func testEditingOwnedCompletedWorkoutSetRecordsSetAndSessionUpdates() throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context, ownerTokenIdentifier: owner)
        let set = try XCTUnwrap(session.sortedLoggedExercises.first?.sortedSets.first)
        let editTime = Date(timeIntervalSince1970: 2_000)
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.exercises[0].sets[0].weight = 225

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: owner,
            context: context,
            now: editTime
        )

        let entries = try fetchEntries(context)
        XCTAssertEqual(session.syncOwnerTokenIdentifier, owner)
        XCTAssertEqual(set.weight, 225)
        XCTAssertEqual(set.updatedAt, editTime)
        XCTAssertEqual(session.updatedAt, editTime)
        XCTAssertEqual(entries.count, 2)
        assertEntry(entries, kind: .workoutSession, id: session.id, operation: .update)
        assertEntry(entries, kind: .loggedSet, id: set.id, operation: .update)
    }

    func testSignedOutEditingOwnerlessCompletedWorkoutAddsAndRemovesSetsWithoutOutbox() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context)
        let loggedExercise = try XCTUnwrap(session.sortedLoggedExercises.first)
        let tombstonedSet = LoggedSet(orderIndex: 9, weight: 95, reps: 10, isCompleted: true)
        tombstonedSet.markDeleted(now: Date(timeIntervalSince1970: 150))
        tombstonedSet.loggedExercise = loggedExercise
        loggedExercise.sets.append(tombstonedSet)
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        let removedSetID = try XCTUnwrap(draft.exercises[0].sets[0].id)
        let shiftedSetID = try XCTUnwrap(draft.exercises[0].sets[1].id)
        draft.exercises[0].sets[0].isRemoved = true
        draft.exercises[0].sets.append(CompletedWorkoutEditSetDraft(
            orderIndex: 2,
            weight: 235,
            reps: 4,
            rpe: 9,
            kind: .working,
            isCompleted: true,
            notes: "Added after the fact"
        ))

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        let entries = try fetchEntries(context)
        let allSets = try context.fetch(FetchDescriptor<LoggedSet>())
        let visibleSets = loggedExercise.sortedSets
        let removedSetAfterSave = try XCTUnwrap(allSets.first { $0.id == removedSetID })
        let shiftedSetAfterSave = try XCTUnwrap(allSets.first { $0.id == shiftedSetID })
        let addedSet = try XCTUnwrap(visibleSets.first { $0.notes == "Added after the fact" })
        XCTAssertTrue(removedSetAfterSave.isDeleted)
        XCTAssertEqual(removedSetAfterSave.orderIndex, 0)
        XCTAssertEqual(shiftedSetAfterSave.orderIndex, 0)
        XCTAssertEqual(tombstonedSet.orderIndex, 9)
        XCTAssertEqual(addedSet.orderIndex, 1)
        XCTAssertEqual(addedSet.weight, 235)
        XCTAssertEqual(addedSet.reps, 4)
        XCTAssertEqual(addedSet.rpe, 9)
        XCTAssertTrue(addedSet.isCompleted)
        XCTAssertEqual(addedSet.completedAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(addedSet.notes, "Added after the fact")
        XCTAssertNil(session.syncOwnerTokenIdentifier)
        XCTAssertTrue(entries.isEmpty)
    }

    func testSignedOutEditingPendingOwnerlessCompletedWorkoutEnqueuesAddedSetForClaim() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            userSettingsCursor: 1,
            exercisesCursor: 1,
            workoutSessionsCursor: 1,
            loggedExercisesCursor: 1,
            loggedSetsCursor: 1,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        let session = makeCompletedWorkout(context: context)
        let loggedExercise = try XCTUnwrap(session.sortedLoggedExercises.first)
        try context.save()

        try SyncOutboxRecorder().bootstrapV1SyncableRecords(
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 1_500)
        )
        XCTAssertEqual(try fetchEntries(context).count, 4)

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.exercises[0].sets.append(CompletedWorkoutEditSetDraft(
            orderIndex: 2,
            weight: 245,
            reps: 2,
            rpe: 9.5,
            kind: .working,
            isCompleted: true,
            notes: "Signed-out added set"
        ))

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        let addedSet = try XCTUnwrap(loggedExercise.sortedSets.first { $0.notes == "Signed-out added set" })
        let entries = try fetchEntries(context)
        XCTAssertEqual(entries.count, 5)
        assertEntry(entries, kind: .loggedSet, id: addedSet.id, operation: .create)
        XCTAssertNil(entries.first { $0.entityKind == .loggedSet && $0.entityID == addedSet.id }?.ownerTokenIdentifier)

        let client = FakeSyncClient()
        let result = try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(result.didPush)
        XCTAssertEqual(session.syncOwnerTokenIdentifier, owner)
        let addedPayload = try XCTUnwrap(client.upsertedLoggedSets.first {
            $0.clientId == addedSet.id.uuidString.lowercased()
        })
        XCTAssertEqual(addedPayload.weight, 245)
        XCTAssertEqual(addedPayload.reps, 2)
        XCTAssertEqual(addedPayload.rpe, 9.5)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testSignedOutEditingOwnerlessCompletedWorkoutDoesNotBypassBootstrapPolicyOnSignIn() async throws {
        let ownerA = "issuer|owner_a"
        let ownerB = "issuer|owner_b"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: ownerB,
            userSettingsCursor: 1,
            exercisesCursor: 1,
            workoutSessionsCursor: 1,
            loggedExercisesCursor: 1,
            loggedSetsCursor: 1,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        let session = makeCompletedWorkout(context: context)
        let set = try XCTUnwrap(session.sortedLoggedExercises.first?.sortedSets.first)
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.title = "Signed-out edit"
        draft.exercises[0].sets[0].weight = 225

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(session.title, "Signed-out edit")
        XCTAssertEqual(set.weight, 225)
        XCTAssertNil(session.syncOwnerTokenIdentifier)
        XCTAssertTrue(try fetchEntries(context).isEmpty)

        let client = FakeSyncClient()
        let result = try await SyncCoordinator(client: client).run(ownerTokenIdentifier: ownerA, context: context)

        XCTAssertFalse(result.didPush)
        XCTAssertNil(session.syncOwnerTokenIdentifier)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
        XCTAssertTrue(client.operationLog.isEmpty)
    }

    func testEditingCompletedWorkoutIgnoresEmptyNewSetDraft() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context)
        let loggedExercise = try XCTUnwrap(session.sortedLoggedExercises.first)
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.exercises[0].sets.append(CompletedWorkoutEditSetDraft(orderIndex: 2))

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(loggedExercise.sortedSets.count, 2)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testNoOpCompletedWorkoutEditDoesNotTouchTimestampsOrOutbox() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context)
        let set = try XCTUnwrap(session.sortedLoggedExercises.first?.sortedSets.first)
        let sessionUpdatedAt = session.updatedAt
        let setUpdatedAt = set.updatedAt
        try context.save()

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            CompletedWorkoutEditDraft(session: session),
            for: session,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(session.updatedAt, sessionUpdatedAt)
        XCTAssertEqual(set.updatedAt, setUpdatedAt)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testNoOpCompletedWorkoutEditDoesNotNormalizeLegacyEndedAtDuration() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let endedAt = startedAt.addingTimeInterval(3_247)
        let session = makeCompletedWorkout(
            context: context,
            startedAt: startedAt,
            durationSeconds: 0
        )
        session.endedAt = endedAt
        let sessionUpdatedAt = session.updatedAt
        try context.save()

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            CompletedWorkoutEditDraft(session: session),
            for: session,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(session.durationSeconds, 0)
        XCTAssertEqual(session.endedAt, endedAt)
        XCTAssertEqual(session.updatedAt, sessionUpdatedAt)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testCompletedWorkoutDurationInputPreservesNonMinuteAlignedSecondsWhenUnchanged() throws {
        let initialDurationSeconds = 3_247
        let minutesText = CompletedWorkoutDurationInput.minutesText(for: initialDurationSeconds)

        let resolvedDurationSeconds = try CompletedWorkoutDurationInput.durationSeconds(
            from: minutesText,
            initialMinutesText: minutesText,
            initialDurationSeconds: initialDurationSeconds
        )

        XCTAssertEqual(minutesText, "54")
        XCTAssertEqual(resolvedDurationSeconds, initialDurationSeconds)
    }

    func testCompletedWorkoutDurationInputRejectsBlankDurationWhenChanged() throws {
        XCTAssertThrowsError(try CompletedWorkoutDurationInput.durationSeconds(
            from: "",
            initialMinutesText: "54",
            initialDurationSeconds: 3_247
        )) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .invalidDuration)
        }
    }

    func testCompletedWorkoutDurationInputRejectsOverflowingMinutes() throws {
        XCTAssertThrowsError(try CompletedWorkoutDurationInput.durationSeconds(
            from: String(Int.max),
            initialMinutesText: "54",
            initialDurationSeconds: 3_247
        )) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .invalidDuration)
        }
    }

    func testCompletedWorkoutEditRejectsOwnerMismatchWithoutMutating() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context, ownerTokenIdentifier: "issuer|owner_a")
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.title = "Should not save"

        XCTAssertThrowsError(try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "issuer|owner_b",
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        ))

        XCTAssertEqual(session.title, "Push")
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testCompletedWorkoutEditRejectsOwnedWorkoutWhileSignedOut() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = makeCompletedWorkout(context: context, ownerTokenIdentifier: "issuer|owner_a")
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.title = "Should not save"

        XCTAssertThrowsError(try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .ownerMismatch)
        }

        XCTAssertEqual(session.title, "Push")
        XCTAssertEqual(session.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testEditingOwnerlessCompletedWorkoutRejectsBootstrapWhenAnotherOwnerHasLocalSyncState() throws {
        let ownerA = "issuer|owner_a"
        let ownerB = "issuer|owner_b"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: ownerB,
            userSettingsCursor: 1,
            exercisesCursor: 1,
            workoutSessionsCursor: 1,
            loggedExercisesCursor: 1,
            loggedSetsCursor: 1,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        let session = makeCompletedWorkout(context: context)
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.title = "Should not save"
        draft.exercises[0].sets[0].weight = 225

        XCTAssertThrowsError(try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: ownerA,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .ownerlessBootstrapBlocked)
        }

        XCTAssertNil(session.syncOwnerTokenIdentifier)
        XCTAssertEqual(session.title, "Push")
        XCTAssertEqual(session.sortedLoggedExercises[0].sortedSets[0].weight, 185)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testSignedInEditOfOwnerlessCompletedWorkoutStampsOwnerForSetSyncReplay() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            userSettingsCursor: 1,
            exercisesCursor: 1,
            workoutSessionsCursor: 1,
            loggedExercisesCursor: 1,
            loggedSetsCursor: 1,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        let session = makeCompletedWorkout(context: context)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: session)
        let editedSetID = try XCTUnwrap(draft.exercises[0].sets[0].id)
        draft.exercises[0].sets[0].weight = 225
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(session.syncOwnerTokenIdentifier, owner)
        XCTAssertEqual(client.operationLog.prefix(2), [
            "upsertWorkoutSession:\(session.id.uuidString.lowercased())",
            "upsertLoggedExercise:\(try XCTUnwrap(session.sortedLoggedExercises.first?.id.uuidString.lowercased()))",
        ])
        let editedPayload = try XCTUnwrap(client.upsertedLoggedSets.first {
            $0.clientId == editedSetID.uuidString.lowercased()
        })
        XCTAssertEqual(editedPayload.weight, 225)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
    }

    func testSettingsUpdateSyncBootstrapsLargeOwnedWorkoutGraphWithoutFailure() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(weightUnit: .pounds, syncOwnerTokenIdentifier: owner)
        context.insert(settings)

        for index in 0..<100 {
            let session = WorkoutSession(
                title: "Workout \(index)",
                startedAt: Date(timeIntervalSince1970: Double(index)),
                endedAt: Date(timeIntervalSince1970: Double(index + 1000)),
                durationSeconds: 100,
                status: .completed,
                source: .blank,
                syncOwnerTokenIdentifier: owner
            )
            let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
            let set = LoggedSet(orderIndex: 0, weight: Double(100 + index), reps: 5, isCompleted: true)
            loggedExercise.session = session
            set.loggedExercise = loggedExercise
            loggedExercise.sets.append(set)
            session.loggedExercises.append(loggedExercise)
            context.insert(session)
        }
        try context.save()

        let client = FakeSyncClient()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = owner

        try SettingsMutationService(syncScheduler: scheduler).updateWeightUnit(
            .kilograms,
            settings: settings,
            context: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(scheduler.requestCount, 1)

        try await waitUntil(timeout: 5.0) {
            scheduler.lastSyncedAt != nil || scheduler.lastFailure != nil
        }

        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNotNil(scheduler.lastSyncedAt)
        XCTAssertTrue(try fetchEntries(context).isEmpty)
        XCTAssertEqual(client.upsertedLoggedSets.count, 100)
        XCTAssertEqual(client.upsertedSettings.count, 1)
    }

    func testCoordinatorPushesLargePendingOutboxInBoundedPages() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            userSettingsCursor: 1,
            exercisesCursor: 1,
            workoutSessionsCursor: 1,
            loggedExercisesCursor: 1,
            loggedSetsCursor: 1,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))

        let recorder = SyncOutboxRecorder()
        for index in 0..<120 {
            let session = WorkoutSession(
                title: "Workout \(index)",
                startedAt: Date(timeIntervalSince1970: Double(index)),
                endedAt: Date(timeIntervalSince1970: Double(index + 1000)),
                durationSeconds: 100,
                status: .completed,
                source: .blank,
                syncOwnerTokenIdentifier: owner
            )
            let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
            let set = LoggedSet(orderIndex: 0, weight: Double(100 + index), reps: 5, isCompleted: true)
            loggedExercise.session = session
            set.loggedExercise = loggedExercise
            loggedExercise.sets.append(set)
            session.loggedExercises.append(loggedExercise)
            context.insert(session)
            try recorder.recordUpdate(
                entityKind: .loggedSet,
                entityID: set.id,
                ownerTokenIdentifier: owner,
                context: context,
                now: Date(timeIntervalSince1970: Double(2_000 + index))
            )
        }
        try context.save()

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.upsertedLoggedSets.count, 50)
        XCTAssertEqual(try fetchEntries(context).count, 70)
    }

    func testCoordinatorSortsAllPendingDeletesByDependencyBeforeBatchLimit() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            userSettingsCursor: 1,
            exercisesCursor: 1,
            workoutSessionsCursor: 1,
            loggedExercisesCursor: 1,
            loggedSetsCursor: 1,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))

        context.insert(SyncOutboxEntry(
            entityKind: .workoutSession,
            entityID: UUID(),
            operation: .delete,
            ownerTokenIdentifier: owner,
            now: Date(timeIntervalSince1970: 100)
        ))
        context.insert(SyncOutboxEntry(
            entityKind: .loggedExercise,
            entityID: UUID(),
            operation: .delete,
            ownerTokenIdentifier: owner,
            now: Date(timeIntervalSince1970: 101)
        ))
        for index in 0..<60 {
            context.insert(SyncOutboxEntry(
                entityKind: .loggedSet,
                entityID: UUID(),
                operation: .delete,
                ownerTokenIdentifier: owner,
                now: Date(timeIntervalSince1970: Double(200 + index))
            ))
        }
        try context.save()

        let client = FakeSyncClient()
        let result = try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(result.hasMorePendingEntries)
        XCTAssertEqual(client.tombstones.count, 50)
        XCTAssertTrue(client.tombstones.allSatisfy { kind, _, _ in kind == .loggedSet })
        XCTAssertEqual(try fetchEntries(context).count, 12)
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

    private func makeCompletedWorkout(
        context: ModelContext,
        title: String = "Push",
        startedAt: Date = Date(timeIntervalSince1970: 0),
        durationSeconds: Int = 3_600,
        updatedAt: Date = Date(timeIntervalSince1970: 100),
        ownerTokenIdentifier: String? = nil
    ) -> WorkoutSession {
        let firstSet = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            rpe: 8,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 50),
            notes: "Original first",
            updatedAt: updatedAt
        )
        let secondSet = LoggedSet(
            orderIndex: 1,
            weight: 205,
            reps: 3,
            rpe: 9,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 60),
            notes: "Original second",
            updatedAt: updatedAt
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            updatedAt: updatedAt,
            sets: [firstSet, secondSet]
        )
        let session = WorkoutSession(
            title: title,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(durationSeconds)),
            durationSeconds: durationSeconds,
            notes: "Original notes",
            status: .completed,
            source: .blank,
            updatedAt: updatedAt,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            loggedExercises: [loggedExercise]
        )
        context.insert(session)
        return session
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition was not met before timeout")
    }
}
