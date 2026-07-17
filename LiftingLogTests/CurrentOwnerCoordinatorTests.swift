import SwiftData
import XCTest
@testable import LiftingLog

private let ownerA = "issuer|owner_a"
private let ownerB = "issuer|owner_b"

@MainActor
final class CurrentOwnerCoordinatorTests: XCTestCase {
    func testStartWithoutActiveClerkSessionEntersLocalOnlyMode() async throws {
        let harness = try CurrentOwnerCoordinatorHarness(
            clerkOwner: nil,
            schedulerMode: .unconfigured
        )

        harness.coordinator.start()
        try await waitUntil { harness.coordinator.state == .localOnly }

        XCTAssertNil(harness.syncScheduler.currentOwnerTokenIdentifier)
        harness.finish()
    }

    func testRepeatedStartOnlyObservesAndRecoversAuthenticationOnce() async throws {
        let harness = try CurrentOwnerCoordinatorHarness(
            schedulerMode: .unconfigured
        )

        harness.coordinator.start()
        harness.coordinator.start()
        harness.coordinator.start()
        try await waitUntil {
            harness.authenticationClient.observeAuthenticationStatesCallCount == 1
                && harness.authenticationClient.loginFromCacheCallCount == 1
        }

        XCTAssertEqual(harness.authenticationClient.observeAuthenticationStatesCallCount, 1)
        XCTAssertEqual(harness.authenticationClient.loginFromCacheCallCount, 1)
        harness.finish()
    }

    func testStartWithActiveClerkSessionShowsOwnerDataWhileConvexAuthenticationResolves() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()

        harness.coordinator.start()
        try await waitUntil {
            harness.coordinator.state == .resolving(ownerTokenIdentifier: ownerA)
        }
        harness.syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.syncScheduler.currentOwnerTokenIdentifier, ownerA)
        XCTAssertTrue(
            harness.syncClient.fetchRequests.isEmpty,
            "Local owner access must not authorize cloud sync while Convex authentication is unresolved."
        )
        harness.finish()
    }

    func testMatchingConvexAuthenticationActivatesCloudSyncForTheClerkOwner() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()

        harness.coordinator.start()
        try await waitUntil {
            harness.coordinator.state == .resolving(ownerTokenIdentifier: ownerA)
        }
        harness.sendAuthenticated(as: ownerA)
        try await waitUntil {
            harness.coordinator.state == .active(ownerTokenIdentifier: ownerA)
        }
        try await waitUntil { harness.syncScheduler.lastSyncedAt != nil }

        XCTAssertEqual(harness.syncScheduler.currentOwnerTokenIdentifier, ownerA)
        XCTAssertEqual(harness.syncScheduler.requestCount, 1)
        harness.finish()
    }

    func testMismatchedConvexAuthenticationKeepsClerkOwnerVisibleAndPausesSync() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()

        harness.coordinator.start()
        try await waitUntil {
            harness.coordinator.state == .resolving(ownerTokenIdentifier: ownerA)
        }
        harness.sendAuthenticated(as: ownerB)
        try await waitUntil { harness.authenticationClient.logoutCallCount == 1 }
        harness.syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            harness.coordinator.state,
            .resolving(ownerTokenIdentifier: ownerA)
        )
        XCTAssertEqual(harness.syncScheduler.currentOwnerTokenIdentifier, ownerA)
        XCTAssertTrue(harness.syncClient.fetchRequests.isEmpty)
        harness.finish()
    }

    func testMismatchedConvexAuthenticationMovesAnActiveOwnerBackToResolving() async throws {
        let harness = try CurrentOwnerCoordinatorHarness(
            schedulerMode: .unconfigured
        )

        harness.coordinator.start()
        try await waitUntil { harness.authenticationClient.loginFromCacheCallCount == 1 }
        harness.sendAuthenticated(as: ownerA)
        try await waitUntil {
            harness.coordinator.state == .active(ownerTokenIdentifier: ownerA)
        }

        harness.sendAuthenticated(as: ownerB)
        try await waitUntil { harness.authenticationClient.logoutCallCount == 1 }

        XCTAssertEqual(
            harness.coordinator.state,
            .resolving(ownerTokenIdentifier: ownerA)
        )
        XCTAssertEqual(harness.syncScheduler.currentOwnerTokenIdentifier, ownerA)
        XCTAssertFalse(harness.syncScheduler.isCloudSyncAuthorized)
        harness.finish()
    }

    func testOfflineOwnerEditStaysOwnedAndQueuedWhileConvexAuthenticationIsUnresolved() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()

        harness.coordinator.start()
        try await waitUntil {
            harness.coordinator.state == .resolving(ownerTokenIdentifier: ownerA)
        }
        let workout = WorkoutSession(
            title: "Edited offline",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: harness.syncScheduler.currentOwnerTokenIdentifier
        )
        harness.context.insert(workout)
        try SyncOutboxRecorder().recordCreate(
            entityKind: .workoutSession,
            entityID: workout.id,
            ownerTokenIdentifier: harness.syncScheduler.currentOwnerTokenIdentifier,
            context: harness.context,
            now: Date(timeIntervalSince1970: 300)
        )
        try harness.context.save()
        harness.syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        let outboxEntry = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<SyncOutboxEntry>()).first {
                $0.entityID == workout.id
            }
        )
        XCTAssertEqual(workout.syncOwnerTokenIdentifier, ownerA)
        XCTAssertEqual(outboxEntry.ownerTokenIdentifier, ownerA)
        XCTAssertEqual(outboxEntry.status, .pending)
        XCTAssertTrue(harness.syncClient.fetchRequests.isEmpty)
        harness.finish()
    }

    func testClerkAccountSwitchHidesThePreviousOwnerBeforeConvexAuthenticationResolves() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()

        harness.coordinator.start()
        try await waitUntil {
            harness.coordinator.state == .resolving(ownerTokenIdentifier: ownerA)
        }
        harness.setClerkOwner(ownerB, sessionIdentifier: "session_b")
        harness.authenticationClient.sendAuthenticationState(.loading)
        try await waitUntil {
            harness.coordinator.state == .resolving(ownerTokenIdentifier: ownerB)
        }
        harness.syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.syncScheduler.currentOwnerTokenIdentifier, ownerB)
        XCTAssertTrue(harness.syncClient.fetchRequests.isEmpty)
        harness.finish()
    }

    func testConfirmedSignOutHidesOwnedDataWithoutDeletingIt() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()
        let workout = WorkoutSession(
            title: "Kept on device",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: ownerA
        )
        let unclaimedWorkout = WorkoutSession(
            title: "Still available locally",
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400),
            status: .completed,
            source: .blank
        )
        harness.context.insert(workout)
        harness.context.insert(unclaimedWorkout)
        try harness.context.save()

        harness.coordinator.start()
        try await waitUntil {
            harness.coordinator.state == .resolving(ownerTokenIdentifier: ownerA)
        }
        harness.setClerkOwner(nil)
        harness.authenticationClient.sendAuthenticationState(.unauthenticated)
        try await waitUntil { harness.coordinator.state == .localOnly }
        harness.syncScheduler.requestSync()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(harness.syncScheduler.currentOwnerTokenIdentifier)
        XCTAssertFalse(harness.syncScheduler.isCloudSyncAuthorized)
        XCTAssertNotNil(
            try harness.context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == workout.id },
            "Signing out changes visibility; account deletion is the only flow that removes stored owner data."
        )
        let retainedUnclaimedWorkout = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<WorkoutSession>()).first {
                $0.id == unclaimedWorkout.id
            }
        )
        XCTAssertNil(retainedUnclaimedWorkout.syncOwnerTokenIdentifier)
        XCTAssertTrue(harness.syncClient.fetchRequests.isEmpty)
        harness.finish()
    }

    func testStartupRecoversConvexAuthenticationForARestoredClerkSession() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()
        harness.succeedLogin(as: ownerA)

        harness.coordinator.start()
        try await waitUntil {
            harness.coordinator.state == .active(ownerTokenIdentifier: ownerA)
        }
        try await waitUntil { harness.syncScheduler.lastSyncedAt != nil }

        XCTAssertEqual(harness.authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(harness.syncScheduler.requestCount, 1)
        harness.finish()
    }

    func testManualRetryRecoversAfterStartupAuthenticationFails() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()

        harness.coordinator.start()
        try await waitUntil { harness.authenticationClient.loginFromCacheCallCount == 1 }
        XCTAssertEqual(
            harness.coordinator.state,
            .resolving(ownerTokenIdentifier: ownerA)
        )

        harness.succeedLogin(as: ownerA)
        harness.coordinator.retrySync()
        try await waitUntil {
            harness.coordinator.state == .active(ownerTokenIdentifier: ownerA)
                && harness.syncScheduler.lastSyncedAt != nil
        }

        XCTAssertEqual(harness.authenticationClient.loginFromCacheCallCount, 2)
        harness.finish()
    }

    func testForegroundRecoversAfterStartupAuthenticationFails() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()

        harness.coordinator.start()
        try await waitUntil { harness.authenticationClient.loginFromCacheCallCount == 1 }
        harness.succeedLogin(as: ownerA)
        harness.coordinator.appDidEnterForeground()
        try await waitUntil {
            harness.coordinator.state == .active(ownerTokenIdentifier: ownerA)
                && harness.syncScheduler.lastSyncedAt != nil
        }

        XCTAssertEqual(harness.authenticationClient.loginFromCacheCallCount, 2)
        XCTAssertEqual(harness.syncScheduler.requestCount, 1)
        harness.finish()
    }

    func testOverlappingForegroundAndManualRetryShareOneRecoveryAndSync() async throws {
        let harness = try CurrentOwnerCoordinatorHarness()

        harness.coordinator.start()
        try await waitUntil { harness.authenticationClient.loginFromCacheCallCount == 1 }
        harness.succeedLogin(as: ownerA)
        harness.authenticationClient.waitsForLoginResume = true
        harness.coordinator.appDidEnterForeground()
        try await waitUntil { harness.authenticationClient.hasPendingLogin }
        harness.coordinator.retrySync()
        await Task.yield()

        XCTAssertEqual(harness.authenticationClient.loginFromCacheCallCount, 2)
        XCTAssertEqual(harness.syncScheduler.requestCount, 0)

        harness.authenticationClient.resumeLogin()
        try await waitUntil {
            harness.coordinator.state == .active(ownerTokenIdentifier: ownerA)
                && harness.syncScheduler.lastSyncedAt != nil
        }

        XCTAssertEqual(harness.authenticationClient.loginFromCacheCallCount, 2)
        XCTAssertEqual(harness.syncScheduler.requestCount, 1)
        harness.finish()
    }

    func testFirstSignInAdoptsAndUploadsAnUnclaimedLocalWorkout() async throws {
        let harness = try CurrentOwnerCoordinatorHarness(clerkOwner: nil)
        let workout = WorkoutSession(
            title: "Made before sign in",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank
        )
        harness.context.insert(workout)
        try harness.context.save()

        harness.coordinator.start()
        try await waitUntil { harness.coordinator.state == .localOnly }
        harness.setClerkOwner(ownerA)
        harness.sendAuthenticated(as: ownerA)
        try await waitUntil { harness.syncScheduler.lastSyncedAt != nil }

        XCTAssertEqual(workout.syncOwnerTokenIdentifier, ownerA)
        XCTAssertTrue(
            harness.syncClient.upsertedWorkoutSessions.contains(where: { payload in
                payload.clientId == workout.id.uuidString.lowercased()
            })
        )
        harness.finish()
    }

    func testFixedOwnerUITestModeKeepsItsOwnerAndRoutesRetryDirectlyToTheScheduler() async throws {
        let harness = try CurrentOwnerCoordinatorHarness(
            clerkOwner: nil,
            schedulerMode: .unconfigured,
            startupMode: .fixedOwner("issuer|ui_owner")
        )

        harness.coordinator.start()
        harness.coordinator.retrySync()
        try await waitUntil { harness.syncScheduler.requestCount == 1 }

        XCTAssertEqual(
            harness.coordinator.state,
            .active(ownerTokenIdentifier: "issuer|ui_owner")
        )
        XCTAssertEqual(harness.syncScheduler.currentOwnerTokenIdentifier, "issuer|ui_owner")
        XCTAssertEqual(harness.authenticationClient.loginFromCacheCallCount, 0)
        harness.finish()
    }

    func testRestoreCachedOwnerUITestModeWithoutSubjectDoesNotRestoreAnOwner() throws {
        let harness = try CurrentOwnerCoordinatorHarness(
            clerkOwner: nil,
            cachedOwner: ownerA,
            schedulerMode: .unconfigured,
            startupMode: .restoreCachedOwner(matchingSubject: nil)
        )

        harness.coordinator.start()

        XCTAssertEqual(
            harness.coordinator.state,
            .resolving(ownerTokenIdentifier: nil)
        )
        XCTAssertNil(harness.syncScheduler.currentOwnerTokenIdentifier)
        harness.finish()
    }

    func testEarlyConvexUnauthenticatedStateWaitsForClerkBeforeTreatingItAsSignOut() async throws {
        let harness = try CurrentOwnerCoordinatorHarness(
            clerkOwner: nil,
            schedulerMode: .unconfigured,
            clerkWaitsUntilResumed: true
        )
        harness.syncScheduler.currentOwnerTokenIdentifier = ownerA

        harness.coordinator.start()
        harness.authenticationClient.sendAuthenticationState(.unauthenticated)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            harness.syncScheduler.currentOwnerTokenIdentifier,
            ownerA,
            "Convex must not clear local owner access while Clerk is still restoring its session."
        )

        harness.setClerkOwner(ownerA)
        harness.clerkSessionProvider.resumeLoading()
        try await waitUntil {
            harness.coordinator.state == .resolving(ownerTokenIdentifier: ownerA)
        }
        harness.finish()
    }

    func testMalformedConvexAuthenticationFailsClosedWithoutHidingClerkOwnerData() async throws {
        let harness = try CurrentOwnerCoordinatorHarness(
            schedulerMode: .unconfigured
        )

        harness.coordinator.start()
        try await waitUntil { harness.authenticationClient.loginFromCacheCallCount == 1 }
        harness.sendAuthenticated(as: ownerA)
        try await waitUntil {
            harness.coordinator.state == .active(ownerTokenIdentifier: ownerA)
        }

        harness.authenticationClient.sendAuthenticationState(.authenticated(token: "not-a-jwt"))
        try await waitUntil { harness.authenticationClient.logoutCallCount == 1 }

        XCTAssertEqual(
            harness.coordinator.state,
            .resolving(ownerTokenIdentifier: ownerA)
        )
        XCTAssertEqual(harness.syncScheduler.currentOwnerTokenIdentifier, ownerA)
        XCTAssertFalse(harness.syncScheduler.isCloudSyncAuthorized)
        harness.finish()
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

private enum TestSchedulerMode {
    case configured
    case unconfigured
}

@MainActor
private final class CurrentOwnerCoordinatorHarness {
    let container: ModelContainer?
    let syncClient: FakeSyncClient
    let syncScheduler: SyncScheduler
    let clerkSessionProvider: TestCurrentOwnerClerkSessionProvider
    let authenticationClient: TestCurrentOwnerAuthenticationClient
    let coordinator: CurrentOwnerCoordinator

    var context: ModelContext {
        guard let container else {
            preconditionFailure("This scenario requires a configured scheduler")
        }
        return container.mainContext
    }

    init(
        clerkOwner: String? = ownerA,
        sessionIdentifier: String = "session_a",
        cachedOwner: String? = nil,
        schedulerMode: TestSchedulerMode = .configured,
        clerkWaitsUntilResumed: Bool = false,
        startupMode: CurrentOwnerCoordinator.StartupMode = .live
    ) throws {
        syncClient = FakeSyncClient()
        let ownerStore = Self.makeOwnerStore()
        ownerStore.ownerTokenIdentifier = cachedOwner
        switch schedulerMode {
        case .configured:
            let container = try SwiftDataTestSupport.makeInMemoryContainer()
            self.container = container
            syncScheduler = SyncScheduler(
                coordinator: SyncCoordinator(client: syncClient),
                modelContext: container.mainContext,
                lastKnownOwnerTokenStore: ownerStore
            )
        case .unconfigured:
            container = nil
            syncScheduler = SyncScheduler(lastKnownOwnerTokenStore: ownerStore)
        }

        clerkSessionProvider = TestCurrentOwnerClerkSessionProvider(
            state: Self.clerkState(owner: clerkOwner, sessionIdentifier: sessionIdentifier),
            waitsUntilResumed: clerkWaitsUntilResumed
        )
        authenticationClient = TestCurrentOwnerAuthenticationClient()
        coordinator = CurrentOwnerCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            clerkSessionProvider: clerkSessionProvider,
            startupMode: startupMode
        )
    }

    func setClerkOwner(_ owner: String?, sessionIdentifier: String = "session_a") {
        clerkSessionProvider.state = Self.clerkState(
            owner: owner,
            sessionIdentifier: sessionIdentifier
        )
    }

    func sendAuthenticated(as owner: String) {
        authenticationClient.sendAuthenticationState(
            .authenticated(token: Self.makeJWT(ownerTokenIdentifier: owner))
        )
    }

    func succeedLogin(as owner: String) {
        authenticationClient.loginResult = .success(
            Self.makeJWT(ownerTokenIdentifier: owner)
        )
    }

    func finish() {
        authenticationClient.finishAuthenticationStates()
    }

    private static func clerkState(
        owner: String?,
        sessionIdentifier: String
    ) -> CurrentOwnerClerkSessionState {
        CurrentOwnerClerkSessionState(
            hasActiveSession: owner != nil,
            sessionIdentifier: owner == nil ? nil : sessionIdentifier,
            ownerTokenIdentifier: owner
        )
    }

    private static func makeOwnerStore() -> LastKnownSyncOwnerTokenStore {
        let suiteName = "CurrentOwnerCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LastKnownSyncOwnerTokenStore(userDefaults: defaults)
    }

    private static func makeJWT(ownerTokenIdentifier: String) -> String {
        let parts = ownerTokenIdentifier.split(separator: "|", maxSplits: 1).map(String.init)
        precondition(parts.count == 2, "Test owners must use the issuer|subject format")
        let header = Data("{}".utf8).base64URLEncodedString()
        let payload = Data(#"{"iss":"\#(parts[0])","sub":"\#(parts[1])"}"#.utf8)
            .base64URLEncodedString()
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
