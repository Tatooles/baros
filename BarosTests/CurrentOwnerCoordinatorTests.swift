import SwiftData
import XCTest
@testable import Baros

@MainActor
final class CurrentOwnerCoordinatorTests: XCTestCase {
    func testStartWithoutActiveClerkSessionEntersLocalOnlyMode() async throws {
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(hasActiveSession: false)
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let syncScheduler = SyncScheduler(lastKnownOwnerTokenStore: makeOwnerStore())
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil { coordinator.state == .localOnly }

        XCTAssertNil(syncScheduler.currentOwnerTokenIdentifier)
        authenticationClient.finishAuthenticationStates()
    }

    func testRepeatedStartOnlyObservesAndRecoversAuthenticationOnce() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: SyncScheduler(lastKnownOwnerTokenStore: makeOwnerStore()),
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        coordinator.start()
        coordinator.start()
        try await waitUntil {
            authenticationClient.observeAuthenticationStatesCallCount == 1
                && authenticationClient.loginFromCacheCallCount == 1
        }

        XCTAssertEqual(authenticationClient.observeAuthenticationStatesCallCount, 1)
        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        authenticationClient.finishAuthenticationStates()
    }

    func testStartWithActiveClerkSessionShowsOwnerDataWhileConvexAuthenticationResolves() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let syncClient = FakeSyncClient()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: syncClient),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil {
            coordinator.state == .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        }
        syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(syncScheduler.currentOwnerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertTrue(
            syncClient.fetchRequests.isEmpty,
            "Local owner access must not authorize cloud sync while Convex authentication is unresolved."
        )
        authenticationClient.finishAuthenticationStates()
    }

    func testMatchingConvexAuthenticationActivatesCloudSyncForTheClerkOwner() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let syncClient = FakeSyncClient()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: syncClient),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil {
            coordinator.state == .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        }
        authenticationClient.sendAuthenticationState(
            .authenticated(token: makeJWT(issuer: "issuer", subject: "owner_a"))
        )
        try await waitUntil {
            coordinator.state == .active(ownerTokenIdentifier: ownerTokenIdentifier)
        }
        try await waitUntil { syncScheduler.lastSyncedAt != nil }

        XCTAssertEqual(syncScheduler.currentOwnerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertEqual(syncScheduler.requestCount, 1)
        authenticationClient.finishAuthenticationStates()
    }

    func testMismatchedConvexAuthenticationKeepsClerkOwnerVisibleAndPausesSync() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let syncClient = FakeSyncClient()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: syncClient),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil {
            coordinator.state == .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        }
        authenticationClient.sendAuthenticationState(
            .authenticated(token: makeJWT(issuer: "issuer", subject: "owner_b"))
        )
        try await waitUntil { authenticationClient.logoutCallCount == 1 }
        syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            coordinator.state,
            .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        )
        XCTAssertEqual(syncScheduler.currentOwnerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertTrue(syncClient.fetchRequests.isEmpty)
        authenticationClient.finishAuthenticationStates()
    }

    func testMismatchedConvexAuthenticationMovesAnActiveOwnerBackToResolving() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let syncScheduler = SyncScheduler(lastKnownOwnerTokenStore: makeOwnerStore())
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil { authenticationClient.loginFromCacheCallCount == 1 }
        authenticationClient.sendAuthenticationState(
            .authenticated(token: makeJWT(issuer: "issuer", subject: "owner_a"))
        )
        try await waitUntil {
            coordinator.state == .active(ownerTokenIdentifier: ownerTokenIdentifier)
        }

        authenticationClient.sendAuthenticationState(
            .authenticated(token: makeJWT(issuer: "issuer", subject: "owner_b"))
        )
        try await waitUntil { authenticationClient.logoutCallCount == 1 }

        XCTAssertEqual(
            coordinator.state,
            .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        )
        XCTAssertEqual(syncScheduler.currentOwnerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertFalse(syncScheduler.isCloudSyncAuthorized)
        authenticationClient.finishAuthenticationStates()
    }

    func testOfflineOwnerEditStaysOwnedAndQueuedWhileConvexAuthenticationIsUnresolved() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let syncClient = FakeSyncClient()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: syncClient),
            modelContext: context,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: TestCurrentOwnerClerkSessionProvider(
                state: .init(
                    hasActiveSession: true,
                    sessionIdentifier: "session_a",
                    ownerTokenIdentifier: ownerTokenIdentifier
                )
            )
        )

        coordinator.start()
        try await waitUntil {
            coordinator.state == .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        }
        let workout = WorkoutSession(
            title: "Edited offline",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        )
        context.insert(workout)
        try SyncOutboxRecorder().recordCreate(
            entityKind: .workoutSession,
            entityID: workout.id,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            context: context,
            now: Date(timeIntervalSince1970: 300)
        )
        try context.save()
        syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        let outboxEntry = try XCTUnwrap(
            context.fetch(FetchDescriptor<SyncOutboxEntry>()).first {
                $0.entityID == workout.id
            }
        )
        XCTAssertEqual(workout.syncOwnerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertEqual(outboxEntry.ownerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertEqual(outboxEntry.status, .pending)
        XCTAssertTrue(syncClient.fetchRequests.isEmpty)
        authenticationClient.finishAuthenticationStates()
    }

    func testClerkAccountSwitchHidesThePreviousOwnerBeforeConvexAuthenticationResolves() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let syncClient = FakeSyncClient()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: syncClient),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: "issuer|owner_a"
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil {
            coordinator.state == .resolving(ownerTokenIdentifier: "issuer|owner_a")
        }
        clerkSessionProvider.state = .init(
            hasActiveSession: true,
            sessionIdentifier: "session_b",
            ownerTokenIdentifier: "issuer|owner_b"
        )
        authenticationClient.sendAuthenticationState(.loading)
        try await waitUntil {
            coordinator.state == .resolving(ownerTokenIdentifier: "issuer|owner_b")
        }
        syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(syncScheduler.currentOwnerTokenIdentifier, "issuer|owner_b")
        XCTAssertTrue(syncClient.fetchRequests.isEmpty)
        authenticationClient.finishAuthenticationStates()
    }

    func testConfirmedSignOutHidesOwnedDataWithoutDeletingIt() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let workout = WorkoutSession(
            title: "Kept on device",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let unclaimedWorkout = WorkoutSession(
            title: "Still available locally",
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400),
            status: .completed,
            source: .blank
        )
        context.insert(workout)
        context.insert(unclaimedWorkout)
        try context.save()
        let syncClient = FakeSyncClient()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: syncClient),
            modelContext: context,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil {
            coordinator.state == .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        }
        clerkSessionProvider.state = .init(hasActiveSession: false)
        authenticationClient.sendAuthenticationState(.unauthenticated)
        try await waitUntil { coordinator.state == .localOnly }
        syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(syncScheduler.currentOwnerTokenIdentifier)
        XCTAssertFalse(syncScheduler.isCloudSyncAuthorized)
        XCTAssertNotNil(
            try context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == workout.id },
            "Signing out changes visibility; account deletion is the only flow that removes stored owner data."
        )
        let retainedUnclaimedWorkout = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>()).first {
                $0.id == unclaimedWorkout.id
            }
        )
        XCTAssertNil(retainedUnclaimedWorkout.syncOwnerTokenIdentifier)
        XCTAssertTrue(syncClient.fetchRequests.isEmpty)
        authenticationClient.finishAuthenticationStates()
    }

    func testStartupRecoversConvexAuthenticationForARestoredClerkSession() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let syncClient = FakeSyncClient()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: syncClient),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient(
            loginResult: .success(makeJWT(issuer: "issuer", subject: "owner_a"))
        )
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil {
            coordinator.state == .active(ownerTokenIdentifier: ownerTokenIdentifier)
        }
        try await waitUntil { syncScheduler.lastSyncedAt != nil }

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(syncScheduler.requestCount, 1)
        authenticationClient.finishAuthenticationStates()
    }

    func testManualRetryRecoversAfterStartupAuthenticationFails() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil { authenticationClient.loginFromCacheCallCount == 1 }
        XCTAssertEqual(
            coordinator.state,
            .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        )

        authenticationClient.loginResult = .success(
            makeJWT(issuer: "issuer", subject: "owner_a")
        )
        coordinator.retrySync()
        try await waitUntil {
            coordinator.state == .active(ownerTokenIdentifier: ownerTokenIdentifier)
                && syncScheduler.lastSyncedAt != nil
        }

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 2)
        authenticationClient.finishAuthenticationStates()
    }

    func testForegroundRecoversAfterStartupAuthenticationFails() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: TestCurrentOwnerClerkSessionProvider(
                state: .init(
                    hasActiveSession: true,
                    sessionIdentifier: "session_a",
                    ownerTokenIdentifier: ownerTokenIdentifier
                )
            )
        )

        coordinator.start()
        try await waitUntil { authenticationClient.loginFromCacheCallCount == 1 }
        authenticationClient.loginResult = .success(
            makeJWT(issuer: "issuer", subject: "owner_a")
        )
        coordinator.appDidEnterForeground()
        try await waitUntil {
            coordinator.state == .active(ownerTokenIdentifier: ownerTokenIdentifier)
                && syncScheduler.lastSyncedAt != nil
        }

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 2)
        XCTAssertEqual(syncScheduler.requestCount, 1)
        authenticationClient.finishAuthenticationStates()
    }

    func testOverlappingForegroundAndManualRetryShareOneRecoveryAndSync() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: TestCurrentOwnerClerkSessionProvider(
                state: .init(
                    hasActiveSession: true,
                    sessionIdentifier: "session_a",
                    ownerTokenIdentifier: ownerTokenIdentifier
                )
            )
        )

        coordinator.start()
        try await waitUntil { authenticationClient.loginFromCacheCallCount == 1 }
        authenticationClient.loginResult = .success(
            makeJWT(issuer: "issuer", subject: "owner_a")
        )
        authenticationClient.waitsForLoginResume = true
        coordinator.appDidEnterForeground()
        try await waitUntil { authenticationClient.hasPendingLogin }
        coordinator.retrySync()
        await Task.yield()

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 2)
        XCTAssertEqual(syncScheduler.requestCount, 0)

        authenticationClient.resumeLogin()
        try await waitUntil {
            coordinator.state == .active(ownerTokenIdentifier: ownerTokenIdentifier)
                && syncScheduler.lastSyncedAt != nil
        }

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 2)
        XCTAssertEqual(syncScheduler.requestCount, 1)
        authenticationClient.finishAuthenticationStates()
    }

    func testFirstSignInAdoptsAndUploadsAnUnclaimedLocalWorkout() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let workout = WorkoutSession(
            title: "Made before sign in",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank
        )
        context.insert(workout)
        try context.save()
        let syncClient = FakeSyncClient()
        let syncScheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: syncClient),
            modelContext: context,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(hasActiveSession: false)
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil { coordinator.state == .localOnly }
        clerkSessionProvider.state = .init(
            hasActiveSession: true,
            sessionIdentifier: "session_a",
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        authenticationClient.sendAuthenticationState(
            .authenticated(token: makeJWT(issuer: "issuer", subject: "owner_a"))
        )
        try await waitUntil { syncScheduler.lastSyncedAt != nil }

        XCTAssertEqual(workout.syncOwnerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertTrue(
            syncClient.upsertedWorkoutSessions.contains(where: { payload in
                payload.clientId == workout.id.uuidString.lowercased()
            })
        )
        authenticationClient.finishAuthenticationStates()
    }

    func testFixedOwnerUITestModeKeepsItsOwnerAndRoutesRetryDirectlyToTheScheduler() async throws {
        let syncScheduler = SyncScheduler(lastKnownOwnerTokenStore: makeOwnerStore())
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: TestCurrentOwnerClerkSessionProvider(
                state: .init(hasActiveSession: false)
            ),
            startupMode: .fixedOwner("issuer|ui_owner")
        )

        coordinator.start()
        coordinator.retrySync()
        try await waitUntil { syncScheduler.requestCount == 1 }

        XCTAssertEqual(
            coordinator.state,
            .active(ownerTokenIdentifier: "issuer|ui_owner")
        )
        XCTAssertEqual(syncScheduler.currentOwnerTokenIdentifier, "issuer|ui_owner")
        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 0)
        authenticationClient.finishAuthenticationStates()
    }

    func testEarlyConvexUnauthenticatedStateWaitsForClerkBeforeTreatingItAsSignOut() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let syncScheduler = SyncScheduler(lastKnownOwnerTokenStore: makeOwnerStore())
        syncScheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(hasActiveSession: false),
            waitsUntilResumed: true
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        authenticationClient.sendAuthenticationState(.unauthenticated)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            syncScheduler.currentOwnerTokenIdentifier,
            ownerTokenIdentifier,
            "Convex must not clear local owner access while Clerk is still restoring its session."
        )

        clerkSessionProvider.state = .init(
            hasActiveSession: true,
            sessionIdentifier: "session_a",
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        clerkSessionProvider.resumeLoading()
        try await waitUntil {
            coordinator.state == .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        }
        authenticationClient.finishAuthenticationStates()
    }

    func testMalformedConvexAuthenticationFailsClosedWithoutHidingClerkOwnerData() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let syncScheduler = SyncScheduler(lastKnownOwnerTokenStore: makeOwnerStore())
        let clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: .init(
                hasActiveSession: true,
                sessionIdentifier: "session_a",
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        )
        let authenticationClient = TestCurrentOwnerAuthenticationClient()
        let coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider
        )

        coordinator.start()
        try await waitUntil { authenticationClient.loginFromCacheCallCount == 1 }
        authenticationClient.sendAuthenticationState(
            .authenticated(token: makeJWT(issuer: "issuer", subject: "owner_a"))
        )
        try await waitUntil {
            coordinator.state == .active(ownerTokenIdentifier: ownerTokenIdentifier)
        }

        authenticationClient.sendAuthenticationState(.authenticated(token: "not-a-jwt"))
        try await waitUntil { authenticationClient.logoutCallCount == 1 }

        XCTAssertEqual(
            coordinator.state,
            .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
        )
        XCTAssertEqual(syncScheduler.currentOwnerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertFalse(syncScheduler.isCloudSyncAuthorized)
        authenticationClient.finishAuthenticationStates()
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
        let suiteName = "CurrentOwnerCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LastKnownSyncOwnerTokenStore(userDefaults: defaults)
    }

    private func makeJWT(issuer: String, subject: String) -> String {
        let header = Data("{}".utf8).base64URLEncodedString()
        let payload = Data(#"{"iss":"\#(issuer)","sub":"\#(subject)"}"#.utf8).base64URLEncodedString()
        return "\(header).\(payload).signature"
    }
}

@MainActor
private final class TestCurrentOwnerClerkSessionProvider: CurrentOwnerClerkSessionProviding {
    var state: CurrentOwnerClerkSessionState
    private let waitsUntilResumed: Bool
    private var loadContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        state: CurrentOwnerClerkSessionState,
        waitsUntilResumed: Bool = false
    ) {
        self.state = state
        self.waitsUntilResumed = waitsUntilResumed
    }

    func waitUntilLoaded() async {
        guard waitsUntilResumed else { return }
        await withCheckedContinuation { continuation in
            loadContinuations.append(continuation)
        }
    }

    func resumeLoading() {
        let continuations = loadContinuations
        loadContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
private final class TestCurrentOwnerAuthenticationClient: CurrentOwnerAuthenticationClient {
    private let states: AsyncStream<CurrentOwnerConvexAuthenticationState>
    private let continuation: AsyncStream<CurrentOwnerConvexAuthenticationState>.Continuation
    var loginResult: Result<String, Error>
    var waitsForLoginResume = false
    private var loginContinuations: [CheckedContinuation<Result<String, Error>, Never>] = []
    private(set) var observeAuthenticationStatesCallCount = 0
    private(set) var loginFromCacheCallCount = 0
    private(set) var logoutCallCount = 0

    var hasPendingLogin: Bool {
        !loginContinuations.isEmpty
    }

    init(loginResult: Result<String, Error> = .failure(TestAuthenticationError())) {
        let stream = AsyncStream<CurrentOwnerConvexAuthenticationState>.makeStream()
        states = stream.stream
        continuation = stream.continuation
        self.loginResult = loginResult
    }

    func observeAuthenticationStates(
        _ receive: @MainActor @escaping (CurrentOwnerConvexAuthenticationState) async -> Void
    ) async {
        observeAuthenticationStatesCallCount += 1
        for await state in states {
            await receive(state)
        }
    }

    func loginFromCache() async -> Result<String, Error> {
        loginFromCacheCallCount += 1
        if waitsForLoginResume {
            return await withCheckedContinuation { continuation in
                loginContinuations.append(continuation)
            }
        }
        return loginResult
    }

    func logout() async {
        logoutCallCount += 1
    }

    func finishAuthenticationStates() {
        continuation.finish()
    }

    func sendAuthenticationState(_ state: CurrentOwnerConvexAuthenticationState) {
        continuation.yield(state)
    }

    func resumeLogin() {
        guard !loginContinuations.isEmpty else { return }
        loginContinuations.removeFirst().resume(returning: loginResult)
    }
}

private struct TestAuthenticationError: Error {}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
