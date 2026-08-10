import SwiftData
import XCTest
@testable import Baros

@MainActor
final class SyncSchedulerStatusTests: XCTestCase {
    func testSchedulerCachesOwnerAndRestoresItAfterTransientNilOwner() throws {
        let store = makeOwnerStore()
        let scheduler = SyncScheduler(lastKnownOwnerTokenStore: store)
        let owner = "issuer|owner_a"

        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.currentOwnerTokenIdentifier = nil

        XCTAssertEqual(store.ownerTokenIdentifier, owner)
        XCTAssertTrue(scheduler.restoreLastKnownOwnerTokenIdentifier())
        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, owner)
    }

    func testSchedulerRestoresCachedOwnerWhenSubjectMatches() throws {
        let store = makeOwnerStore()
        let scheduler = SyncScheduler(lastKnownOwnerTokenStore: store)
        let owner = "issuer|owner_a"
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.currentOwnerTokenIdentifier = nil

        XCTAssertTrue(scheduler.restoreLastKnownOwnerTokenIdentifier(matchingOwnerSubject: "owner_a"))

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, owner)
        XCTAssertEqual(store.ownerTokenIdentifier, owner)
    }

    func testSchedulerActivatesValidatedOwnerAndCachesIt() throws {
        let store = makeOwnerStore()
        let scheduler = SyncScheduler(lastKnownOwnerTokenStore: store)
        let owner = "issuer|owner_a"
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.currentOwnerTokenIdentifier = nil

        XCTAssertTrue(scheduler.activateValidatedOwnerTokenIdentifier(owner))

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, owner)
        XCTAssertEqual(store.ownerTokenIdentifier, owner)
    }

    func testSchedulerActivatesValidatedExactOwnerAmongMultipleLocalOwners() throws {
        let store = makeOwnerStore()
        let ownerA = "issuer|owner_a"
        let ownerB = "issuer|owner_b"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(UserSettings(syncOwnerTokenIdentifier: ownerA))
        context.insert(UserSettings(syncOwnerTokenIdentifier: ownerB))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertTrue(scheduler.activateValidatedOwnerTokenIdentifier(ownerB))

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, ownerB)
        XCTAssertEqual(store.ownerTokenIdentifier, ownerB)
    }

    func testSchedulerValidatedExactOwnerOverridesStaleCache() throws {
        let store = makeOwnerStore()
        let ownerA = "issuer|owner_a"
        let ownerB = "issuer|owner_b"
        store.ownerTokenIdentifier = ownerA
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(UserSettings(syncOwnerTokenIdentifier: ownerA))
        context.insert(UserSettings(syncOwnerTokenIdentifier: ownerB))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertTrue(scheduler.activateValidatedOwnerTokenIdentifier(ownerB))

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, ownerB)
        XCTAssertEqual(store.ownerTokenIdentifier, ownerB)
    }

    func testSchedulerRestoresValidatedExactOwnerWithoutLocalFootprint() throws {
        let store = makeOwnerStore()
        let ownerB = "issuer|owner_b"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertTrue(scheduler.activateValidatedOwnerTokenIdentifier(ownerB))

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, ownerB)
        XCTAssertEqual(store.ownerTokenIdentifier, ownerB)
    }

    func testSchedulerDoesNotRestoreCachedOwnerWhenSubjectDoesNotMatch() throws {
        let store = makeOwnerStore()
        let scheduler = SyncScheduler(lastKnownOwnerTokenStore: store)
        let owner = "issuer|owner_a"
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.currentOwnerTokenIdentifier = nil

        XCTAssertFalse(scheduler.restoreLastKnownOwnerTokenIdentifier(matchingOwnerSubject: "owner_b"))

        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertEqual(store.ownerTokenIdentifier, owner)
    }

    func testSchedulerUsesValidatedExactOwnerWhenCacheBelongsToDifferentIssuer() throws {
        let store = makeOwnerStore()
        let scheduler = SyncScheduler(lastKnownOwnerTokenStore: store)
        let cachedOwner = "issuer_a|owner_a"
        scheduler.currentOwnerTokenIdentifier = cachedOwner
        scheduler.currentOwnerTokenIdentifier = nil

        XCTAssertTrue(
            scheduler.activateValidatedOwnerTokenIdentifier("issuer_b|owner_a")
        )

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, "issuer_b|owner_a")
        XCTAssertEqual(store.ownerTokenIdentifier, "issuer_b|owner_a")
    }

    func testSchedulerFallsBackToInferredOwnerWhenCachedOwnerSubjectMismatches() throws {
        let store = makeOwnerStore()
        store.ownerTokenIdentifier = "issuer|owner_b"
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(UserSettings(syncOwnerTokenIdentifier: owner))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertTrue(scheduler.restoreLastKnownOwnerTokenIdentifier(matchingOwnerSubject: "owner_a"))

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, owner)
        XCTAssertEqual(store.ownerTokenIdentifier, owner)
    }

    func testSchedulerRestoresSingleLocalOwnerWhenCacheIsEmpty() throws {
        let store = makeOwnerStore()
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(UserSettings(syncOwnerTokenIdentifier: owner))
        context.insert(Exercise(
            name: "Owner Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest,
            syncOwnerTokenIdentifier: owner
        ))
        context.insert(WorkoutSession(
            title: "Owner Workout",
            startedAt: .now,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: owner
        ))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertTrue(scheduler.restoreLastKnownOwnerTokenIdentifier())

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, owner)
        XCTAssertEqual(store.ownerTokenIdentifier, owner)
    }

    func testSchedulerRestoresSingleLocalOwnerWhenSubjectMatches() throws {
        let store = makeOwnerStore()
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(UserSettings(syncOwnerTokenIdentifier: owner))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertTrue(scheduler.restoreLastKnownOwnerTokenIdentifier(matchingOwnerSubject: "owner_a"))

        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, owner)
        XCTAssertEqual(store.ownerTokenIdentifier, owner)
    }

    func testSchedulerDoesNotInferLocalOwnerWhenSubjectDoesNotMatch() throws {
        let store = makeOwnerStore()
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(UserSettings(syncOwnerTokenIdentifier: owner))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertFalse(scheduler.restoreLastKnownOwnerTokenIdentifier(matchingOwnerSubject: "owner_b"))

        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertNil(store.ownerTokenIdentifier)
    }

    func testSchedulerDoesNotGuessLocalOwnerWhenMultipleOwnersExist() throws {
        let store = makeOwnerStore()
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_b"))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertFalse(scheduler.restoreLastKnownOwnerTokenIdentifier())

        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertNil(store.ownerTokenIdentifier)
    }

    func testSchedulerDoesNotRestoreSubjectAmongMultipleLocalOwners() throws {
        let store = makeOwnerStore()
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_b"))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)

        XCTAssertFalse(scheduler.restoreLastKnownOwnerTokenIdentifier(matchingOwnerSubject: "owner_b"))

        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertNil(store.ownerTokenIdentifier)
    }

    func testEnteringSignedOutModeClearsCachedOwnerAndSeedsLocalDefaults() throws {
        let store = makeOwnerStore()
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: owner)
        let scheduler = SyncScheduler(modelContext: context, lastKnownOwnerTokenStore: store)
        scheduler.currentOwnerTokenIdentifier = owner

        scheduler.enterSignedOutMode()

        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertNil(store.ownerTokenIdentifier)
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(
                from: try context.fetch(FetchDescriptor<UserSettings>()),
                ownerTokenIdentifier: nil
            ).count,
            1
        )
        XCTAssertEqual(
            Exercise.visibleActiveExercises(
                from: try context.fetch(FetchDescriptor<Exercise>()),
                ownerTokenIdentifier: nil
            )
            .filter(\.isSeeded)
            .count,
            20
        )
    }

    func testDeletionModeSuppressesSyncRequests() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: client), modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        scheduler.beginDeletionMode()
        scheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertFalse(scheduler.isSyncing)
        XCTAssertTrue(client.fetchRequests.isEmpty)
    }

    func testResetAfterDataDeletionClearsOwnerAndRuntimeState() {
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        scheduler.recordFailureForTesting(message: "offline", at: Date(timeIntervalSince1970: 100))
        scheduler.beginDeletionMode()

        scheduler.resetAfterDataDeletion()

        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNil(scheduler.lastSyncedAt)
        XCTAssertFalse(scheduler.hasQueuedSyncRequest)
        XCTAssertFalse(scheduler.isSyncing)
        XCTAssertFalse(scheduler.isDeletionModeEnabled)
    }

    func testSchedulerReportsSyncingDuringActiveRunAndSuccessAfterCompletion() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let coordinator = SyncCoordinator(client: client)
        let scheduler = SyncScheduler(coordinator: coordinator, modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        let syncStarted = expectation(description: "sync started")
        client.onFetchChanges = {
            XCTAssertTrue(scheduler.isSyncing)
            syncStarted.fulfill()
        }

        scheduler.requestSync()
        await fulfillment(of: [syncStarted], timeout: 1.0)
        try await waitUntil { !scheduler.isSyncing }

        XCTAssertFalse(scheduler.isSyncing)
        XCTAssertFalse(scheduler.hasQueuedSyncRequest)
        XCTAssertNotNil(scheduler.lastSyncedAt)
        XCTAssertNil(scheduler.lastFailure)
    }

    func testPausingActiveSyncQueuesItForAuthenticatedReplay() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        client.onFetchChanges = {
            guard client.fetchRequests.count == 1 else { return }
            scheduler.pauseCloudSync()
        }

        scheduler.requestSync()
        try await waitUntil {
            client.fetchRequests.count == 1
                && !scheduler.isSyncing
        }

        XCTAssertFalse(scheduler.isCloudSyncAuthorized)
        XCTAssertTrue(scheduler.hasQueuedSyncRequest)

        scheduler.authorizeCloudSync()
        scheduler.requestSync()
        try await waitUntil {
            client.fetchRequests.count == 2
                && scheduler.lastSyncedAt != nil
        }

        XCTAssertFalse(scheduler.hasQueuedSyncRequest)
    }

    func testSchedulerRecordsFailureAndRetryUsesSameRequestPath() async throws {
        struct FetchError: LocalizedError {
            var errorDescription: String? { "Convex function sync:fetchChanges failed" }
        }

        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        client.fetchError = FetchError()
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        scheduler.requestSync()
        try await waitUntil { scheduler.lastFailure != nil }

        XCTAssertFalse(scheduler.isSyncing)
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertEqual(scheduler.lastFailure?.message, "Convex function sync:fetchChanges failed")
        let failure = try XCTUnwrap(sink.observations.first { $0.kind == .durableFailure })
        XCTAssertEqual(failure.failureCategory, .syncRun)
        XCTAssertEqual(failure.errorCode, .syncRunFailed)

        client.fetchError = nil
        scheduler.retrySync()
        try await waitUntil { scheduler.lastSyncedAt != nil }

        XCTAssertEqual(scheduler.requestCount, 2)
        XCTAssertNil(scheduler.lastFailure)
        XCTAssertEqual(sink.observations.filter { $0.kind == .durableFailure }.count, 1)
    }

    func testOfflinePushIsATransientSyncConditionInsteadOfADurableSyncFailure() async throws {
        let owner = "issuer|owner_private"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Private workout content",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let client = FakeSyncClient()
        client.error = URLError(.notConnectedToInternet)
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = owner

        scheduler.requestSync()
        try await waitUntil { scheduler.lastFailure != nil }

        XCTAssertTrue(sink.observations.contains {
            $0.kind == .breadcrumb
                && $0.phase == .push
                && $0.errorCode == .networkUnavailable
        })
        XCTAssertFalse(sink.observations.contains { $0.kind == .durableFailure })
        XCTAssertFalse(String(describing: sink.observations).contains(owner))
    }

    func testRepeatedOfflinePushAttemptsRemainTransient() async throws {
        let owner = "issuer|owner_private"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Private workout content",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let client = FakeSyncClient()
        client.error = URLError(.notConnectedToInternet)
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = owner

        for attempt in 1...3 {
            attempt == 1 ? scheduler.requestSync() : scheduler.retrySync()
            try await waitUntil {
                let entries = try? context.fetch(FetchDescriptor<SyncOutboxEntry>())
                return entries?.first?.attemptCount == attempt && !scheduler.isSyncing
            }
        }

        XCTAssertFalse(sink.observations.contains { $0.kind == .durableFailure })
        XCTAssertEqual(sink.observations.filter {
            $0.kind == .breadcrumb && $0.errorCode == .networkUnavailable
        }.count, 3)
        XCTAssertFalse(String(describing: sink.observations).contains(owner))
        XCTAssertFalse(String(describing: sink.observations).contains("Private workout content"))
    }

    func testTimedOutPullIsATransientSyncConditionInsteadOfADurableSyncFailure() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        client.fetchError = URLError(.timedOut)
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        scheduler.requestSync()
        try await waitUntil { scheduler.lastFailure != nil }

        XCTAssertTrue(sink.observations.contains {
            $0.kind == .breadcrumb
                && $0.phase == .pull
                && $0.errorCode == .requestTimedOut
        })
        XCTAssertFalse(sink.observations.contains { $0.kind == .durableFailure })
    }

    func testResolvingCurrentOwnerQueuesSyncAsATransientAuthorizationCondition() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        scheduler.pauseCloudSync()

        scheduler.requestSync()

        XCTAssertTrue(scheduler.hasQueuedSyncRequest)
        XCTAssertTrue(client.fetchRequests.isEmpty)
        XCTAssertTrue(sink.observations.contains {
            $0.kind == .breadcrumb
                && $0.errorCode == .authorizationUnavailable
        })
        XCTAssertFalse(sink.observations.contains { $0.kind == .durableFailure })
    }

    func testRepeatedDurablePushFailuresAreAllRecorded() async throws {
        struct PushError: LocalizedError {
            var errorDescription: String? { "private server detail" }
        }

        let owner = "issuer|owner_private"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Private workout content",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let client = FakeSyncClient()
        client.error = PushError()
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = owner

        scheduler.requestSync()
        try await waitUntil {
            sink.observations.filter { $0.kind == .durableFailure }.count == 1
        }
        scheduler.retrySync()
        try await waitUntil {
            sink.observations.filter { $0.kind == .durableFailure }.count == 2
        }

        let failures = sink.observations.filter { $0.kind == .durableFailure }
        XCTAssertEqual(failures.map(\.fingerprint), [failures[0].fingerprint, failures[0].fingerprint])
        XCTAssertEqual(failures.map(\.entityKind), [.exercise, .exercise])
        XCTAssertEqual(failures.map(\.operation), [.create, .create])
        XCTAssertEqual(failures.map(\.counts.attempt), [1, 2])
        XCTAssertFalse(String(describing: failures).contains(owner))
        XCTAssertFalse(String(describing: failures).contains("Private workout content"))
        XCTAssertFalse(String(describing: failures).contains("private server detail"))

        client.error = nil
        scheduler.retrySync()
        try await waitUntil { scheduler.lastSyncedAt != nil }
        XCTAssertEqual(sink.observations.filter { $0.kind == .durableFailure }.count, 2)
    }

    func testSuccessfulRetryAfterRelaunchDoesNotEmitAnotherFailure() async throws {
        struct PushError: LocalizedError {
            var errorDescription: String? { "private server detail" }
        }

        let owner = "issuer|owner_private"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Private workout content",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let client = FakeSyncClient()
        client.error = PushError()
        let firstSink = RecordingSyncObservationSink()
        let firstObservability = SyncObservability(sink: firstSink)
        let firstScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: firstObservability),
            modelContext: context,
            observability: firstObservability
        )
        firstScheduler.currentOwnerTokenIdentifier = owner
        firstScheduler.requestSync()
        try await waitUntil {
            firstSink.observations.contains { $0.kind == .durableFailure }
                && !firstScheduler.isSyncing
        }

        client.error = nil
        let relaunchedContext = ModelContext(container)
        let relaunchedSink = RecordingSyncObservationSink()
        let relaunchedObservability = SyncObservability(sink: relaunchedSink)
        let relaunchedScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: relaunchedObservability),
            modelContext: relaunchedContext,
            observability: relaunchedObservability
        )
        relaunchedScheduler.currentOwnerTokenIdentifier = owner
        relaunchedScheduler.retrySync()
        try await waitUntil { relaunchedScheduler.lastSyncedAt != nil }

        XCTAssertFalse(relaunchedSink.observations.contains { $0.kind == .durableFailure })
    }

    func testSuccessfulRetryOfPreviouslyFailedEntryDoesNotEmitFailure() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        let failedEntry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: exercise.id,
            operation: .create,
            status: .failed,
            ownerTokenIdentifier: owner,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            lastAttemptAt: Date(timeIntervalSince1970: 150),
            attemptCount: 3,
            lastErrorMessage: "legacy failure"
        )
        context.insert(exercise)
        context.insert(failedEntry)
        try context.save()

        let retryContext = ModelContext(container)
        let client = FakeSyncClient()
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: retryContext,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.retrySync()
        try await waitUntil { scheduler.lastSyncedAt != nil }

        XCTAssertFalse(sink.observations.contains { $0.kind == .durableFailure })
    }

    func testSchedulerDoesNotRecordSuccessWhenPushLeavesFailedOutboxEntry() async throws {
        struct PushError: LocalizedError {
            var errorDescription: String? { "push failed" }
        }

        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .exercise,
            entityID: exercise.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let client = FakeSyncClient()
        client.error = PushError()
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = owner

        scheduler.requestSync()
        try await waitUntil {
            !scheduler.isSyncing
                && ((try? context.fetch(FetchDescriptor<SyncOutboxEntry>()).first?.status) == .failed)
        }

        XCTAssertNil(scheduler.lastSyncedAt)
        XCTAssertEqual(scheduler.lastFailure?.message, "Cloud sync could not finish.")
        XCTAssertEqual(scheduler.lastFailure?.reason, .failedOutboxPush)
    }

    func testSchedulerDoesNotRecordSuccessWhenRemotePullIsIncomplete() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: "00000000-0000-0000-0000-000000006601",
                        createdAt: 1,
                        updatedAt: 2,
                        deletedAt: nil,
                        serverUpdatedAt: 50,
                        sessionClientId: "00000000-0000-0000-0000-000000006602",
                        exerciseClientId: nil,
                        orderIndex: 0,
                        exerciseSnapshotName: "Standing Calf Raise",
                        exerciseSnapshotEquipmentRaw: "machine",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "legs",
                        hasSnapshotMetadata: true,
                        notes: "",
                        referenceNotes: nil,
                        sourceLoggedExerciseID: nil
                    )
                ],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 50, loggedSets: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false, loggedExercises: true)
            )
        ]
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = owner

        scheduler.requestSync()
        try await waitUntil {
            scheduler.lastSyncedAt != nil || scheduler.lastFailure != nil
        }

        XCTAssertNil(scheduler.lastSyncedAt)
        XCTAssertEqual(scheduler.lastFailure?.message, "Cloud sync could not finish.")
        XCTAssertEqual(scheduler.lastFailure?.reason, .incompleteRemotePull)
        let failure = try XCTUnwrap(sink.observations.first { $0.kind == .durableFailure })
        XCTAssertEqual(failure.failureCategory, .remotePull)
        XCTAssertEqual(failure.errorCode, .incompleteRemotePull)
    }

    func testSchedulerDrainsMorePendingEntriesBeforeFailingIncompleteRemotePull() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let recorder = SyncOutboxRecorder()
        for index in 0..<51 {
            let exercise = Exercise(
                name: "Exercise \(index)",
                category: .strength,
                equipment: .barbell,
                primaryMuscle: "Chest",
                syncOwnerTokenIdentifier: owner
            )
            context.insert(exercise)
            try recorder.recordUpdate(
                entityKind: .exercise,
                entityID: exercise.id,
                ownerTokenIdentifier: owner,
                context: context,
                now: Date(timeIntervalSince1970: Double(index))
            )
        }
        try context.save()

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: "00000000-0000-0000-0000-000000006611",
                        createdAt: 1,
                        updatedAt: 2,
                        deletedAt: nil,
                        serverUpdatedAt: 50,
                        sessionClientId: "00000000-0000-0000-0000-000000006612",
                        exerciseClientId: nil,
                        orderIndex: 0,
                        exerciseSnapshotName: "Standing Calf Raise",
                        exerciseSnapshotEquipmentRaw: "machine",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "legs",
                        hasSnapshotMetadata: true,
                        notes: "",
                        referenceNotes: nil,
                        sourceLoggedExerciseID: nil
                    )
                ],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 50, loggedSets: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]
        let coordinator = SyncCoordinator(client: client, maxPendingPushEntriesPerRun: 50)
        let scheduler = SyncScheduler(coordinator: coordinator, modelContext: context)
        scheduler.currentOwnerTokenIdentifier = owner

        scheduler.requestSync()
        try await waitUntil {
            scheduler.lastSyncedAt != nil || scheduler.lastFailure != nil
        }

        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNotNil(scheduler.lastSyncedAt)
        XCTAssertEqual(client.upsertedExercises.count, 51)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testSchedulerDiscardsOutboxEntryWhenLocalRecordBelongsToDifferentOwner() async throws {
        let currentOwner = "issuer|owner_a"
        let otherOwner = "issuer|owner_b"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5)
        let loggedExercise = LoggedExercise(orderIndex: 0, sets: [set])
        let session = WorkoutSession(
            title: "Other owner workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: otherOwner,
            loggedExercises: [loggedExercise]
        )
        context.insert(session)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .loggedSet,
            entityID: set.id,
            ownerTokenIdentifier: currentOwner,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        let client = FakeSyncClient()
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )
        scheduler.currentOwnerTokenIdentifier = currentOwner

        scheduler.requestSync()
        try await waitUntil {
            scheduler.lastSyncedAt != nil || scheduler.lastFailure != nil
        }

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(client.upsertedLoggedSets.isEmpty)
        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNotNil(scheduler.lastSyncedAt)
        let events = sink.observations.filter { $0.kind != .breadcrumb }
        XCTAssertEqual(events.map(\.kind), [.durableFailure])
        XCTAssertEqual(events.first?.failureCategory, .ownership)
        XCTAssertEqual(events.first?.errorCode, .ownerMismatch)
        XCTAssertEqual(events.first?.entityKind, .loggedSet)
        XCTAssertFalse(String(describing: events).contains(currentOwner))
        XCTAssertFalse(String(describing: events).contains(otherOwner))
    }

    func testSchedulerDoesNotRecordSuccessWithoutOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client, observability: observability),
            modelContext: context,
            observability: observability
        )

        scheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertNil(scheduler.lastSyncedAt)
        XCTAssertNil(scheduler.lastFailure)
        XCTAssertFalse(scheduler.isSyncing)
        XCTAssertTrue(sink.observations.contains {
            $0.kind == .breadcrumb
                && $0.phase == .ownership
                && $0.errorCode == .noCurrentOwner
        })
        XCTAssertFalse(sink.observations.contains { $0.kind == .durableFailure })
    }

    func testForegroundTriggerRetriesFailedOutboxEntry() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner
        )
        context.insert(exercise)
        let failedEntry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: exercise.id,
            operation: .update,
            status: .failed,
            ownerTokenIdentifier: owner,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            lastAttemptAt: Date(timeIntervalSince1970: 150),
            attemptCount: 1,
            lastErrorMessage: "offline"
        )
        context.insert(failedEntry)
        try context.save()

        let client = FakeSyncClient()
        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: client), modelContext: context)
        scheduler.currentOwnerTokenIdentifier = owner

        scheduler.requestSyncOnAppForeground()
        try await waitUntil {
            !scheduler.isSyncing
                && ((try? context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty) == true)
        }

        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertEqual(client.upsertedExercises.map(\.clientId), [exercise.id.uuidString.lowercased()])
        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNotNil(scheduler.lastSyncedAt)
    }

    func testForegroundTriggerIsNoOpInDeletionMode() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: client), modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        scheduler.beginDeletionMode()

        scheduler.requestSyncOnAppForeground()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertFalse(scheduler.isSyncing)
        XCTAssertTrue(client.fetchRequests.isEmpty)
    }

    func testForegroundTriggerIsNoOpWhenSignedOut() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: client), modelContext: context)

        scheduler.requestSyncOnAppForeground()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertFalse(scheduler.isSyncing)
        XCTAssertTrue(client.fetchRequests.isEmpty)
    }

    func testOwnerChangeClearsRuntimeFailureAndCancelsQueuedState() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let scheduler = SyncScheduler(coordinator: SyncCoordinator(client: client), modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        scheduler.recordFailureForTesting(message: "offline", at: Date(timeIntervalSince1970: 100))

        XCTAssertNotNil(scheduler.lastFailure)

        let syncStarted = expectation(description: "sync started")
        client.onFetchChanges = {
            XCTAssertTrue(scheduler.isSyncing)
            scheduler.requestSync()
            XCTAssertTrue(scheduler.hasQueuedSyncRequest)
            scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"
            syncStarted.fulfill()
        }

        scheduler.requestSync()
        await fulfillment(of: [syncStarted], timeout: 1.0)
        try await waitUntil { !scheduler.isSyncing }

        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNil(scheduler.lastSyncedAt)
        XCTAssertFalse(scheduler.hasQueuedSyncRequest)
        XCTAssertFalse(scheduler.isSyncing)
    }

    func testOwnerChangeClearsPausedSyncRequest() {
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        scheduler.pauseCloudSync()
        scheduler.requestSync()
        XCTAssertTrue(scheduler.hasQueuedSyncRequest)

        scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"
        scheduler.authorizeCloudSync()
        scheduler.pauseCloudSync()

        XCTAssertFalse(scheduler.hasQueuedSyncRequest)
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

    private func makeOwnerStore() -> LastKnownSyncOwnerTokenStore {
        let suiteName = "SyncSchedulerStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LastKnownSyncOwnerTokenStore(userDefaults: defaults)
    }
}
