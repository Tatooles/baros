import Foundation
import SwiftData
import XCTest
@testable import BarosCore

/// The client half of the server-decides sync rule: the pull rule, sync
/// bases, rejection handling and the one-time update step.
@MainActor
final class SyncClientConvergenceTests: XCTestCase {
    private let owner = "issuer|owner_a"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Pull rule

    func testPullRuleTable() {
        func decide(
            localDeleted: Bool = false,
            incomingDeleted: Bool = false,
            intent: SyncLocalIntent = .none,
            bootstrapping: Bool = false,
            reasserts: Bool = true,
            localNewer: Bool = false
        ) -> SyncPullDecision {
            SyncPullRule.decide(
                localUpdatedAt: Date(timeIntervalSince1970: localNewer ? 200 : 100),
                localIsDeleted: localDeleted,
                incomingUpdatedAt: Date(timeIntervalSince1970: 150),
                incomingIsDeleted: incomingDeleted,
                localIntent: intent,
                isBootstrapping: bootstrapping,
                reassertsLocalDeletes: reasserts
            )
        }
        // Deletes win, even over a waiting local edit.
        XCTAssertEqual(decide(incomingDeleted: true, intent: .pending), .applyIncoming)
        XCTAssertEqual(decide(incomingDeleted: true, intent: .blocked, localNewer: true), .applyIncoming)
        // A local delete against a live copy is sent again, except for settings.
        XCTAssertEqual(decide(localDeleted: true), .reassertLocalDelete)
        XCTAssertEqual(decide(localDeleted: true, reasserts: false), .keepLocal(rewindCursor: false))
        XCTAssertEqual(decide(localDeleted: true, intent: .pending), .keepLocal(rewindCursor: false))
        // Both live: the server's version applies unless something waits to be sent.
        XCTAssertEqual(decide(localNewer: true), .applyIncoming)
        XCTAssertEqual(decide(intent: .pending), .keepLocal(rewindCursor: true))
        XCTAssertEqual(decide(intent: .blocked), .keepLocal(rewindCursor: false))
        // First-run bootstrap keeps a newer local copy for its upload to decide.
        XCTAssertEqual(decide(bootstrapping: true, localNewer: true), .keepLocal(rewindCursor: true))
        XCTAssertEqual(decide(bootstrapping: true), .applyIncoming)
    }

    func testPendingLocalEditIsKeptAndItsRecordPulledAgainAfterThePush() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Local Edit", context: context)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context)

        let client = FakeSyncClient()
        client.fetchResponses = [
            exerciseResponse([exerciseRecord(id: exercise.id, name: "Concurrent Server Edit", updatedAt: 1_900_000_000, serverUpdatedAt: 30)], cursor: 30),
        ]
        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(exercise.name, "Local Edit")
        XCTAssertEqual(client.upsertedExercises.map(\.name), ["Local Edit"])
        XCTAssertEqual(try SyncCursorState.state(for: owner, context: context).exercisesCursor, 29,
                       "The kept record is pulled again, so a push without a verdict cannot strand the server's version.")
    }

    func testServerTombstoneAppliesOverAWaitingEdit() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Local Edit", context: context)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context)

        let client = FakeSyncClient()
        client.fetchResponses = [
            exerciseResponse([exerciseRecord(id: exercise.id, name: "Deleted", updatedAt: 1_700_000_000, deletedAt: 1_700_000_000, serverUpdatedAt: 30)], cursor: 30),
        ]
        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertNotNil(exercise.deletedAt)
    }

    func testUserSettingsLocalDeleteIsKeptWithoutSendingItAgain() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(
            weightUnit: .pounds,
            syncOwnerTokenIdentifier: owner,
            updatedAt: Date(timeIntervalSince1970: 20),
            deletedAt: Date(timeIntervalSince1970: 20)
        )
        context.insert(settings)
        try markBootstrapped(context, upgraded: true)

        let client = FakeSyncClient()
        client.fetchResponses = [SyncFetchChangesResponse(
            userSettings: [UserSettingsSyncRecord(
                clientId: settings.id.uuidString.lowercased(), createdAt: 10, updatedAt: 40, deletedAt: nil,
                serverUpdatedAt: 45, weightUnitRaw: "kilograms", defaultRestTimerSeconds: 120, hasCompletedOnboarding: true
            )],
            exercises: [], workoutSessions: [], loggedExercises: [], loggedSets: [],
            cursors: SyncChangeCursors(userSettings: 45, exercises: 0),
            hasMore: SyncHasMore(userSettings: false, exercises: false)
        )]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertNotNil(settings.deletedAt)
        XCTAssertTrue(client.tombstones.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testPlaceholderTombstoneDeletesAHeldLoggedExerciseWithoutBlankingIt() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let graph = completedWorkout(context: context)
        graph.loggedExercise.notes = "Kept notes"
        try markBootstrapped(context, upgraded: true)

        let client = FakeSyncClient()
        client.fetchResponses = [SyncFetchChangesResponse(
            userSettings: [], exercises: [], workoutSessions: [],
            loggedExercises: [LoggedExerciseSyncRecord(
                clientId: graph.loggedExercise.id.uuidString.lowercased(), createdAt: 0, updatedAt: 1_900_000_000,
                deletedAt: 1_900_000_000, serverUpdatedAt: 70, sessionClientId: "", exerciseClientId: nil, orderIndex: 0,
                exerciseSnapshotName: "", exerciseSnapshotEquipmentRaw: "", exerciseSnapshotPrimaryMuscleGroupRaw: "",
                hasSnapshotMetadata: false, notes: "", referenceNotes: nil, sourceLoggedExerciseID: nil
            )],
            loggedSets: [],
            cursors: SyncChangeCursors(userSettings: 0, exercises: 0, loggedExercises: 70),
            hasMore: SyncHasMore(userSettings: false, exercises: false)
        )]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertNotNil(graph.loggedExercise.deletedAt)
        XCTAssertEqual(graph.loggedExercise.notes, "Kept notes")
        XCTAssertEqual(graph.loggedExercise.syncBaseUpdatedAt, 1_900_000_000)
    }

    func testRemoteSeedTombstoneAppliesToAnAdoptedSeedWithAWaitingEdit() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let remoteID = UUID()
        let bench = Exercise(
            seedIdentifier: "bench-press", name: "My Bench", category: .strength, equipment: .barbell,
            primaryMuscle: "Chest", isSeeded: true
        )
        context.insert(bench)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: bench.id, ownerTokenIdentifier: nil, context: context, now: start)
        try context.save()
        var tombstone = exerciseRecord(id: remoteID, name: "Bench Press", updatedAt: 20, deletedAt: 25, serverUpdatedAt: 31)
        tombstone = ExerciseSyncRecord(
            clientId: tombstone.clientId, createdAt: 10, updatedAt: 20, deletedAt: 25, serverUpdatedAt: 31,
            seedIdentifier: "bench-press", name: "Bench Press", categoryRaw: "strength", equipmentRaw: "barbell",
            primaryMuscleRaw: "Chest", primaryMuscleGroupRaw: "chest", notes: "", isArchived: false, isSeeded: true
        )
        let client = FakeSyncClient()
        client.fetchResponses = [exerciseResponse([tombstone], cursor: 31)]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(bench.id, remoteID)
        XCTAssertNotNil(bench.deletedAt, "Deletes win, even over a waiting local edit.")
    }

    // MARK: Sync base and stamps

    func testEditClockStampsAboveTheLocalVersionAndTheSyncBase() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(SyncEditClock.stamp(previous: Date(timeIntervalSince1970: 50), syncBase: nil, now: now), now)
        XCTAssertEqual(SyncEditClock.stamp(previous: now, syncBase: nil, now: now), now.addingTimeInterval(0.001))
        XCTAssertEqual(
            SyncEditClock.stamp(previous: Date(timeIntervalSince1970: 50), syncBase: 500, now: now),
            Date(timeIntervalSince1970: 500.001)
        )
    }

    func testUploadsNameTheirBaseAndAdoptTheStoredVersion() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("New", context: context)
        try SyncOutboxRecorder().recordCreate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)

        let client = FakeSyncClient()
        client.exerciseMutationResults = [SyncMutationResult(status: "inserted", serverUpdatedAt: 5, updatedAt: 1_850_000_000.25)]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.upsertedExercises.map(\.baseUpdatedAt), [nil], "A record never synced sends a null base.")
        XCTAssertEqual(exercise.syncBaseUpdatedAt, 1_850_000_000.25)

        // An edit on a slow clock still lands above the stored version, and names it.
        exercise.name = "Edited"
        exercise.touch(now: Date(timeIntervalSince1970: 1_000_000_000))
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        let next = FakeSyncClient()
        try await SyncCoordinator(client: next).run(ownerTokenIdentifier: owner, context: context)

        let upload = try XCTUnwrap(next.upsertedExercises.first)
        XCTAssertEqual(upload.baseUpdatedAt, 1_850_000_000.25)
        XCTAssertGreaterThan(upload.updatedAt, 1_850_000_000.25)
    }

    func testIgnoredUploadKeepsTheOldBase() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Lost", context: context)
        exercise.syncBaseUpdatedAt = 1_700_000_000
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)

        let client = FakeSyncClient()
        client.exerciseMutationResults = [SyncMutationResult(status: "ignored_stale", serverUpdatedAt: 9, updatedAt: 1_900_000_000)]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(exercise.syncBaseUpdatedAt, 1_700_000_000, "The server kept its own version; the pull brings it.")
    }

    func testPulledVersionBecomesTheSyncBase() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try markBootstrapped(context, upgraded: true)
        let id = UUID()
        let client = FakeSyncClient()
        client.fetchResponses = [exerciseResponse([exerciseRecord(id: id, name: "Pulled", updatedAt: 1_812_345_678.5, serverUpdatedAt: 8)], cursor: 8)]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.id == id })
        XCTAssertEqual(exercise.syncBaseUpdatedAt, 1_812_345_678.5)
    }

    // MARK: Rejections (#96)

    func testRejectionClassification() {
        XCTAssertEqual(SyncPushFailureClassifier.classify(URLError(.notConnectedToInternet)), .transient(.networkUnavailable))
        XCTAssertEqual(SyncPushFailureClassifier.classify(SyncServerRejection(code: "missingParent", message: "")), .record(code: "missingParent"))
        XCTAssertEqual(SyncPushFailureClassifier.classify(SyncServerRejection(code: "invalidPayload", message: "")), .record(code: "invalidPayload"))
        XCTAssertEqual(SyncPushFailureClassifier.classify(SyncServerRejection(code: "unauthenticated", message: "")), .accountWide(code: "unauthenticated"))
        XCTAssertEqual(SyncPushFailureClassifier.classify(SyncServerRejection(code: "accountDeletionInProgress", message: "")), .accountWide(code: "accountDeletionInProgress"))
        // Convex rejects bad arguments before any coded error: possibly permanent.
        XCTAssertEqual(SyncPushFailureClassifier.classify(SyncServerRejection(code: nil, message: "ArgumentValidationError")), .unknown)
        XCTAssertEqual(SyncPushFailureClassifier.classify(CocoaError(.coreData)), .local)
        XCTAssertEqual(
            SyncServerRejection.fromConvexErrorData(#"{"code":"missingParent","message":"No workout"}"#),
            SyncServerRejection(code: "missingParent", message: "No workout")
        )
        XCTAssertEqual(SyncServerRejection.fromConvexErrorData("\"plain\"").code, nil)
    }

    func testRejectedEntryBacksOffAndIsDeadLetteredOnlyAfterADayOfRejections() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Poison", context: context)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        client.onUpsertExercise = { _ in throw SyncServerRejection(code: "invalidPayload", message: "bad") }
        var now = start
        let coordinator = SyncCoordinator(client: client, clock: { now })
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)

        try await coordinator.run(ownerTokenIdentifier: owner, context: context)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.rejectionCount, 1)
        XCTAssertEqual(entry.lastRejectionCode, "invalidPayload")
        XCTAssertEqual(entry.nextAttemptAt, start.addingTimeInterval(30))

        // Still backing off: not sent.
        now = start.addingTimeInterval(10)
        try await coordinator.run(ownerTokenIdentifier: owner, context: context)
        XCTAssertEqual(entry.rejectionCount, 1)

        // Eight rejections in a few hours are not enough.
        for _ in 0 ..< 7 {
            now = try XCTUnwrap(entry.nextAttemptAt)
            try await coordinator.run(ownerTokenIdentifier: owner, context: context)
        }
        XCTAssertEqual(entry.rejectionCount, 8)
        XCTAssertEqual(entry.status, .failed)

        // Once the rejections span a day, the entry is dead-lettered.
        now = start.addingTimeInterval(SyncRejectionPolicy.blockingWindow)
        try await coordinator.run(ownerTokenIdentifier: owner, context: context)
        XCTAssertEqual(entry.status, .blocked)

        // A blocked entry is not sent again on its own.
        let sent = client.upsertedExercises.count
        now = now.addingTimeInterval(SyncRejectionPolicy.maxBackoff * 2)
        try await coordinator.run(ownerTokenIdentifier: owner, context: context)
        XCTAssertEqual(client.upsertedExercises.count, sent)
        XCTAssertEqual(exercise.name, "Poison", "A blocked record keeps its local version.")
    }

    func testOldStuckEntryIsNotDeadLetteredByItsLegacyAttemptCount() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Stuck Before Update", context: context)
        context.insert(SyncOutboxEntry(
            entityKind: .exercise, entityID: exercise.id, operation: .update, status: .failed,
            ownerTokenIdentifier: owner, createdAt: start, updatedAt: start, attemptCount: 50_000
        ))
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        client.onUpsertExercise = { _ in throw SyncServerRejection(code: nil, message: "Server Error") }

        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.rejectionCount, 1)
    }

    func testBackedOffEntryIsSentWhenTheClockMovedBackwards() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Backed Off", context: context)
        let entry = SyncOutboxEntry(
            entityKind: .exercise, entityID: exercise.id, operation: .update, status: .failed,
            ownerTokenIdentifier: owner, createdAt: start, updatedAt: start, attemptCount: 1
        )
        // Backed off from a clock a month ahead, which has since been corrected.
        entry.nextAttemptAt = start.addingTimeInterval(30 * 24 * 3600)
        context.insert(entry)
        try markBootstrapped(context, upgraded: true)

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.upsertedExercises.count, 1)
    }

    func testChildUploadWaitsForARejectedParentAndAMissingParentIsQueuedAgain() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let graph = completedWorkout(context: context)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .loggedExercise, entityID: graph.loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try recorder.recordUpdate(entityKind: .loggedSet, entityID: graph.set.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)

        let client = FakeSyncClient()
        client.onUpsertLoggedExercise = { _ in throw SyncServerRejection(code: "missingParent", message: "No workout") }
        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(client.upsertedLoggedSets.isEmpty, "The set waits for its rejected logged exercise.")
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(entries.first { $0.entityID == graph.set.id }?.status, .pending)
        XCTAssertEqual(entries.first { $0.entityID == graph.loggedExercise.id }?.status, .failed)
        XCTAssertNotNil(entries.first { $0.entityID == graph.session.id }, "The workout the server never got is queued again.")
    }

    func testLoggedExerciseWaitsForItsExerciseWhileTheExercisesCreateKeepsFailing() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let graph = completedWorkout(context: context)
        let exercise = ownedExercise("Never Uploaded", context: context)
        graph.loggedExercise.exercise = exercise
        let recorder = SyncOutboxRecorder()
        try recorder.recordCreate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try recorder.recordUpdate(entityKind: .loggedExercise, entityID: graph.loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        client.onUpsertExercise = { _ in throw SyncServerRejection(code: "invalidPayload", message: "bad") }

        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(client.upsertedLoggedExercises.isEmpty)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first { $0.entityID == graph.loggedExercise.id })
        XCTAssertEqual(entry.status, .pending, "It waits instead of being rejected for a missing reference.")
        XCTAssertEqual(entry.rejectionCount, 0)
    }

    func testFailingEditOfAWorkoutTheServerHasDoesNotHoldBackItsSets() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let graph = completedWorkout(context: context)
        graph.session.syncBaseUpdatedAt = 200
        let blockedEdit = SyncOutboxEntry(
            entityKind: .workoutSession, entityID: graph.session.id, operation: .update, status: .blocked,
            ownerTokenIdentifier: owner, createdAt: start, updatedAt: start, attemptCount: 9
        )
        context.insert(blockedEdit)
        try SyncOutboxRecorder().recordUpdate(entityKind: .loggedSet, entityID: graph.set.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.upsertedLoggedSets.map(\.clientId), [graph.set.id.uuidString.lowercased()])
    }

    func testEntriesWaitingOnARejectedWorkoutDoNotUseUpTheBatch() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let rejected = completedWorkout(context: context)
        let failingCreate = SyncOutboxEntry(
            entityKind: .workoutSession, entityID: rejected.session.id, operation: .create, status: .failed,
            ownerTokenIdentifier: owner, createdAt: start, updatedAt: start, attemptCount: 3
        )
        failingCreate.nextAttemptAt = start.addingTimeInterval(600)
        context.insert(failingCreate)
        let recorder = SyncOutboxRecorder()
        for index in 0 ..< 9 {
            let loggedExercise = LoggedExercise(orderIndex: index + 1, exerciseSnapshotName: "Row \(index)")
            loggedExercise.session = rejected.session
            rejected.session.loggedExercises.append(loggedExercise)
            context.insert(loggedExercise)
            try recorder.recordCreate(entityKind: .loggedExercise, entityID: loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        }
        let healthy = completedWorkout(context: context)
        try recorder.recordUpdate(entityKind: .loggedSet, entityID: healthy.set.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client, maxPendingPushEntriesPerRun: 8, clock: { self.start })
            .run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(client.upsertedLoggedExercises.isEmpty)
        XCTAssertEqual(client.upsertedLoggedSets.map(\.clientId), [healthy.set.id.uuidString.lowercased()])
    }

    func testSetWaitsWhenItsLoggedExerciseWaitsForAFailingExercise() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let graph = completedWorkout(context: context)
        let exercise = ownedExercise("Never Uploaded", context: context)
        graph.loggedExercise.exercise = exercise
        let recorder = SyncOutboxRecorder()
        try recorder.recordCreate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try recorder.recordCreate(entityKind: .loggedExercise, entityID: graph.loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try recorder.recordCreate(entityKind: .loggedSet, entityID: graph.set.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        client.onUpsertExercise = { _ in throw SyncServerRejection(code: "invalidPayload", message: "bad") }

        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(client.upsertedLoggedSets.isEmpty, "The set waits with its logged exercise.")
        let set = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first { $0.entityID == graph.set.id })
        XCTAssertEqual(set.rejectionCount, 0)
    }

    func testRequeuedMissingParentHoldsBackItsChildrenWhileItKeepsFailing() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let graph = completedWorkout(context: context)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .loggedExercise, entityID: graph.loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        client.onUpsertLoggedExercise = { _ in throw SyncServerRejection(code: "missingParent", message: "No workout") }
        var now = start
        let coordinator = SyncCoordinator(client: client, clock: { now })
        try await coordinator.run(ownerTokenIdentifier: owner, context: context)

        // The workout is queued again, and its upload fails too.
        let parent = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first { $0.entityID == graph.session.id })
        XCTAssertEqual(parent.operation, .update)
        client.onUpsertWorkoutSession = { _ in throw SyncServerRejection(code: "invalidPayload", message: "bad") }
        try recorder.recordUpdate(entityKind: .loggedSet, entityID: graph.set.id, ownerTokenIdentifier: owner, context: context, now: start)
        now = start.addingTimeInterval(10)
        try await coordinator.run(ownerTokenIdentifier: owner, context: context)

        // The logged exercise is still backing off; its set waits with it.
        XCTAssertTrue(client.upsertedLoggedSets.isEmpty)
        let set = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first { $0.entityID == graph.set.id })
        XCTAssertEqual(set.rejectionCount, 0)
    }

    func testDeletingARequeuedParentStillSendsItsTombstone() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let graph = completedWorkout(context: context)
        try SyncOutboxRecorder().recordUpdate(entityKind: .loggedExercise, entityID: graph.loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        client.onUpsertLoggedExercise = { _ in throw SyncServerRejection(code: "missingParent", message: "No workout") }
        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        graph.session.markDeletedCascade(now: start)
        try SyncOutboxRecorder().recordDelete(entityKind: .workoutSession, entityID: graph.session.id, ownerTokenIdentifier: owner, context: context, now: start)

        let parent = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first { $0.entityID == graph.session.id })
        XCTAssertEqual(parent.operation, .delete)
    }

    func testSingleAccountWideRejectionDoesNotReportTheRunAsSynced() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Waiting", context: context)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        client.onUpsertExercise = { _ in throw SyncServerRejection(code: "unauthenticated", message: "Signed out") }

        do {
            try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)
            XCTFail("Expected the run to report the refused write")
        } catch let SyncCoordinatorError.accountUnavailable(code) {
            XCTAssertEqual(code, "unauthenticated")
        }
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.rejectionCount, 0)
    }

    func testAccountWideRejectionIsReportedWhenALaterNetworkErrorEndsTheRun() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let first = ownedExercise("First", context: context)
        let second = ownedExercise("Second", context: context)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .exercise, entityID: first.id, ownerTokenIdentifier: owner, context: context, now: start)
        try recorder.recordUpdate(entityKind: .exercise, entityID: second.id, ownerTokenIdentifier: owner, context: context, now: start.addingTimeInterval(1))
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        let firstID = first.id.uuidString.lowercased()
        client.onUpsertExercise = { record in
            if record.clientId == firstID { throw SyncServerRejection(code: "unauthenticated", message: "Signed out") }
            throw URLError(.notConnectedToInternet)
        }

        do {
            try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)
            XCTFail("Expected the run to report the refused write")
        } catch let SyncCoordinatorError.accountUnavailable(code) {
            XCTAssertEqual(code, "unauthenticated")
        }
    }

    func testStreakOfLocalFailuresStopsTheRun() async throws {
        struct LocalStoreError: Error {}
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        for index in 0 ..< 8 {
            let exercise = ownedExercise("E\(index)", context: context)
            try recorder.recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start.addingTimeInterval(Double(index)))
        }
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        var attempts = 0
        client.onUpsertExercise = { _ in
            attempts += 1
            throw LocalStoreError()
        }

        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(attempts, SyncRejectionPolicy.uncodedRejectionStreakBeforeStopping)
    }

    func testEditDuringUploadStaysAboveTheVersionTheServerStored() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Uploading", context: context)
        exercise.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        // The server kept the upload above its own stamp, as after a fast clock.
        client.exerciseMutationResults = [SyncMutationResult(status: "updated", serverUpdatedAt: 9, updatedAt: 1_900_000_000)]
        let owner = self.owner
        let start = self.start
        client.whileExerciseUploadInFlight = {
            exercise.name = "Edited While Uploading"
            exercise.touch(now: Date(timeIntervalSince1970: 1_800_000_001))
            try? SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        }

        try await SyncCoordinator(client: client, clock: { start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(exercise.syncBaseUpdatedAt, 1_900_000_000)
        XCTAssertGreaterThan(exercise.updatedAt.timeIntervalSince1970, 1_900_000_000,
                             "Otherwise the server would read the next upload as a re-send with no edit.")
    }

    func testAdoptedSeedWithAWaitingEditIsPulledAgainAfterThePush() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bench = Exercise(
            seedIdentifier: "bench-press", name: "My Bench", category: .strength, equipment: .barbell,
            primaryMuscle: "Chest", isSeeded: true
        )
        context.insert(bench)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: bench.id, ownerTokenIdentifier: nil, context: context, now: start)
        try context.save()
        let remote = ExerciseSyncRecord(
            clientId: UUID().uuidString.lowercased(), createdAt: 10, updatedAt: 20, deletedAt: nil, serverUpdatedAt: 31,
            seedIdentifier: "bench-press", name: "Bench Press", categoryRaw: "strength", equipmentRaw: "barbell",
            primaryMuscleRaw: "Chest", primaryMuscleGroupRaw: "chest", notes: "", isArchived: false, isSeeded: true
        )
        let client = FakeSyncClient()
        client.fetchResponses = [exerciseResponse([remote], cursor: 31)]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(bench.name, "My Bench")
        XCTAssertEqual(try SyncCursorState.state(for: owner, context: context).exercisesCursor, 30)
    }

    func testLocalFailureIsRetriedWithoutCountingTowardDeadLettering() async throws {
        struct LocalStoreError: Error {}
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let broken = ownedExercise("Broken Locally", context: context)
        let healthy = ownedExercise("Healthy", context: context)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .exercise, entityID: broken.id, ownerTokenIdentifier: owner, context: context, now: start)
        try recorder.recordUpdate(entityKind: .exercise, entityID: healthy.id, ownerTokenIdentifier: owner, context: context, now: start.addingTimeInterval(1))
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        let brokenID = broken.id.uuidString.lowercased()
        client.onUpsertExercise = { record in
            if record.clientId == brokenID { throw LocalStoreError() }
        }

        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first { $0.entityID == broken.id })
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.rejectionCount, 0)
        XCTAssertEqual(entry.nextAttemptAt, start.addingTimeInterval(SyncRejectionPolicy.firstBackoff))
        XCTAssertEqual(client.upsertedExercises.map(\.clientId), [healthy.id.uuidString.lowercased()])
    }

    func testAccountWideRejectionsStopTheRunWithoutCounting() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        for name in ["A", "B", "C"] {
            let exercise = ownedExercise(name, context: context)
            try recorder.recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)
        }
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        var attempts = 0
        client.onUpsertExercise = { _ in
            attempts += 1
            throw SyncServerRejection(code: "accountDeletionInProgress", message: "Deleting")
        }

        do {
            try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)
            XCTFail("Expected the run to stop")
        } catch let SyncCoordinatorError.accountUnavailable(code) {
            XCTAssertEqual(code, "accountDeletionInProgress")
        }

        XCTAssertEqual(attempts, SyncRejectionPolicy.accountWideRejectionsBeforeStopping)
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.status == .pending && $0.rejectionCount == 0 })
    }

    func testStreakOfUncodedRejectionsStopsTheRun() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        for index in 0 ..< 8 {
            let exercise = ownedExercise("E\(index)", context: context)
            try recorder.recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start.addingTimeInterval(Double(index)))
        }
        try markBootstrapped(context, upgraded: true)
        let client = FakeSyncClient()
        var attempts = 0
        client.onUpsertExercise = { _ in
            attempts += 1
            throw SyncServerRejection(code: nil, message: "Server Error")
        }

        try await SyncCoordinator(client: client, clock: { self.start }).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(attempts, SyncRejectionPolicy.uncodedRejectionStreakBeforeStopping)
    }

    func testRetrySendsBlockedEntriesAgainWithAFreshCount() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Blocked", context: context)
        let entry = SyncOutboxEntry(
            entityKind: .exercise, entityID: exercise.id, operation: .update, status: .blocked,
            ownerTokenIdentifier: owner, createdAt: start, updatedAt: start, attemptCount: 9
        )
        entry.rejectionCount = 9
        entry.firstRejectedAt = start
        entry.nextAttemptAt = start.addingTimeInterval(3600)
        context.insert(entry)

        let requeued = try SyncOutboxRecorder(clock: { self.start }).retryRejectedEntries(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(requeued, 1)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.rejectionCount, 0)
        XCTAssertNil(entry.nextAttemptAt)
        XCTAssertNil(entry.firstRejectedAt)
    }

    func testLocalEditUnblocksADeadLetteredEntry() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = ownedExercise("Blocked", context: context)
        let entry = SyncOutboxEntry(
            entityKind: .exercise, entityID: exercise.id, operation: .update, status: .blocked,
            ownerTokenIdentifier: owner, createdAt: start, updatedAt: start, attemptCount: 9
        )
        entry.nextAttemptAt = start.addingTimeInterval(3600)
        context.insert(entry)

        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: owner, context: context, now: start)

        XCTAssertEqual(entry.status, .pending)
        XCTAssertNil(entry.nextAttemptAt)
    }

    // MARK: One-time update step

    func testUpdateSendsTopmostLocalDeletesOnceAndSkipsSettings() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let deletedExercise = ownedExercise("Deleted", context: context)
        deletedExercise.deletedAt = Date(timeIntervalSince1970: 10)
        let deletedWorkout = completedWorkout(context: context)
        deletedWorkout.session.markDeletedCascade(now: Date(timeIntervalSince1970: 20))
        let liveWorkout = completedWorkout(context: context)
        liveWorkout.set.markDeleted(now: Date(timeIntervalSince1970: 30))
        // Removed during the workout, so the server never had it.
        let removedMidWorkout = LoggedSet(orderIndex: 1, reps: 5, createdAt: Date(timeIntervalSince1970: 120),
                                          updatedAt: Date(timeIntervalSince1970: 150), deletedAt: Date(timeIntervalSince1970: 150))
        removedMidWorkout.loggedExercise = liveWorkout.loggedExercise
        liveWorkout.loggedExercise.sets.append(removedMidWorkout)
        context.insert(removedMidWorkout)
        let discarded = completedWorkout(context: context)
        discarded.session.status = .discarded
        discarded.session.markDeletedCascade(now: Date(timeIntervalSince1970: 300))
        let settings = UserSettings(weightUnit: .pounds, syncOwnerTokenIdentifier: owner, deletedAt: Date(timeIntervalSince1970: 40))
        context.insert(settings)
        try markBootstrapped(context)

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(Set(client.tombstones.map(\.1)), [deletedExercise.id, deletedWorkout.session.id, liveWorkout.set.id])
        XCTAssertTrue(try SyncCursorState.state(for: owner, context: context).hasRunConvergenceUpgrade)

        let again = FakeSyncClient()
        try await SyncCoordinator(client: again).run(ownerTokenIdentifier: owner, context: context)
        XCTAssertTrue(again.tombstones.isEmpty, "The step runs once.")
    }

    func testUpdateAdoptsSyncBasesOnlyForRecordsWithNothingWaiting() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let synced = ownedExercise("Synced", context: context)
        synced.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let waiting = ownedExercise("Waiting", context: context)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: waiting.id, ownerTokenIdentifier: owner, context: context, now: start)
        try markBootstrapped(context)
        let client = FakeSyncClient()
        client.onUpsertExercise = { _ in throw URLError(.notConnectedToInternet) }

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(synced.syncBaseUpdatedAt, 1_700_000_000)
        XCTAssertNil(waiting.syncBaseUpdatedAt, "Its edit may never have reached the server.")
    }

    func testFreshDeviceMarksTheUpdateStepDoneWithoutResending() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try await SyncCoordinator(client: FakeSyncClient()).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertTrue(try SyncCursorState.state(for: owner, context: context).hasRunConvergenceUpgrade)
    }

    // MARK: Helpers

    private func markBootstrapped(_ context: ModelContext, upgraded: Bool = false) throws {
        let state = try SyncCursorState.state(for: owner, context: context)
        state.hasBootstrappedSettingsExercises = true
        state.hasBootstrappedWorkoutGraph = true
        state.hasRunConvergenceUpgrade = upgraded
        try context.save()
    }

    private func ownedExercise(_ name: String, context: ModelContext) -> Exercise {
        let exercise = Exercise(
            name: name, category: .strength, equipment: .barbell, primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner, updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        context.insert(exercise)
        return exercise
    }

    private func completedWorkout(context: ModelContext) -> (session: WorkoutSession, loggedExercise: LoggedExercise, set: LoggedSet) {
        let session = WorkoutSession(
            title: "Push", startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100, status: .completed, source: .blank,
            createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200),
            syncOwnerTokenIdentifier: owner
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0, exerciseSnapshotName: "Bench Press",
            createdAt: Date(timeIntervalSince1970: 110), updatedAt: Date(timeIntervalSince1970: 210)
        )
        let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true,
                            createdAt: Date(timeIntervalSince1970: 120), updatedAt: Date(timeIntervalSince1970: 220))
        loggedExercise.session = session
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(set)
        return (session, loggedExercise, set)
    }
}
