import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class SyncCoordinatorTests: XCTestCase {
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

        let coordinator = SyncCoordinator(client: FakeSyncClient())
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

        let coordinator = SyncCoordinator(client: FakeSyncClient())
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

        let coordinator = SyncCoordinator(client: FakeSyncClient())
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

        let coordinator = SyncCoordinator(client: FakeSyncClient())
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

        let coordinator = SyncCoordinator(client: FakeSyncClient())
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

        let coordinator = SyncCoordinator(client: FakeSyncClient())
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

        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedSettings.count, 1)
        XCTAssertEqual(client.upsertedSettings.first?.clientId, settings.id.uuidString.lowercased())
        XCTAssertEqual(client.upsertedExercises.count, 1)
        XCTAssertEqual(client.upsertedExercises.first?.clientId, exercise.id.uuidString.lowercased())
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunPushesCompletedWorkoutGraphInParentFirstOrder() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005001")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005002")!,
            title: "Push",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005003")!,
            orderIndex: 0,
            exercise: exercise,
            createdAt: Date(timeIntervalSince1970: 110),
            updatedAt: Date(timeIntervalSince1970: 210)
        )
        let set = LoggedSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005004")!,
            orderIndex: 0,
            weight: 185,
            reps: 5,
            kind: .working,
            isCompleted: true,
            createdAt: Date(timeIntervalSince1970: 120),
            updatedAt: Date(timeIntervalSince1970: 220)
        )
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        context.insert(exercise)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(set)
        let recorder = SyncOutboxRecorder()
        try recorder.recordCreate(entityKind: .loggedSet, entityID: set.id, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 300))
        try recorder.recordCreate(entityKind: .loggedExercise, entityID: loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 301))
        try recorder.recordCreate(entityKind: .workoutSession, entityID: session.id, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 302))
        try context.save()

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.operationLog, [
            "upsertWorkoutSession:\(session.id.uuidString.lowercased())",
            "upsertLoggedExercise:\(loggedExercise.id.uuidString.lowercased())",
            "upsertLoggedSet:\(set.id.uuidString.lowercased())",
        ])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunTombstonesDeletedWorkoutGraphEntriesInDependencyOrderWithLocalDeletionTimestamp() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let deletedAt = Date(timeIntervalSince1970: 300)
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005401")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005402")!,
            title: "Deleted Push",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            syncOwnerTokenIdentifier: owner
        )
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005403")!,
            orderIndex: 0,
            exercise: exercise,
            createdAt: Date(timeIntervalSince1970: 110),
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )
        let set = LoggedSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005404")!,
            orderIndex: 0,
            weight: 185,
            reps: 5,
            kind: .working,
            isCompleted: true,
            createdAt: Date(timeIntervalSince1970: 120),
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        context.insert(exercise)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(set)
        let recorder = SyncOutboxRecorder()
        try recorder.recordDelete(entityKind: .loggedSet, entityID: set.id, ownerTokenIdentifier: owner, context: context, now: deletedAt)
        try recorder.recordDelete(entityKind: .loggedExercise, entityID: loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: deletedAt)
        try recorder.recordDelete(entityKind: .workoutSession, entityID: session.id, ownerTokenIdentifier: owner, context: context, now: deletedAt)
        try context.save()

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.tombstones.map(\.0), [.loggedSet, .loggedExercise, .workoutSession])
        XCTAssertEqual(client.tombstones.map(\.1), [set.id, loggedExercise.id, session.id])
        XCTAssertEqual(client.tombstones.map(\.2), [deletedAt, deletedAt, deletedAt])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstWorkoutGraphRunBootstrapsLocalCompletedWorkoutWhenRemoteGraphIsEmpty() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007001")!,
            title: "Local Push",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank
        )
        context.insert(session)
        try context.save()

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.upsertedWorkoutSessions.map(\.clientId), [session.id.uuidString.lowercased()])
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertTrue(state.hasBootstrappedWorkoutGraph)
    }

    func testFirstWorkoutGraphRunDoesNotBulkUploadOwnerlessLocalWorkoutWhenRemoteGraphExists() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let localSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007101")!,
            title: "Local Push",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank
        )
        let remoteSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000007102")!
        context.insert(localSession)
        try context.save()

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: remoteSessionID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        title: "Remote Push",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    ),
                ],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(client.upsertedWorkoutSessions.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).count, 0)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == remoteSessionID })
    }

    func testFirstWorkoutGraphRunClaimsOwnerlessWorkoutOutboxWhenRemoteGraphExists() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let localSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007111")!,
            title: "Signed Out Local",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007112")!,
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press"
        )
        let set = LoggedSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007113")!,
            orderIndex: 0,
            weight: 185,
            reps: 5,
            isCompleted: true
        )
        loggedExercise.session = localSession
        set.loggedExercise = loggedExercise
        localSession.loggedExercises.append(loggedExercise)
        loggedExercise.sets.append(set)
        context.insert(localSession)
        context.insert(loggedExercise)
        context.insert(set)
        let recorder = SyncOutboxRecorder()
        try recorder.recordCreate(entityKind: .workoutSession, entityID: localSession.id, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 201))
        try recorder.recordCreate(entityKind: .loggedExercise, entityID: loggedExercise.id, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 202))
        try recorder.recordCreate(entityKind: .loggedSet, entityID: set.id, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 203))
        try context.save()

        let remoteSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000007114")!
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: remoteSessionID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        title: "Remote Push",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    ),
                ],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.operationLog, [
            "upsertWorkoutSession:\(localSession.id.uuidString.lowercased())",
            "upsertLoggedExercise:\(loggedExercise.id.uuidString.lowercased())",
            "upsertLoggedSet:\(set.id.uuidString.lowercased())",
        ])
        XCTAssertEqual(localSession.syncOwnerTokenIdentifier, owner)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstWorkoutGraphRunClaimsOwnerlessWorkoutOutboxWhenRemoteGraphIsEmpty() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007121")!,
            title: "Signed Out Local",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007122")!,
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press"
        )
        let set = LoggedSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007123")!,
            orderIndex: 0,
            weight: 185,
            reps: 5,
            isCompleted: true
        )
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        session.loggedExercises.append(loggedExercise)
        loggedExercise.sets.append(set)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(set)
        let recorder = SyncOutboxRecorder()
        try recorder.recordCreate(entityKind: .workoutSession, entityID: session.id, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 201))
        try recorder.recordCreate(entityKind: .loggedExercise, entityID: loggedExercise.id, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 202))
        try recorder.recordCreate(entityKind: .loggedSet, entityID: set.id, ownerTokenIdentifier: nil, context: context, now: Date(timeIntervalSince1970: 203))
        try context.save()

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.operationLog, [
            "upsertWorkoutSession:\(session.id.uuidString.lowercased())",
            "upsertLoggedExercise:\(loggedExercise.id.uuidString.lowercased())",
            "upsertLoggedSet:\(set.id.uuidString.lowercased())",
        ])
        XCTAssertEqual(session.syncOwnerTokenIdentifier, owner)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testFirstWorkoutGraphRunDoesNotBulkUploadOwnerlessLocalWorkoutForDifferentLocalOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let previousOwner = "issuer|owner_a"
        let currentOwner = "issuer|owner_b"
        let localSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007201")!,
            title: "Previous Owner Push",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank
        )
        context.insert(SyncCursorState(
            ownerTokenIdentifier: previousOwner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        context.insert(UserSettings(syncOwnerTokenIdentifier: previousOwner))
        context.insert(localSession)
        try context.save()

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: currentOwner, context: context)

        XCTAssertTrue(client.upsertedWorkoutSessions.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).count, 0)
        let currentOwnerState = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>())
            .first { $0.ownerTokenIdentifier == currentOwner })
        XCTAssertFalse(currentOwnerState.hasBootstrappedWorkoutGraph)
    }

    func testRunSkipsActiveWorkoutSessionOutboxEntry() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005101")!,
            title: "Active",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank
        )
        context.insert(session)
        try SyncOutboxRecorder().recordCreate(
            entityKind: .workoutSession,
            entityID: session.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(client.upsertedWorkoutSessions.isEmpty)
        XCTAssertTrue(client.tombstones.isEmpty)
    }

    func testRunSkipsLoggedExerciseWithoutSessionParent() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005201")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005202")!,
            orderIndex: 0,
            exercise: exercise
        )
        context.insert(exercise)
        context.insert(loggedExercise)
        try SyncOutboxRecorder().recordCreate(
            entityKind: .loggedExercise,
            entityID: loggedExercise.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(client.upsertedLoggedExercises.isEmpty)
        XCTAssertFalse(client.operationLog.contains { $0.hasPrefix("upsertLoggedExercise:") })
    }

    func testRunSkipsLoggedSetWithoutWorkoutSessionParent() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005301")!,
            orderIndex: 0
        )
        let set = LoggedSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005302")!,
            orderIndex: 0,
            weight: 185,
            reps: 5,
            kind: .working,
            isCompleted: true
        )
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        context.insert(loggedExercise)
        context.insert(set)
        try SyncOutboxRecorder().recordCreate(
            entityKind: .loggedSet,
            entityID: set.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(client.upsertedLoggedSets.isEmpty)
        XCTAssertFalse(client.operationLog.contains { $0.hasPrefix("upsertLoggedSet:") })
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

        let firstClient = FakeSyncClient()
        try await SyncCoordinator(client: firstClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertTrue(state.hasBootstrappedSettingsExercises)
        XCTAssertEqual(firstClient.upsertedSettings.map(\.clientId), [settings.id.uuidString.lowercased()])
        XCTAssertEqual(
            Set(firstClient.upsertedExercises.map(\.clientId)),
            Set([bench.id.uuidString.lowercased(), squat.id.uuidString.lowercased()])
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)

        let secondClient = FakeSyncClient()
        try await SyncCoordinator(client: secondClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 32),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

    func testRunPullsFullWorkoutGraphIntoEmptyStore() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006001")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000006002")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006003")!
        let setID = UUID(uuidString: "00000000-0000-0000-0000-000000006004")!
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: exerciseID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        seedIdentifier: nil,
                        name: "Bench Press",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: false
                    )
                ],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: sessionID.uuidString.lowercased(),
                        createdAt: 11,
                        updatedAt: 21,
                        deletedAt: nil,
                        serverUpdatedAt: 31,
                        title: "Push",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "Good",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    )
                ],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: loggedExerciseID.uuidString.lowercased(),
                        createdAt: 12,
                        updatedAt: 22,
                        deletedAt: nil,
                        serverUpdatedAt: 32,
                        sessionClientId: sessionID.uuidString.lowercased(),
                        exerciseClientId: exerciseID.uuidString.lowercased(),
                        orderIndex: 0,
                        exerciseSnapshotName: "Bench Press",
                        exerciseSnapshotEquipmentRaw: "barbell",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
                        hasSnapshotMetadata: true,
                        notes: "Paused",
                        referenceNotes: nil
                    )
                ],
                loggedSets: [
                    LoggedSetSyncRecord(
                        clientId: setID.uuidString.lowercased(),
                        createdAt: 13,
                        updatedAt: 23,
                        deletedAt: nil,
                        serverUpdatedAt: 33,
                        loggedExerciseClientId: loggedExerciseID.uuidString.lowercased(),
                        orderIndex: 0,
                        weight: 185,
                        reps: 5,
                        rpe: 8,
                        placeholderWeight: nil,
                        placeholderReps: nil,
                        placeholderRPE: nil,
                        kindRaw: "working",
                        isCompleted: true,
                        completedAt: 190,
                        notes: "",
                        healthLinkID: nil
                    )
                ],
                cursors: SyncChangeCursors(
                    userSettings: 0,
                    exercises: 30,
                    workoutSessions: 31,
                    loggedExercises: 32,
                    loggedSets: 33
                ),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let fetchRequest = try XCTUnwrap(client.fetchRequests.first)
        XCTAssertEqual(fetchRequest.cursors, SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 0, loggedSets: 0))
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let session = try XCTUnwrap(sessions.first { $0.id == sessionID })
        XCTAssertEqual(session.title, "Push")
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.syncOwnerTokenIdentifier, owner)
        XCTAssertEqual(session.sortedLoggedExercises.count, 1)
        let loggedExercise = try XCTUnwrap(session.sortedLoggedExercises.first)
        XCTAssertEqual(loggedExercise.id, loggedExerciseID)
        XCTAssertEqual(loggedExercise.exercise?.id, exerciseID)
        XCTAssertEqual(loggedExercise.sortedSets.map(\.id), [setID])
        XCTAssertEqual(loggedExercise.sortedSets.first?.weight, 185)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertEqual(state.exercisesCursor, 30)
        XCTAssertEqual(state.workoutSessionsCursor, 31)
        XCTAssertEqual(state.loggedExercisesCursor, 32)
        XCTAssertEqual(state.loggedSetsCursor, 33)
    }

    func testPullCascadesRemoteWorkoutSessionTombstoneToLocalChildren() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let deletedAt = Date(timeIntervalSince1970: 300)
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000006051")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006052")!
        let setID = UUID(uuidString: "00000000-0000-0000-0000-000000006053")!

        let state = SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        )
        let session = WorkoutSession(
            id: sessionID,
            title: "Remote Deleted",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            syncOwnerTokenIdentifier: owner
        )
        let loggedExercise = LoggedExercise(
            id: loggedExerciseID,
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            createdAt: Date(timeIntervalSince1970: 110),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let set = LoggedSet(
            id: setID,
            orderIndex: 0,
            weight: 185,
            reps: 5,
            kind: .working,
            isCompleted: true,
            createdAt: Date(timeIntervalSince1970: 120),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        session.loggedExercises.append(loggedExercise)
        loggedExercise.sets.append(set)
        context.insert(state)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(set)
        try context.save()

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: sessionID.uuidString.lowercased(),
                        createdAt: 100,
                        updatedAt: 300,
                        deletedAt: 300,
                        serverUpdatedAt: 400,
                        title: "Remote Deleted",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    )
                ],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 400),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(session.deletedAt, deletedAt)
        XCTAssertEqual(loggedExercise.deletedAt, deletedAt)
        XCTAssertEqual(set.deletedAt, deletedAt)
        XCTAssertTrue(session.sortedLoggedExercises.isEmpty)
        XCTAssertTrue(loggedExercise.sortedSets.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testPullDoesNotAdvanceLoggedSetCursorWhenParentLoggedExerciseIsMissing() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [
                    LoggedSetSyncRecord(
                        clientId: "00000000-0000-0000-0000-000000006104",
                        createdAt: 1,
                        updatedAt: 2,
                        deletedAt: nil,
                        serverUpdatedAt: 50,
                        loggedExerciseClientId: "00000000-0000-0000-0000-000000006103",
                        orderIndex: 0,
                        weight: 100,
                        reps: 5,
                        rpe: nil,
                        placeholderWeight: nil,
                        placeholderReps: nil,
                        placeholderRPE: nil,
                        kindRaw: "working",
                        isCompleted: true,
                        completedAt: nil,
                        notes: "",
                        healthLinkID: nil
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 0, loggedSets: 50),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertEqual(state.loggedSetsCursor, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LoggedSet>()).isEmpty)
    }

    func testPullDefersLoggedExerciseUntilReferencedExerciseExists() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006201")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000006202")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006203")!
        let state = SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        )
        context.insert(state)
        try context.save()

        let firstClient = FakeSyncClient()
        firstClient.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: sessionID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 31,
                        title: "Push",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    )
                ],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: loggedExerciseID.uuidString.lowercased(),
                        createdAt: 11,
                        updatedAt: 21,
                        deletedAt: nil,
                        serverUpdatedAt: 32,
                        sessionClientId: sessionID.uuidString.lowercased(),
                        exerciseClientId: exerciseID.uuidString.lowercased(),
                        orderIndex: 0,
                        exerciseSnapshotName: "Bench Press",
                        exerciseSnapshotEquipmentRaw: "barbell",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
                        hasSnapshotMetadata: true,
                        notes: "",
                        referenceNotes: nil
                    )
                ],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 31, loggedExercises: 32),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: firstClient).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(state.workoutSessionsCursor, 31)
        XCTAssertEqual(state.loggedExercisesCursor, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LoggedExercise>()).isEmpty)

        let secondClient = FakeSyncClient()
        secondClient.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: exerciseID.uuidString.lowercased(),
                        createdAt: 9,
                        updatedAt: 19,
                        deletedAt: nil,
                        serverUpdatedAt: 30,
                        seedIdentifier: nil,
                        name: "Bench Press",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: false
                    )
                ],
                workoutSessions: [],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: loggedExerciseID.uuidString.lowercased(),
                        createdAt: 11,
                        updatedAt: 21,
                        deletedAt: nil,
                        serverUpdatedAt: 32,
                        sessionClientId: sessionID.uuidString.lowercased(),
                        exerciseClientId: exerciseID.uuidString.lowercased(),
                        orderIndex: 0,
                        exerciseSnapshotName: "Bench Press",
                        exerciseSnapshotEquipmentRaw: "barbell",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
                        hasSnapshotMetadata: true,
                        notes: "",
                        referenceNotes: nil
                    )
                ],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30, workoutSessions: 31, loggedExercises: 32),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: secondClient).run(ownerTokenIdentifier: owner, context: context)

        let loggedExercise = try XCTUnwrap(context.fetch(FetchDescriptor<LoggedExercise>()).first)
        XCTAssertEqual(secondClient.fetchRequests.first?.cursors.loggedExercises, 0)
        XCTAssertEqual(loggedExercise.id, loggedExerciseID)
        XCTAssertEqual(loggedExercise.exercise?.id, exerciseID)
        XCTAssertEqual(state.exercisesCursor, 30)
        XCTAssertEqual(state.loggedExercisesCursor, 32)
    }

    func testPullImportsLoggedExerciseWhenReferencedExerciseIsTombstoned() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006251")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000006252")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006253")!
        let state = SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        )
        context.insert(state)
        try context.save()

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: exerciseID.uuidString.lowercased(),
                        createdAt: 9,
                        updatedAt: 19,
                        deletedAt: 29,
                        serverUpdatedAt: 30,
                        seedIdentifier: nil,
                        name: "Deleted Bench",
                        categoryRaw: "strength",
                        equipmentRaw: "barbell",
                        primaryMuscleRaw: "Chest",
                        primaryMuscleGroupRaw: "chest",
                        notes: "",
                        isArchived: false,
                        isSeeded: false
                    )
                ],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: sessionID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 31,
                        title: "Push",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    )
                ],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: loggedExerciseID.uuidString.lowercased(),
                        createdAt: 11,
                        updatedAt: 21,
                        deletedAt: nil,
                        serverUpdatedAt: 32,
                        sessionClientId: sessionID.uuidString.lowercased(),
                        exerciseClientId: exerciseID.uuidString.lowercased(),
                        orderIndex: 0,
                        exerciseSnapshotName: "Bench Press",
                        exerciseSnapshotEquipmentRaw: "barbell",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
                        hasSnapshotMetadata: true,
                        notes: "",
                        referenceNotes: nil
                    )
                ],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30, workoutSessions: 31, loggedExercises: 32),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first)
        let loggedExercise = try XCTUnwrap(context.fetch(FetchDescriptor<LoggedExercise>()).first)
        XCTAssertEqual(exercise.id, exerciseID)
        XCTAssertEqual(exercise.deletedAt, Date(timeIntervalSince1970: 29))
        XCTAssertEqual(loggedExercise.id, loggedExerciseID)
        XCTAssertEqual(loggedExercise.exercise?.id, exerciseID)
        XCTAssertEqual(loggedExercise.exerciseSnapshotName, "Bench Press")
        XCTAssertEqual(state.exercisesCursor, 30)
        XCTAssertEqual(state.loggedExercisesCursor, 32)
    }

    func testPullAdvancesLoggedExerciseCursorForTombstoneWhenSessionIsMissing() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let missingTombstoneID = UUID(uuidString: "00000000-0000-0000-0000-000000006303")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000006312")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006313")!
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: missingTombstoneID.uuidString.lowercased(),
                        createdAt: 1,
                        updatedAt: 2,
                        deletedAt: 3,
                        serverUpdatedAt: 60,
                        sessionClientId: "00000000-0000-0000-0000-000000006302",
                        exerciseClientId: nil,
                        orderIndex: 0,
                        exerciseSnapshotName: "",
                        exerciseSnapshotEquipmentRaw: "none",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "other",
                        hasSnapshotMetadata: false,
                        notes: "",
                        referenceNotes: nil
                    )
                ],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 60, loggedSets: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false, loggedExercises: true)
            ),
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: sessionID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 70,
                        title: "Pull",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    )
                ],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: loggedExerciseID.uuidString.lowercased(),
                        createdAt: 11,
                        updatedAt: 21,
                        deletedAt: nil,
                        serverUpdatedAt: 80,
                        sessionClientId: sessionID.uuidString.lowercased(),
                        exerciseClientId: nil,
                        orderIndex: 0,
                        exerciseSnapshotName: "Lat Pulldown",
                        exerciseSnapshotEquipmentRaw: "cable",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "back",
                        hasSnapshotMetadata: true,
                        notes: "",
                        referenceNotes: nil
                    )
                ],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 70, loggedExercises: 80, loggedSets: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        let loggedExercises = try context.fetch(FetchDescriptor<LoggedExercise>())
        XCTAssertEqual(client.fetchRequests.map(\.cursors.loggedExercises), [0, 60])
        XCTAssertEqual(state.workoutSessionsCursor, 70)
        XCTAssertEqual(state.loggedExercisesCursor, 80)
        XCTAssertNil(loggedExercises.first { $0.id == missingTombstoneID })
        XCTAssertNotNil(loggedExercises.first { $0.id == loggedExerciseID })
    }

    func testPullAdvancesLoggedSetCursorForTombstoneWhenLoggedExerciseIsMissing() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let missingTombstoneID = UUID(uuidString: "00000000-0000-0000-0000-000000006404")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000006412")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006413")!
        let setID = UUID(uuidString: "00000000-0000-0000-0000-000000006414")!
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [
                    LoggedSetSyncRecord(
                        clientId: missingTombstoneID.uuidString.lowercased(),
                        createdAt: 1,
                        updatedAt: 2,
                        deletedAt: 3,
                        serverUpdatedAt: 60,
                        loggedExerciseClientId: "00000000-0000-0000-0000-000000006403",
                        orderIndex: 0,
                        weight: nil,
                        reps: nil,
                        rpe: nil,
                        placeholderWeight: nil,
                        placeholderReps: nil,
                        placeholderRPE: nil,
                        kindRaw: "working",
                        isCompleted: false,
                        completedAt: nil,
                        notes: "",
                        healthLinkID: nil
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 0, loggedSets: 60),
                hasMore: SyncHasMore(userSettings: false, exercises: false, loggedSets: true)
            ),
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: sessionID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 20,
                        deletedAt: nil,
                        serverUpdatedAt: 70,
                        title: "Legs",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    )
                ],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: loggedExerciseID.uuidString.lowercased(),
                        createdAt: 11,
                        updatedAt: 21,
                        deletedAt: nil,
                        serverUpdatedAt: 80,
                        sessionClientId: sessionID.uuidString.lowercased(),
                        exerciseClientId: nil,
                        orderIndex: 0,
                        exerciseSnapshotName: "Squat",
                        exerciseSnapshotEquipmentRaw: "barbell",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "legs",
                        hasSnapshotMetadata: true,
                        notes: "",
                        referenceNotes: nil
                    )
                ],
                loggedSets: [
                    LoggedSetSyncRecord(
                        clientId: setID.uuidString.lowercased(),
                        createdAt: 12,
                        updatedAt: 22,
                        deletedAt: nil,
                        serverUpdatedAt: 90,
                        loggedExerciseClientId: loggedExerciseID.uuidString.lowercased(),
                        orderIndex: 0,
                        weight: 225,
                        reps: 5,
                        rpe: nil,
                        placeholderWeight: nil,
                        placeholderReps: nil,
                        placeholderRPE: nil,
                        kindRaw: "working",
                        isCompleted: true,
                        completedAt: nil,
                        notes: "",
                        healthLinkID: nil
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 70, loggedExercises: 80, loggedSets: 90),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        let sets = try context.fetch(FetchDescriptor<LoggedSet>())
        XCTAssertEqual(client.fetchRequests.map(\.cursors.loggedSets), [0, 60])
        XCTAssertEqual(state.loggedExercisesCursor, 80)
        XCTAssertEqual(state.loggedSetsCursor, 90)
        XCTAssertNil(sets.first { $0.id == missingTombstoneID })
        XCTAssertNotNil(sets.first { $0.id == setID })
    }

    func testPullStopsCurrentPaginationWhenLoggedSetParentIsMissingAndHasMore() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [
                    LoggedSetSyncRecord(
                        clientId: "00000000-0000-0000-0000-000000006204",
                        createdAt: 1,
                        updatedAt: 2,
                        deletedAt: nil,
                        serverUpdatedAt: 50,
                        loggedExerciseClientId: "00000000-0000-0000-0000-000000006203",
                        orderIndex: 0,
                        weight: 100,
                        reps: 5,
                        rpe: nil,
                        placeholderWeight: nil,
                        placeholderReps: nil,
                        placeholderRPE: nil,
                        kindRaw: "working",
                        isCompleted: true,
                        completedAt: nil,
                        notes: "",
                        healthLinkID: nil
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 0, loggedSets: 50),
                hasMore: SyncHasMore(userSettings: false, exercises: false, loggedSets: true)
            ),
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 0, loggedSets: 100),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertEqual(client.fetchRequests.count, 1)
        XCTAssertEqual(state.loggedSetsCursor, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LoggedSet>()).isEmpty)
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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 31),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: ownerTokenIdentifier, context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 31),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 31),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 31),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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
        let client = FakeSyncClient()
        client.userSettingsMutationResults = [
            SyncMutationResult(status: "ignored_stale", serverUpdatedAt: 30)
        ]
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [remoteRecord],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
            SyncFetchChangesResponse(
                userSettings: [remoteRecord],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 30, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

    func testIgnoredStaleWorkoutSessionPushRewindsWorkoutSessionCursor() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000005501")!
        let state = SyncCursorState(
            ownerTokenIdentifier: owner,
            workoutSessionsCursor: 50,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        )
        let session = WorkoutSession(
            id: sessionID,
            title: "Local Push",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 20),
            syncOwnerTokenIdentifier: owner
        )
        context.insert(state)
        context.insert(session)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .workoutSession,
            entityID: session.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 20)
        )
        try context.save()

        let client = FakeSyncClient()
        client.workoutSessionMutationResults = [
            SyncMutationResult(status: "ignored_stale", serverUpdatedAt: 40)
        ]
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: sessionID.uuidString.lowercased(),
                        createdAt: 10,
                        updatedAt: 30,
                        deletedAt: nil,
                        serverUpdatedAt: 40,
                        title: "Remote Push",
                        startedAt: 100,
                        endedAt: 200,
                        durationSeconds: 100,
                        notes: "",
                        referenceNotes: nil,
                        statusRaw: "completed",
                        sourceRaw: "blank",
                        sourceSessionID: nil,
                        healthLinkID: nil
                    )
                ],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 40),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.fetchRequests.map(\.cursors.workoutSessions), [39])
        XCTAssertEqual(session.title, "Remote Push")
        XCTAssertEqual(state.workoutSessionsCursor, 40)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
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

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
        client.error = PushError()
        let coordinator = SyncCoordinator(client: client)
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

        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedExercises.map { $0.clientId }, [exercise.id.uuidString.lowercased()])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunRetriesFailedWorkoutSessionPushOnNextRunWithoutDuplicatingEntries() async throws {
        struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000005601")!,
            title: "Retry Push",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank
        )
        context.insert(session)
        try SyncOutboxRecorder().recordCreate(
            entityKind: .workoutSession,
            entityID: session.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let firstClient = FakeSyncClient()
        firstClient.error = PushError()
        try await SyncCoordinator(client: firstClient).run(ownerTokenIdentifier: owner, context: context)

        var entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        let failedEntry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(failedEntry.attemptCount, 1)
        XCTAssertEqual(failedEntry.lastErrorMessage, "offline")

        let retryClient = FakeSyncClient()
        try await SyncCoordinator(client: retryClient).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(retryClient.upsertedWorkoutSessions.map(\.clientId), [session.id.uuidString.lowercased()])
        XCTAssertEqual(retryClient.operationLog, ["upsertWorkoutSession:\(session.id.uuidString.lowercased())"])
        entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertTrue(entries.isEmpty)
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

        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedExercises.count, 0)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.lastErrorMessage, "Cannot sync exercise \(exercise.id.uuidString) because the local record belongs to a different owner.")
    }

    func testRunContinuesAfterOwnerMismatchWhenLaterEntriesAreValid() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|owner_a"
        let otherOwner = "issuer|owner_b"
        let state = try SyncCursorState.state(for: owner, context: context)
        state.hasBootstrappedSettingsExercises = true
        state.hasBootstrappedWorkoutGraph = true

        let otherSession = WorkoutSession(
            title: "Other Owner",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: otherOwner
        )
        let otherLoggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let otherSet = LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)
        otherLoggedExercise.session = otherSession
        otherSet.loggedExercise = otherLoggedExercise
        otherSession.loggedExercises.append(otherLoggedExercise)
        otherLoggedExercise.sets.append(otherSet)

        let ownedSession = WorkoutSession(
            title: "Owned Session",
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400),
            durationSeconds: 100,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: owner
        )
        let ownedLoggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Squat")
        let ownedSet = LoggedSet(orderIndex: 0, weight: 200, reps: 5, isCompleted: true)
        ownedLoggedExercise.session = ownedSession
        ownedSet.loggedExercise = ownedLoggedExercise
        ownedSession.loggedExercises.append(ownedLoggedExercise)
        ownedLoggedExercise.sets.append(ownedSet)

        context.insert(otherSession)
        context.insert(otherLoggedExercise)
        context.insert(otherSet)
        context.insert(ownedSession)
        context.insert(ownedLoggedExercise)
        context.insert(ownedSet)
        let staleEntry = SyncOutboxEntry(
            entityKind: .loggedSet,
            entityID: otherSet.id,
            operation: .update,
            status: .failed,
            ownerTokenIdentifier: owner,
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 600)
        )
        context.insert(staleEntry)
        try context.save()

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.upsertedLoggedSets.map(\.clientId), [ownedSet.id.uuidString.lowercased()])
        XCTAssertEqual(staleEntry.status, .failed)
        XCTAssertEqual(staleEntry.lastErrorMessage, "Cannot sync loggedSet \(otherSet.id.uuidString) because the local record belongs to a different owner.")
        XCTAssertFalse(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).contains { $0.entityID == ownedSet.id })
    }

    func testRunTombstonesMissingExerciseForUpdateEntry() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000003006")!
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
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

        let firstClient = FakeSyncClient()
        firstClient.error = PushError()
        let coordinator = SyncCoordinator(client: firstClient)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let failedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(failedEntry.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertNotEqual(failedEntry.updatedAt, Date(timeIntervalSince1970: 100))

        let retryClient = FakeSyncClient()
        try await SyncCoordinator(client: retryClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let firstClient = FakeSyncClient()
        firstClient.error = PushError()
        try await SyncCoordinator(client: firstClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let failedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(failedEntry.createdAt, Date(timeIntervalSince1970: 200))
        XCTAssertNotEqual(failedEntry.updatedAt, Date(timeIntervalSince1970: 200))

        let retryClient = FakeSyncClient()
        try await SyncCoordinator(client: retryClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(retryClient.tombstones.count, 1)
        XCTAssertEqual(retryClient.tombstones.first?.0, .exercise)
        XCTAssertEqual(retryClient.tombstones.first?.1, exerciseID)
        XCTAssertEqual(retryClient.tombstones.first?.2, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunPullsRemoteExerciseAndAdvancesCursor() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 45),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 45, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 25, exercises: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(settings.weightUnit, .kilograms)
        XCTAssertEqual(settings.defaultRestTimerSeconds, 150)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunPullsUntilNoMoreAndUsesAdvancedCursors() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 10, exercises: 20),
                hasMore: SyncHasMore(userSettings: false, exercises: true)
            ),
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 10, exercises: 40),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
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
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

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

        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
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

        let client = FakeSyncClient()
        client.error = PushError()
        let coordinator = SyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        let failedEntry = try XCTUnwrap(entries.first { $0.entityID == failedExercise.id })
        let pendingEntry = try XCTUnwrap(entries.first { $0.entityID == pendingExercise.id })
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(pendingEntry.status, .pending)
    }
}

final class FakeSyncClient: SyncClient, @unchecked Sendable {
    var upsertedSettings: [UserSettingsSyncPayload] = []
    var upsertedExercises: [ExerciseSyncPayload] = []
    var upsertedWorkoutSessions: [WorkoutSessionSyncPayload] = []
    var upsertedLoggedExercises: [LoggedExerciseSyncPayload] = []
    var upsertedLoggedSets: [LoggedSetSyncPayload] = []
    var operationLog: [String] = []
    var tombstones: [(SyncEntityKind, UUID, Date)] = []
    var fetchRequests: [(cursors: SyncChangeCursors, limit: Int)] = []
    var userSettingsMutationResults: [SyncMutationResult] = []
    var exerciseMutationResults: [SyncMutationResult] = []
    var workoutSessionMutationResults: [SyncMutationResult] = []
    var loggedExerciseMutationResults: [SyncMutationResult] = []
    var loggedSetMutationResults: [SyncMutationResult] = []
    var tombstoneResults: [SyncMutationResult] = []
    var fetchResponses: [SyncFetchChangesResponse] = []
    var fetchResponse = SyncFetchChangesResponse(
        userSettings: [],
        exercises: [],
        workoutSessions: [],
        loggedExercises: [],
        loggedSets: [],
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

    func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        operationLog.append("upsertWorkoutSession:\(record.clientId)")
        upsertedWorkoutSessions.append(record)
        if !workoutSessionMutationResults.isEmpty {
            return workoutSessionMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        operationLog.append("upsertLoggedExercise:\(record.clientId)")
        upsertedLoggedExercises.append(record)
        if !loggedExerciseMutationResults.isEmpty {
            return loggedExerciseMutationResults.removeFirst()
        }
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        operationLog.append("upsertLoggedSet:\(record.clientId)")
        upsertedLoggedSets.append(record)
        if !loggedSetMutationResults.isEmpty {
            return loggedSetMutationResults.removeFirst()
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
