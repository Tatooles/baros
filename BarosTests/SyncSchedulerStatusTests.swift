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
        try await waitUntil {
            let entry = try? context.fetch(FetchDescriptor<SyncOutboxEntry>()).first
            return entry?.attemptCount == 1 && !scheduler.isSyncing
        }

        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertNil(scheduler.lastFailure)
        XCTAssertEqual(scheduler.lastTransientCondition?.errorCode, .networkUnavailable)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertNil(entry.lastErrorMessage)
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
        try await waitUntil {
            sink.observations.contains {
                $0.kind == .breadcrumb
                    && $0.phase == .pull
                    && $0.errorCode == .requestTimedOut
            } && !scheduler.isSyncing
        }

        XCTAssertNil(scheduler.lastFailure)
        XCTAssertEqual(scheduler.lastTransientCondition?.errorCode, .requestTimedOut)
        XCTAssertFalse(scheduler.hasUnfinishedSyncWork)
        XCTAssertTrue(scheduler.shouldAttemptNetworkRecovery)
        XCTAssertTrue(sink.observations.contains {
            $0.kind == .breadcrumb
                && $0.phase == .pull
                && $0.errorCode == .requestTimedOut
        })
        XCTAssertFalse(sink.observations.contains { $0.kind == .durableFailure })
    }

    func testOfflinePullRecordsNetworkTransientSyncCondition() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        client.fetchError = URLError(.notConnectedToInternet)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        scheduler.requestSync()
        try await waitUntil {
            scheduler.lastTransientCondition != nil && !scheduler.isSyncing
        }

        XCTAssertNil(scheduler.lastFailure)
        XCTAssertEqual(scheduler.lastTransientCondition?.errorCode, .networkUnavailable)
        XCTAssertFalse(scheduler.hasUnfinishedSyncWork)
        XCTAssertTrue(scheduler.shouldAttemptNetworkRecovery)

        client.fetchError = nil
        scheduler.retrySync()
        try await waitUntil { scheduler.lastSyncedAt != nil }

        XCTAssertNil(scheduler.lastTransientCondition)
        XCTAssertFalse(scheduler.hasUnfinishedSyncWork)
        XCTAssertFalse(scheduler.shouldAttemptNetworkRecovery)
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

    func testTransientPushAfterSuccessfulDurableRetryClearsResolvedFailure() async throws {
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
            updatedAt: Date(timeIntervalSince1970: 100),
            lastAttemptAt: Date(timeIntervalSince1970: 100),
            attemptCount: 1,
            lastErrorMessage: "durable failure"
        )
        let session = WorkoutSession(
            title: "Later pending workout",
            startedAt: Date(timeIntervalSince1970: 200),
            endedAt: Date(timeIntervalSince1970: 300),
            durationSeconds: 100,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: owner
        )
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        context.insert(exercise)
        context.insert(failedEntry)
        context.insert(session)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .workoutSession,
            entityID: session.id,
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        let client = FakeSyncClient()
        client.onUpsertExercise = { _ in
            client.error = URLError(.notConnectedToInternet)
        }
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.recordFailureForTesting(
            message: "Cloud sync could not finish.",
            reason: .failedOutboxPush
        )

        scheduler.retrySync()
        try await waitUntil {
            !scheduler.isSyncing && scheduler.lastTransientCondition != nil
        }

        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNil(scheduler.lastSyncedAt)
        XCTAssertEqual(scheduler.lastTransientCondition?.errorCode, .networkUnavailable)
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.entityKind, .workoutSession)
        XCTAssertEqual(entries.first?.status, .pending)
    }

    func testTransientPostPushPullAfterSuccessfulDurableRetryClearsResolvedFailure() async throws {
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
            updatedAt: Date(timeIntervalSince1970: 100),
            lastAttemptAt: Date(timeIntervalSince1970: 100),
            attemptCount: 1,
            lastErrorMessage: "durable failure"
        )
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        context.insert(exercise)
        context.insert(failedEntry)
        try context.save()

        let client = FakeSyncClient()
        client.onUpsertExercise = { _ in
            client.fetchError = URLError(.notConnectedToInternet)
        }
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.recordFailureForTesting(
            message: "Cloud sync could not finish.",
            reason: .failedOutboxPush
        )

        scheduler.retrySync()
        try await waitUntil {
            !scheduler.isSyncing && scheduler.lastTransientCondition != nil
        }

        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNil(scheduler.lastSyncedAt)
        XCTAssertEqual(scheduler.lastTransientCondition?.errorCode, .networkUnavailable)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
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

    func testSuccessfulCappedPageDrainsPendingWorkBeforeUntouchedDurableRetry() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        let recorder = SyncOutboxRecorder()
        for index in 0..<51 {
            let exercise = Exercise(
                name: "Pending Exercise \(index)",
                category: .strength,
                equipment: .barbell,
                primaryMuscle: "Back",
                syncOwnerTokenIdentifier: owner
            )
            context.insert(exercise)
            try recorder.recordUpdate(
                entityKind: .exercise,
                entityID: exercise.id,
                ownerTokenIdentifier: owner,
                context: context,
                now: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let retryExercise = Exercise(
            name: "Durable Retry",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Back",
            syncOwnerTokenIdentifier: owner
        )
        let failedEntry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: retryExercise.id,
            operation: .update,
            status: .failed,
            ownerTokenIdentifier: owner,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            lastAttemptAt: Date(timeIntervalSince1970: 100),
            attemptCount: 1,
            lastErrorMessage: "previous durable failure"
        )
        context.insert(retryExercise)
        context.insert(failedEntry)
        try context.save()

        let client = FakeSyncClient()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.recordFailureForTesting(
            message: "Cloud sync could not finish.",
            reason: .failedOutboxPush
        )

        scheduler.retrySync()
        try await waitUntil {
            (scheduler.lastSyncedAt != nil || client.upsertedExercises.count >= 50)
                && !scheduler.isSyncing
        }

        XCTAssertNotNil(scheduler.lastSyncedAt)
        XCTAssertNil(scheduler.lastFailure)
        XCTAssertEqual(client.upsertedExercises.count, 52)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testPostPushPullInterruptionClearsResolvedIncompletePullFailure() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
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
        client.onUpsertExercise = { _ in
            client.fetchError = URLError(.timedOut)
        }
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.recordFailureForTesting(
            message: "Cloud sync could not finish.",
            reason: .incompleteRemotePull
        )

        scheduler.retrySync()
        try await waitUntil {
            scheduler.lastTransientCondition != nil && !scheduler.isSyncing
        }

        XCTAssertNil(scheduler.lastFailure)
        XCTAssertNil(scheduler.lastSyncedAt)
        XCTAssertEqual(scheduler.lastTransientCondition?.errorCode, .requestTimedOut)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testInitialPullInterruptionPreservesIncompletePullFailure() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        client.fetchError = URLError(.timedOut)
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        scheduler.recordFailureForTesting(
            message: "Cloud sync could not finish.",
            reason: .incompleteRemotePull
        )

        scheduler.retrySync()
        try await waitUntil {
            scheduler.lastTransientCondition != nil && !scheduler.isSyncing
        }

        XCTAssertEqual(scheduler.lastFailure?.reason, .incompleteRemotePull)
        XCTAssertEqual(scheduler.lastTransientCondition?.errorCode, .requestTimedOut)
    }

    func testIncompleteInitialPullSurvivesPostPushPullInterruption() async throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
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
        client.fetchResponses = [Self.incompleteRemotePullResponse]
        client.onUpsertExercise = { _ in
            client.fetchError = URLError(.timedOut)
        }
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: context
        )
        scheduler.currentOwnerTokenIdentifier = owner
        scheduler.recordFailureForTesting(
            message: "Cloud sync could not finish.",
            reason: .incompleteRemotePull
        )

        scheduler.retrySync()
        try await waitUntil {
            scheduler.lastTransientCondition != nil && !scheduler.isSyncing
        }

        XCTAssertEqual(scheduler.lastFailure?.reason, .incompleteRemotePull)
        XCTAssertEqual(scheduler.lastTransientCondition?.errorCode, .requestTimedOut)
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

    func testUnfinishedSyncWorkIncludesPendingEntryForCurrentOwner() throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(),
            operation: .update,
            ownerTokenIdentifier: owner,
            now: Date(timeIntervalSince1970: 100)
        ))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = owner

        XCTAssertTrue(scheduler.hasUnfinishedSyncWork)
    }

    func testUnfinishedSyncWorkIncludesFailedInFlightAndOwnerlessV1Entries() throws {
        let owner = "issuer|owner_a"
        for (status, entryOwner) in [
            (SyncOutboxStatus.failed, owner as String?),
            (.inFlight, owner),
            (.pending, nil),
        ] {
            let container = try SwiftDataTestSupport.makeInMemoryContainer()
            let context = container.mainContext
            let entityID = UUID()
            if entryOwner == nil {
                context.insert(Exercise(
                    id: entityID,
                    name: "Unclaimed Press",
                    category: .strength,
                    equipment: .barbell,
                    primaryMuscleGroup: .chest
                ))
            }
            context.insert(SyncOutboxEntry(
                entityKind: .exercise,
                entityID: entityID,
                operation: .update,
                status: status,
                ownerTokenIdentifier: entryOwner,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            ))
            try context.save()
            let scheduler = SyncScheduler(modelContext: context)
            scheduler.currentOwnerTokenIdentifier = owner

            XCTAssertTrue(scheduler.hasUnfinishedSyncWork, "Expected \(status) work for \(String(describing: entryOwner))")
        }
    }

    func testUnfinishedSyncWorkExcludesCompletedExcludedAndOtherOwnerEntries() throws {
        let owner = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(),
            operation: .update,
            status: .completed,
            ownerTokenIdentifier: owner,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        ))
        context.insert(SyncOutboxEntry(
            entityKind: .workoutTemplate,
            entityID: UUID(),
            operation: .update,
            ownerTokenIdentifier: owner,
            now: Date(timeIntervalSince1970: 100)
        ))
        context.insert(SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(),
            operation: .update,
            ownerTokenIdentifier: "issuer|owner_b",
            now: Date(timeIntervalSince1970: 100)
        ))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = owner

        XCTAssertFalse(scheduler.hasUnfinishedSyncWork)
    }

    func testUnfinishedSyncWorkIncludesQueuedSchedulerRequest() {
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        scheduler.pauseCloudSync()
        scheduler.requestSync()

        XCTAssertTrue(scheduler.hasUnfinishedSyncWork)
    }

    func testUnfinishedSyncWorkExcludesUnclaimableOwnerlessEntry() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(),
            operation: .update,
            ownerTokenIdentifier: nil,
            now: Date(timeIntervalSince1970: 100)
        ))
        try context.save()
        let scheduler = SyncScheduler(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        XCTAssertFalse(scheduler.hasUnfinishedSyncWork)
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

    private static var incompleteRemotePullResponse: SyncFetchChangesResponse {
        SyncFetchChangesResponse(
            userSettings: [],
            exercises: [],
            workoutSessions: [],
            loggedExercises: [
                LoggedExerciseSyncRecord(
                    clientId: "00000000-0000-0000-0000-000000006701",
                    createdAt: 1,
                    updatedAt: 2,
                    deletedAt: nil,
                    serverUpdatedAt: 50,
                    sessionClientId: "00000000-0000-0000-0000-000000006702",
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
            cursors: SyncChangeCursors(
                userSettings: 0,
                exercises: 0,
                workoutSessions: 0,
                loggedExercises: 50,
                loggedSets: 0
            ),
            hasMore: SyncHasMore(
                userSettings: false,
                exercises: false,
                loggedExercises: true
            )
        )
    }
}
