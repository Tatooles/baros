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

    func testSettingsWeightUnitChangeRecordsOnlySettingsUpdate() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let service = SettingsMutationService()
        let settings = UserSettings(weightUnit: .pounds)
        let completedUpdatedAt = Date(timeIntervalSince1970: 40)
        let placeholderUpdatedAt = Date(timeIntervalSince1970: 45)
        let completedSet = LoggedSet(
            orderIndex: 0,
            weight: 225,
            reps: 5,
            isCompleted: true,
            updatedAt: completedUpdatedAt
        )
        let placeholderSet = LoggedSet(
            orderIndex: 1,
            placeholderWeight: 135,
            placeholderReps: 8,
            updatedAt: placeholderUpdatedAt
        )
        context.insert(settings)
        context.insert(completedSet)
        context.insert(placeholderSet)
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
        XCTAssertEqual(placeholderSet.placeholderWeight, 135)
        XCTAssertEqual(placeholderSet.updatedAt, placeholderUpdatedAt)

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

    func testLargeWeightUnitConversionSyncDrainsWithoutFailure() async throws {
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
