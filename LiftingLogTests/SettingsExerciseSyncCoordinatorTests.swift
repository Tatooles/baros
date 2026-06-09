import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class SettingsExerciseSyncCoordinatorTests: XCTestCase {
    func testFirstRunClaimsUnownedSettingsExercisesAndOutboxEntries() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(id: UUID(uuidString: "00000000-0000-0000-0000-000000002001")!)
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002002")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(settings)
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .userSettings,
            entityID: settings.id,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(settings.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entries.first?.ownerTokenIdentifier, "issuer|owner_a")
    }

    func testBootstrappedPrepareDoesNotClaimOwnerlessSeedDefaultsWithoutLocalIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let state = SyncCursorState(
            ownerTokenIdentifier: "issuer|owner_a",
            hasBootstrappedSettingsExercises: true
        )
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002005")!,
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true
        )
        context.insert(state)
        context.insert(exercise)
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertNil(exercise.syncOwnerTokenIdentifier)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testBootstrappedPrepareClaimsOwnerlessRowsWithLocalIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let state = SyncCursorState(
            ownerTokenIdentifier: "issuer|owner_a",
            hasBootstrappedSettingsExercises: true
        )
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002006")!,
            seedIdentifier: "bench-press",
            name: "Local Renamed Bench",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true
        )
        context.insert(state)
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entry.ownerTokenIdentifier, "issuer|owner_a")
    }

    func testPrepareSkipsRowsOwnedByDifferentOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(exercise)
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_b", context: context)

        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
    }

    func testPrepareReturnsRelevantInFlightEntriesToPending() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let entry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000002003")!,
            operation: .update,
            status: .inFlight,
            ownerTokenIdentifier: "issuer|owner_a",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(entry)
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(entry.status, .pending)
    }

    func testPrepareDoesNotClaimNilOwnerOutboxEntryForRecordOwnedByDifferentOwner() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002004")!,
            name: "Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(exercise)
        let entry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: exercise.id,
            operation: .update,
            ownerTokenIdentifier: nil,
            now: Date(timeIntervalSince1970: 100)
        )
        context.insert(entry)
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_b", context: context)

        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertNil(entry.ownerTokenIdentifier)
    }

    func testRunPushesSettingsAndExerciseEntriesThenRemovesOutbox() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(id: UUID(uuidString: "00000000-0000-0000-0000-000000003001")!)
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003002")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(settings)
        context.insert(exercise)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .userSettings, entityID: settings.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try recorder.recordCreate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedSettings.count, 1)
        XCTAssertEqual(client.upsertedSettings.first?.clientId, settings.id.uuidString.lowercased())
        XCTAssertEqual(client.upsertedExercises.count, 1)
        XCTAssertEqual(client.upsertedExercises.first?.clientId, exercise.id.uuidString.lowercased())
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstRunBootstrapsExistingSettingsAndExercisesOnce() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(id: UUID(uuidString: "00000000-0000-0000-0000-000000003101")!)
        let bench = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003102")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        let squat = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003103")!,
            name: "Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        context.insert(settings)
        context.insert(bench)
        context.insert(squat)
        try context.save()

        let firstClient = FakeSettingsExerciseSyncClient()
        try await SettingsExerciseSyncCoordinator(client: firstClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertTrue(state.hasBootstrappedSettingsExercises)
        XCTAssertEqual(firstClient.upsertedSettings.map(\.clientId), [settings.id.uuidString.lowercased()])
        XCTAssertEqual(
            Set(firstClient.upsertedExercises.map(\.clientId)),
            Set([bench.id.uuidString.lowercased(), squat.id.uuidString.lowercased()])
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)

        let secondClient = FakeSettingsExerciseSyncClient()
        try await SettingsExerciseSyncCoordinator(client: secondClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertTrue(secondClient.upsertedSettings.isEmpty)
        XCTAssertTrue(secondClient.upsertedExercises.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstRunPullsRemoteDefaultsBeforeBootstrappingLocalDefaults() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let localSettingsID = UUID(uuidString: "00000000-0000-0000-0000-000000003201")!
        let remoteSettingsID = UUID(uuidString: "00000000-0000-0000-0000-000000003202")!
        let localBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003203")!
        let remoteBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003204")!
        let localSquatID = UUID(uuidString: "00000000-0000-0000-0000-000000003205")!
        let remoteSquatID = UUID(uuidString: "00000000-0000-0000-0000-000000003206")!

        let settings = UserSettings(id: localSettingsID)
        let bench = Exercise(
            id: localBenchID,
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true
        )
        let squat = Exercise(
            id: localSquatID,
            seedIdentifier: "back-squat",
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads",
            isSeeded: true
        )
        context.insert(settings)
        context.insert(bench)
        context.insert(squat)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [
                    UserSettingsSyncRecord(
                        clientId: remoteSettingsID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        weightUnitRaw: "kilograms",
                        defaultRestTimerSeconds: 120,
                        hasCompletedOnboarding: true
                    )
                ],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: remoteBenchID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 31,
                        seedIdentifier: "bench-press",
                        name: "Remote Bench",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: true
                    ),
                    ExerciseSyncRecord(
                        clientId: remoteSquatID.uuidString.lowercased(),
                        createdAt: 11,
                        updatedAt: 21,
                        deletedAt: nil,
                        serverUpdatedAt: 32,
                        seedIdentifier: "back-squat",
                        name: "Remote Squat",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Quads",
                        primaryMuscleGroupRaw: "quads",
                        notes: "",
                        isArchived: false,
                        isSeeded: true
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 32),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let syncedSettings = try context.fetch(FetchDescriptor<UserSettings>())
        let syncedExercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertTrue(client.upsertedSettings.isEmpty)
        XCTAssertTrue(client.upsertedExercises.isEmpty)
        XCTAssertEqual(syncedSettings.map(\.id), [remoteSettingsID])
        XCTAssertEqual(syncedSettings.first?.weightUnitRaw, "kilograms")
        XCTAssertEqual(Set(syncedExercises.map(\.id)), Set([remoteBenchID, remoteSquatID]))
        XCTAssertEqual(Set(syncedExercises.map(\.name)), Set(["Remote Bench", "Remote Squat"]))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstRunAdoptsOwnerScopedDefaultsBeforeBootstrapping() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|owner_b"
        let localSettingsID = UUID(uuidString: "00000000-0000-0000-0000-000000003221")!
        let remoteSettingsID = UUID(uuidString: "00000000-0000-0000-0000-000000003222")!
        let localBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003223")!
        let remoteBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003224")!

        let settings = UserSettings(id: localSettingsID, syncOwnerTokenIdentifier: ownerTokenIdentifier)
        let bench = Exercise(
            id: localBenchID,
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(settings)
        context.insert(bench)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [
                    UserSettingsSyncRecord(
                        clientId: remoteSettingsID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        weightUnitRaw: "kilograms",
                        defaultRestTimerSeconds: 120,
                        hasCompletedOnboarding: true
                    )
                ],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: remoteBenchID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 31,
                        seedIdentifier: "bench-press",
                        name: "Remote Bench",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: true
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 31),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: ownerTokenIdentifier, context: context)

        let syncedSettings = try context.fetch(FetchDescriptor<UserSettings>())
        let syncedExercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertTrue(client.upsertedSettings.isEmpty)
        XCTAssertTrue(client.upsertedExercises.isEmpty)
        XCTAssertEqual(syncedSettings.map(\.id), [remoteSettingsID])
        XCTAssertEqual(syncedSettings.first?.weightUnitRaw, "kilograms")
        XCTAssertEqual(syncedExercises.map(\.id), [remoteBenchID])
        XCTAssertEqual(syncedExercises.first?.name, "Remote Bench")
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstRunAdoptsRemoteSeedTombstoneBeforeBootstrappingLocalSeed() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let localBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003207")!
        let remoteBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003208")!

        let bench = Exercise(
            id: localBenchID,
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true
        )
        context.insert(bench)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: remoteBenchID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: 25,
                        serverUpdatedAt: 31,
                        seedIdentifier: "bench-press",
                        name: "Bench Press",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: true
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 31),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let syncedExercises = try context.fetch(FetchDescriptor<Exercise>())
        let syncedExercise = try XCTUnwrap(syncedExercises.first)
        XCTAssertEqual(syncedExercises.count, 1)
        XCTAssertEqual(syncedExercise.id, remoteBenchID)
        XCTAssertEqual(syncedExercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(syncedExercise.deletedAt, Date(timeIntervalSince1970: 25))
        XCTAssertTrue(client.upsertedExercises.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstRunRetargetsDeletedLocalSeedToPulledRemoteSeed() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let localBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003209")!
        let remoteBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003210")!
        let deletedAt = Date(timeIntervalSince1970: 200)

        let bench = Exercise(
            id: localBenchID,
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )
        context.insert(bench)
        try SyncOutboxRecorder().recordDelete(
            entityKind: .exercise,
            entityID: localBenchID,
            ownerTokenIdentifier: nil,
            context: context,
            now: deletedAt
        )
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: remoteBenchID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 31,
                        seedIdentifier: "bench-press",
                        name: "Remote Bench",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: true
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 31),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let syncedExercises = try context.fetch(FetchDescriptor<Exercise>())
        let syncedExercise = try XCTUnwrap(syncedExercises.first)
        XCTAssertEqual(syncedExercises.count, 1)
        XCTAssertEqual(syncedExercise.id, remoteBenchID)
        XCTAssertEqual(syncedExercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(syncedExercise.deletedAt, deletedAt)
        XCTAssertTrue(client.upsertedExercises.isEmpty)
        XCTAssertEqual(client.tombstones.count, 1)
        XCTAssertEqual(client.tombstones.first?.0, .exercise)
        XCTAssertEqual(client.tombstones.first?.1, remoteBenchID)
        XCTAssertEqual(client.tombstones.first?.2, deletedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstRunRetargetsSignedOutEditsToPulledRemoteDefaults() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let localSettingsID = UUID(uuidString: "00000000-0000-0000-0000-000000003211")!
        let remoteSettingsID = UUID(uuidString: "00000000-0000-0000-0000-000000003212")!
        let localBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003213")!
        let remoteBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000003214")!

        let settings = UserSettings(
            id: localSettingsID,
            weightUnit: .pounds,
            defaultRestTimerSeconds: 180,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let bench = Exercise(
            id: localBenchID,
            seedIdentifier: "bench-press",
            name: "Local Renamed Bench",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true,
            updatedAt: Date(timeIntervalSince1970: 210)
        )
        context.insert(settings)
        context.insert(bench)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(
            entityKind: .userSettings,
            entityID: settings.id,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try recorder.recordUpdate(
            entityKind: .exercise,
            entityID: bench.id,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 210)
        )
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [
                    UserSettingsSyncRecord(
                        clientId: remoteSettingsID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        weightUnitRaw: "kilograms",
                        defaultRestTimerSeconds: 120,
                        hasCompletedOnboarding: true
                    )
                ],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: remoteBenchID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 31,
                        seedIdentifier: "bench-press",
                        name: "Remote Bench",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: true
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 31),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let syncedSettings = try context.fetch(FetchDescriptor<UserSettings>())
        let syncedExercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(syncedSettings.map(\.id), [remoteSettingsID])
        XCTAssertEqual(syncedSettings.first?.weightUnitRaw, "pounds")
        XCTAssertEqual(syncedSettings.first?.defaultRestTimerSeconds, 180)
        XCTAssertEqual(syncedExercises.map(\.id), [remoteBenchID])
        XCTAssertEqual(syncedExercises.first?.name, "Local Renamed Bench")
        XCTAssertEqual(client.upsertedSettings.map(\.clientId), [remoteSettingsID.uuidString.lowercased()])
        XCTAssertEqual(client.upsertedSettings.first?.defaultRestTimerSeconds, 180)
        XCTAssertEqual(client.upsertedExercises.map(\.clientId), [remoteBenchID.uuidString.lowercased()])
        XCTAssertEqual(client.upsertedExercises.first?.name, "Local Renamed Bench")
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testIgnoredStaleSettingsPushRefetchesRemoteAfterAdoption() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let localSettingsID = UUID(uuidString: "00000000-0000-0000-0000-000000003215")!
        let remoteSettingsID = UUID(uuidString: "00000000-0000-0000-0000-000000003216")!

        let settings = UserSettings(
            id: localSettingsID,
            weightUnit: .pounds,
            defaultRestTimerSeconds: 90,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        context.insert(settings)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .userSettings,
            entityID: settings.id,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 10)
        )
        try context.save()

        let remoteRecord = UserSettingsSyncRecord(
            clientId: remoteSettingsID.uuidString.lowercased(),
            createdAt: 5,
            updatedAt: 20,
            deletedAt: nil,
            serverUpdatedAt: 30,
            weightUnitRaw: "kilograms",
            defaultRestTimerSeconds: 120,
            hasCompletedOnboarding: true
        )
        let client = FakeSettingsExerciseSyncClient()
        client.userSettingsMutationResults = [
            SyncMutationResult(status: "ignored_stale", serverUpdatedAt: 30)
        ]
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [remoteRecord],
                exercises: [],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
            SyncFetchChangesResponse(
                userSettings: [remoteRecord],
                exercises: [],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let syncedSettings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(syncedSettings.id, remoteSettingsID)
        XCTAssertEqual(syncedSettings.weightUnitRaw, "kilograms")
        XCTAssertEqual(syncedSettings.defaultRestTimerSeconds, 120)
        XCTAssertEqual(syncedSettings.updatedAt, Date(timeIntervalSince1970: 20))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
        XCTAssertEqual(client.upsertedSettings.map(\.clientId), [remoteSettingsID.uuidString.lowercased()])
        XCTAssertEqual(client.fetchRequests.count, 2)
        XCTAssertEqual(client.fetchRequests.first?.cursors.userSettings, 0)
        XCTAssertLessThan(try XCTUnwrap(client.fetchRequests.last?.cursors.userSettings), 30)
    }

    func testFirstRunDoesNotBootstrapRowsOwnedByDifferentOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003104")!,
            name: "Other Owner Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads",
            syncOwnerTokenIdentifier: "issuer|owner_b"
        )
        context.insert(exercise)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertTrue(client.upsertedExercises.isEmpty)
        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_b")
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunMarksFailedEntryAndStopsOnPushError() async throws {
        struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003003")!,
            name: "Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.error = PushError()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.lastErrorMessage, "offline")
    }

    func testRunRetriesPreviouslyFailedEntryOnNextRun() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003004")!,
            name: "Deadlift",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Hamstrings"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(exercise)
        let entry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: exercise.id,
            operation: .update,
            status: .failed,
            ownerTokenIdentifier: "issuer|owner_a",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        entry.lastErrorMessage = "offline"
        context.insert(entry)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedExercises.map { $0.clientId }, [exercise.id.uuidString.lowercased()])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunDoesNotPushModelOwnedByDifferentOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003005")!,
            name: "Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Shoulders"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_b"
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedExercises.count, 0)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.lastErrorMessage, "Cannot sync exercise \(exercise.id.uuidString) because the local record belongs to a different owner.")
    }

    func testRunTombstonesMissingExerciseForUpdateEntry() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000003006")!
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.tombstones.count, 1)
        XCTAssertEqual(client.tombstones.first?.0, .exercise)
        XCTAssertEqual(client.tombstones.first?.1, exerciseID)
        XCTAssertEqual(client.tombstones.first?.2, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunRetriesMissingExerciseTombstoneWithOriginalTimestamp() async throws {
        struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000003010")!
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let firstClient = FakeSettingsExerciseSyncClient()
        firstClient.error = PushError()
        let coordinator = SettingsExerciseSyncCoordinator(client: firstClient)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let failedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(failedEntry.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertNotEqual(failedEntry.updatedAt, Date(timeIntervalSince1970: 100))

        let retryClient = FakeSettingsExerciseSyncClient()
        try await SettingsExerciseSyncCoordinator(client: retryClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(retryClient.tombstones.count, 1)
        XCTAssertEqual(retryClient.tombstones.first?.0, .exercise)
        XCTAssertEqual(retryClient.tombstones.first?.1, exerciseID)
        XCTAssertEqual(retryClient.tombstones.first?.2, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunUsesDeleteIntentTimestampForAttemptedMissingExerciseTombstone() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000003011")!
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        recorder.markInFlight(entry, now: Date(timeIntervalSince1970: 150))
        try recorder.recordDelete(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 200))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.tombstones.count, 1)
        XCTAssertEqual(client.tombstones.first?.0, .exercise)
        XCTAssertEqual(client.tombstones.first?.1, exerciseID)
        XCTAssertEqual(client.tombstones.first?.2, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunRetriesMissingDeleteTombstoneWithDeleteIntentTimestamp() async throws {
        struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000003012")!
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        recorder.markInFlight(entry, now: Date(timeIntervalSince1970: 150))
        try recorder.recordDelete(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 200))
        try context.save()

        let firstClient = FakeSettingsExerciseSyncClient()
        firstClient.error = PushError()
        try await SettingsExerciseSyncCoordinator(client: firstClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let failedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(failedEntry.createdAt, Date(timeIntervalSince1970: 200))
        XCTAssertNotEqual(failedEntry.updatedAt, Date(timeIntervalSince1970: 200))

        let retryClient = FakeSettingsExerciseSyncClient()
        try await SettingsExerciseSyncCoordinator(client: retryClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(retryClient.tombstones.count, 1)
        XCTAssertEqual(retryClient.tombstones.first?.0, .exercise)
        XCTAssertEqual(retryClient.tombstones.first?.1, exerciseID)
        XCTAssertEqual(retryClient.tombstones.first?.2, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunPullsRemoteExerciseAndAdvancesCursor() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: "00000000-0000-0000-0000-000000004001",
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        seedIdentifier: nil,
                        name: "Remote Bench",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: false
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let cursor = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises.first?.name, "Remote Bench")
        XCTAssertEqual(exercises.first?.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(cursor.exercisesCursor, 30)
    }

    func testRunKeepsLocalNewerExerciseWhenRemoteIsOlder() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004002")!,
            name: "Local Name",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: "issuer|owner_a",
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        context.insert(exercise)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: exercise.id.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        seedIdentifier: nil,
                        name: "Remote Older Name",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: false
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(exercise.name, "Local Name")
    }

    func testRunKeepsLocalExerciseTombstoneWhenRemoteIsActive() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004005")!,
            name: "Deleted Local",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: "issuer|owner_a",
            updatedAt: Date(timeIntervalSince1970: 20),
            deletedAt: Date(timeIntervalSince1970: 20)
        )
        context.insert(exercise)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: exercise.id.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 40,
                        deletedAt: nil,
                        serverUpdatedAt: 45,
                        seedIdentifier: nil,
                        name: "Restored Remote",
                        categoryRaw: "future-strength",
                        equipmentRaw: "future-bar",
                        primaryMuscleRaw: "Future Chest",
                        primaryMuscleGroupRaw: "future-chest",
                        notes: "Restored",
                        isArchived: false,
                        isSeeded: false
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 45),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(exercise.name, "Deleted Local")
        XCTAssertEqual(exercise.categoryRaw, "strength")
        XCTAssertEqual(exercise.equipmentRaw, "barbell")
        XCTAssertEqual(exercise.primaryMuscleRaw, "Chest")
        XCTAssertNotNil(exercise.deletedAt)
    }

    func testRunKeepsLocalSettingsTombstoneWhenRemoteIsActive() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004006")!,
            weightUnit: .pounds,
            defaultRestTimerSeconds: 90,
            hasCompletedOnboarding: false,
            syncOwnerTokenIdentifier: "issuer|owner_a",
            updatedAt: Date(timeIntervalSince1970: 20),
            deletedAt: Date(timeIntervalSince1970: 20)
        )
        context.insert(settings)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [
                    UserSettingsSyncRecord(
                        clientId: settings.id.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 40,
                        deletedAt: nil,
                        serverUpdatedAt: 45,
                        weightUnitRaw: "kilograms",
                        defaultRestTimerSeconds: 120,
                        hasCompletedOnboarding: true
                    )
                ],
                exercises: [],
                cursors: SyncChangeCursors(userSettings: 45, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(settings.weightUnitRaw, "pounds")
        XCTAssertEqual(settings.defaultRestTimerSeconds, 90)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertNotNil(settings.deletedAt)
    }

    func testRunAppliesRemoteSettingsWithoutOutboxCascade() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004003")!,
            weightUnit: .pounds,
            syncOwnerTokenIdentifier: "issuer|owner_a",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        context.insert(settings)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [
                    UserSettingsSyncRecord(
                        clientId: settings.id.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 25,
                        weightUnitRaw: "kilograms",
                        defaultRestTimerSeconds: 150,
                        hasCompletedOnboarding: true
                    )
                ],
                exercises: [],
                cursors: SyncChangeCursors(userSettings: 25, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(settings.weightUnit, .kilograms)
        XCTAssertEqual(settings.defaultRestTimerSeconds, 150)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunPullsUntilNoMoreAndUsesAdvancedCursors() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                cursors: SyncChangeCursors(userSettings: 10, exercises: 20),
                hasMore: SyncHasMore(userSettings: false, exercises: true)
            ),
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                cursors: SyncChangeCursors(userSettings: 10, exercises: 40),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let cursor = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertEqual(client.fetchRequests.map(\.cursors.exercises), [0, 20])
        XCTAssertEqual(cursor.userSettingsCursor, 10)
        XCTAssertEqual(cursor.exercisesCursor, 40)
    }

    func testRunDoesNotApplyRemoteExerciseToDifferentOwnerLocalRow() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004004")!,
            name: "Other Owner Name",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: "issuer|owner_b",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        context.insert(exercise)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: exercise.id.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        seedIdentifier: nil,
                        name: "Remote Owner A Name",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: false
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SettingsExerciseSyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(exercise.name, "Other Owner Name")
        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_b")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 1)
    }

    func testRunDoesNotTombstoneModelOwnedByDifferentOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003009")!,
            name: "Other Owner Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_b"
        exercise.markDeleted(now: Date(timeIntervalSince1970: 120))
        context.insert(exercise)
        try SyncOutboxRecorder().recordDelete(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 130))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertTrue(client.tombstones.isEmpty)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.lastErrorMessage, "Cannot sync exercise \(exercise.id.uuidString) because the local record belongs to a different owner.")
    }

    func testRunLeavesSecondPendingEntryPendingAfterFirstEntryFailure() async throws {
        struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let failedExercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003007")!,
            name: "Curl",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscle: "Biceps"
        )
        let pendingExercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003008")!,
            name: "Row",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscle: "Back"
        )
        context.insert(failedExercise)
        context.insert(pendingExercise)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .exercise, entityID: failedExercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try recorder.recordUpdate(entityKind: .exercise, entityID: pendingExercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 200))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.error = PushError()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        let failedEntry = try XCTUnwrap(entries.first { $0.entityID == failedExercise.id })
        let pendingEntry = try XCTUnwrap(entries.first { $0.entityID == pendingExercise.id })
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(pendingEntry.status, .pending)
    }
}

final class FakeSettingsExerciseSyncClient: SettingsExerciseSyncClient, @unchecked Sendable {
    var upsertedSettings: [UserSettingsSyncPayload] = []
    var upsertedExercises: [ExerciseSyncPayload] = []
    var tombstones: [(SyncEntityKind, UUID, Date)] = []
    var fetchRequests: [(cursors: SyncChangeCursors, limit: Int)] = []
    var userSettingsMutationResults: [SyncMutationResult] = []
    var exerciseMutationResults: [SyncMutationResult] = []
    var tombstoneResults: [SyncMutationResult] = []
    var fetchResponses: [SyncFetchChangesResponse] = []
    var fetchResponse = SyncFetchChangesResponse(
        userSettings: [],
        exercises: [],
        cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
        hasMore: SyncHasMore(userSettings: false, exercises: false)
    )
    var onFetchChanges: (() -> Void)?
    var error: Error?
    var fetchError: Error?

    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        upsertedSettings.append(record)
        if !userSettingsMutationResults.isEmpty {
            return userSettingsMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        upsertedExercises.append(record)
        if !exerciseMutationResults.isEmpty {
            return exerciseMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult {
        if let error { throw error }
        tombstones.append((entityKind, clientId, deletedAt))
        if !tombstoneResults.isEmpty {
            return tombstoneResults.removeFirst()
        }
        return SyncMutationResult(status: "tombstoned", serverUpdatedAt: 1)
    }

    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse {
        if let fetchError { throw fetchError }
        fetchRequests.append((cursors, limit))
        onFetchChanges?()
        if !fetchResponses.isEmpty {
            return fetchResponses.removeFirst()
        }
        return fetchResponse
    }
}
