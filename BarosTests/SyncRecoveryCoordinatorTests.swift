import Foundation
import SwiftData
import XCTest
@testable import Baros

@MainActor
final class SyncRecoveryCoordinatorTests: XCTestCase {
    func testForegroundRecoveryAuthenticatesBeforeRequestingSync() async throws {
        let ownerTokenIdentifier = "https://clerk.auth.liftinglog.app|user_123"
        let harness = try makeConfiguredScheduler(ownerTokenIdentifier: ownerTokenIdentifier)
        let client = harness.client
        let scheduler = harness.scheduler
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "https://clerk.auth.liftinglog.app", subject: "user_123")),
            waitsForResume: true
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true },
            currentSessionIdentifier: { "session_a" }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertTrue(client.fetchRequests.isEmpty)
        let shouldActivateEarlyState = await coordinator.shouldActivateAuthenticatedState(
            ownerTokenIdentifier: ownerTokenIdentifier,
            sessionIdentifier: "session_a"
        )
        XCTAssertFalse(shouldActivateEarlyState)
        authenticationClient.resumeLogin()
        await recovery.value
        try await waitUntil { scheduler.lastSyncedAt != nil }

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, ownerTokenIdentifier)
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertFalse(client.fetchRequests.isEmpty)
    }

    func testRecoveryRejectsMismatchedAuthenticatedStateBeforeDeferral() async throws {
        let currentOwnerTokenIdentifier = "issuer|owner_b"
        let scheduler = SyncScheduler(
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = currentOwnerTokenIdentifier
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_b")),
            waitsForResume: true
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true },
            currentSessionIdentifier: { "session_b" },
            expectedOwnerTokenIdentifier: { currentOwnerTokenIdentifier }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }

        let shouldActivateMismatchedState = await coordinator.shouldActivateAuthenticatedState(
            ownerTokenIdentifier: "issuer|owner_a",
            sessionIdentifier: "session_b"
        )
        XCTAssertFalse(shouldActivateMismatchedState)
        XCTAssertEqual(authenticationClient.logoutCallCount, 1)
        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        let shouldActivateRecoveryState = await coordinator.shouldActivateAuthenticatedState(
            ownerTokenIdentifier: currentOwnerTokenIdentifier,
            sessionIdentifier: "session_b"
        )
        XCTAssertFalse(shouldActivateRecoveryState)

        authenticationClient.resumeLogin()
        await recovery.value
    }

    func testManualRetryAuthenticatesBeforeRequestingSync() async throws {
        let ownerTokenIdentifier = "https://clerk.auth.liftinglog.app|user_123"
        let harness = try makeConfiguredScheduler(ownerTokenIdentifier: ownerTokenIdentifier)
        let client = harness.client
        let scheduler = harness.scheduler
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "https://clerk.auth.liftinglog.app", subject: "user_123")),
            waitsForResume: true
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .manualRetry)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertTrue(client.fetchRequests.isEmpty)
        authenticationClient.resumeLogin()
        await recovery.value
        try await waitUntil { scheduler.lastSyncedAt != nil }

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertFalse(client.fetchRequests.isEmpty)
    }

    func testAuthenticationFailurePreservesExistingFailureAndOutbox() async throws {
        struct AuthenticationError: Error {}

        let ownerTokenIdentifier = "https://clerk.auth.liftinglog.app|user_123"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let workout = WorkoutSession(
            title: "Offline Workout",
            startedAt: Date(timeIntervalSince1970: 50),
            endedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let failedEntry = SyncOutboxEntry(
            entityKind: .workoutSession,
            entityID: workout.id,
            operation: .update,
            status: .failed,
            ownerTokenIdentifier: ownerTokenIdentifier,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            lastAttemptAt: Date(timeIntervalSince1970: 150),
            attemptCount: 1,
            lastErrorMessage: "Not authenticated"
        )
        context.insert(workout)
        context.insert(failedEntry)
        try context.save()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: context,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let failureDate = Date(timeIntervalSince1970: 300)
        scheduler.recordFailureForTesting(message: "Not authenticated", at: failureDate)
        let authenticationClient = StubSyncAuthenticationClient(
            result: .failure(AuthenticationError())
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true }
        )

        await coordinator.recoverAuthenticationAndRequestSync(for: .manualRetry)

        let remainingEntry = try XCTUnwrap(
            context.fetch(FetchDescriptor<SyncOutboxEntry>()).first { $0.id == failedEntry.id }
        )
        let remainingWorkout = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == workout.id }
        )
        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertEqual(scheduler.lastFailure?.message, "Not authenticated")
        XCTAssertEqual(scheduler.lastFailure?.occurredAt, failureDate)
        XCTAssertEqual(remainingEntry.status, SyncOutboxStatus.failed)
        XCTAssertEqual(remainingEntry.attemptCount, 1)
        XCTAssertEqual(remainingEntry.lastErrorMessage, "Not authenticated")
        XCTAssertEqual(remainingWorkout.title, "Offline Workout")
        XCTAssertEqual(remainingWorkout.syncOwnerTokenIdentifier, ownerTokenIdentifier)
    }

    func testRecoveryRejectsTokenForDifferentClerkOwner() async throws {
        let harness = try makeConfiguredScheduler(ownerTokenIdentifier: "issuer|owner_b")
        let client = harness.client
        let scheduler = harness.scheduler
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a"))
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true },
            currentSessionIdentifier: { "session_b" },
            expectedOwnerTokenIdentifier: { "issuer|owner_b" }
        )

        await coordinator.recoverAuthenticationAndRequestSync(for: .manualRetry)

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(authenticationClient.logoutCallCount, 1)
        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertTrue(client.fetchRequests.isEmpty)
    }

    func testRecoveryIsNoOpWithoutAnActiveSession() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a"))
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { false }
        )

        await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 0)
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
    }

    func testRecoveryIsNoOpDuringAccountDeletion() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        scheduler.beginDeletionMode()
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a"))
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true }
        )

        await coordinator.recoverAuthenticationAndRequestSync(for: .manualRetry)

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 0)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testRecoveryRechecksSessionAfterAuthenticationCompletes() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a")),
            waitsForResume: true
        )
        let sessionState = ActiveSessionState()
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { sessionState.isActive }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        sessionState.isActive = false
        authenticationClient.resumeLogin()
        await recovery.value

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, "issuer|owner_a")
    }

    func testRecoveryDoesNotResumeAfterAccountDeletionCompletes() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let client = FakeSyncClient()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a")),
            waitsForResume: true
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .manualRetry)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        scheduler.beginDeletionMode()
        scheduler.resetAfterDataDeletion()
        XCTAssertFalse(scheduler.isDeletionModeEnabled)
        authenticationClient.resumeLogin()
        await recovery.value

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertTrue(client.fetchRequests.isEmpty)
    }

    func testInvalidatedRecoveryDefersLateAuthenticatedStateForOriginalSession() async throws {
        let jwt = makeJWT(issuer: "issuer", subject: "owner_a")
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(jwt),
            waitsForResume: true
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true },
            currentSessionIdentifier: { "session_a" },
            expectedOwnerTokenIdentifier: { "issuer|owner_a" }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        scheduler.beginDeletionMode()
        scheduler.resetAfterDataDeletion()
        authenticationClient.resumeLogin()
        await recovery.value

        let shouldActivatePendingState = await coordinator.shouldActivateAuthenticatedState(
            ownerTokenIdentifier: "issuer|owner_a",
            sessionIdentifier: "session_a"
        )
        XCTAssertFalse(shouldActivatePendingState)
        let shouldActivateFollowingState = await coordinator.shouldActivateAuthenticatedState(
            ownerTokenIdentifier: "issuer|owner_a",
            sessionIdentifier: "session_a"
        )
        XCTAssertTrue(shouldActivateFollowingState)
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
    }

    func testPendingRecoveryAuthenticatedStateExpires() async throws {
        let ownerTokenIdentifier = "issuer|owner_a"
        let scheduler = SyncScheduler(lastKnownOwnerTokenStore: makeOwnerStore())
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a")),
            waitsForResume: true
        )
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true },
            currentSessionIdentifier: { "session_a" },
            expectedOwnerTokenIdentifier: { ownerTokenIdentifier },
            pendingAuthenticatedStateLifetime: 5,
            now: { clock.now }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        authenticationClient.resumeLogin()
        await recovery.value
        clock.now = clock.now.addingTimeInterval(6)

        let shouldActivateExpiredState = await coordinator.shouldActivateAuthenticatedState(
            ownerTokenIdentifier: ownerTokenIdentifier,
            sessionIdentifier: "session_a"
        )
        XCTAssertTrue(
            shouldActivateExpiredState,
            "A recovery callback that never arrives must not suppress a later authenticated state forever."
        )
    }

    func testInvalidatedRecoveryDoesNotDeferAuthenticatedStateForNewSession() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: FakeSyncClient()),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a")),
            waitsForResume: true
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true },
            currentSessionIdentifier: { "session_a" }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        scheduler.enterSignedOutMode()

        let shouldActivateNewSessionState = await coordinator.shouldActivateAuthenticatedState(
            ownerTokenIdentifier: "issuer|owner_b",
            sessionIdentifier: "session_b"
        )
        XCTAssertFalse(shouldActivateNewSessionState)
        authenticationClient.resumeLogin()
        await recovery.value
    }

    func testRecoveryDoesNotResumeForAChangedClerkSession() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let client = FakeSyncClient()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a")),
            waitsForResume: true
        )
        let sessionState = SessionIdentifierState(identifier: "session_a")
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true },
            currentSessionIdentifier: { sessionState.identifier }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        XCTAssertTrue(coordinator.willActiveRecoveryRequestSync)
        sessionState.identifier = "session_b"
        XCTAssertFalse(coordinator.willActiveRecoveryRequestSync)
        authenticationClient.resumeLogin()
        await recovery.value

        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertEqual(scheduler.currentOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertTrue(client.fetchRequests.isEmpty)
    }

    func testInvalidatedRecoveryAllowsFreshRetry() async throws {
        let harness = try makeConfiguredScheduler(ownerTokenIdentifier: "issuer|owner_a")
        let client = harness.client
        let scheduler = harness.scheduler
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a")),
            waitsForResume: true
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true },
            expectedOwnerTokenIdentifier: { "issuer|owner_a" }
        )

        let recovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        XCTAssertTrue(coordinator.willActiveRecoveryRequestSync)

        scheduler.enterSignedOutMode()

        XCTAssertFalse(coordinator.willActiveRecoveryRequestSync)
        let freshRetry = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .manualRetry)
        }
        try await waitUntil {
            authenticationClient.loginFromCacheCallCount == 2
                && authenticationClient.pendingLoginCount == 2
        }
        XCTAssertTrue(coordinator.willActiveRecoveryRequestSync)
        authenticationClient.resumeLogin()
        authenticationClient.resumeLogin()
        await recovery.value
        await freshRetry.value
        try await waitUntil { scheduler.lastSyncedAt != nil }

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 2)
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertFalse(client.fetchRequests.isEmpty)
    }

    func testOverlappingRecoveryRequestsShareOneAuthenticationAndSync() async throws {
        let harness = try makeConfiguredScheduler(ownerTokenIdentifier: "issuer|owner_a")
        let client = harness.client
        let scheduler = harness.scheduler
        let authenticationClient = StubSyncAuthenticationClient(
            result: .success(makeJWT(issuer: "issuer", subject: "owner_a")),
            waitsForResume: true
        )
        let coordinator = makeCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: scheduler,
            hasActiveSession: { true }
        )

        let foregroundRecovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .appForeground)
        }
        try await waitUntil { authenticationClient.hasPendingLogin }
        let manualRecovery = Task { @MainActor in
            await coordinator.recoverAuthenticationAndRequestSync(for: .manualRetry)
        }
        await Task.yield()
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertTrue(client.fetchRequests.isEmpty)
        authenticationClient.resumeLogin()
        await foregroundRecovery.value
        await manualRecovery.value
        try await waitUntil { scheduler.lastSyncedAt != nil }

        XCTAssertEqual(authenticationClient.loginFromCacheCallCount, 1)
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertFalse(client.fetchRequests.isEmpty)
    }

    private func makeConfiguredScheduler(
        ownerTokenIdentifier: String? = nil
    ) throws -> ConfiguredSchedulerHarness {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let client = FakeSyncClient()
        let scheduler = SyncScheduler(
            coordinator: SyncCoordinator(client: client),
            modelContext: container.mainContext,
            lastKnownOwnerTokenStore: makeOwnerStore()
        )
        scheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        return ConfiguredSchedulerHarness(
            container: container,
            client: client,
            scheduler: scheduler
        )
    }

    private func makeCoordinator(
        authenticationClient: any SyncAuthenticationClient,
        syncScheduler: SyncScheduler,
        hasActiveSession: @MainActor @escaping () -> Bool,
        currentSessionIdentifier: @MainActor @escaping () -> String? = { nil },
        expectedOwnerTokenIdentifier: (@MainActor () -> String?)? = nil,
        pendingAuthenticatedStateLifetime: TimeInterval = 5,
        now: @MainActor @escaping () -> Date = Date.init
    ) -> SyncRecoveryCoordinator {
        let expectedOwnerTokenIdentifier = expectedOwnerTokenIdentifier ?? {
            syncScheduler.currentOwnerTokenIdentifier
        }
        return SyncRecoveryCoordinator(
            authenticationClient: authenticationClient,
            syncScheduler: syncScheduler,
            hasActiveSession: hasActiveSession,
            currentSessionIdentifier: currentSessionIdentifier,
            expectedOwnerTokenIdentifier: expectedOwnerTokenIdentifier,
            pendingAuthenticatedStateLifetime: pendingAuthenticatedStateLifetime,
            now: now
        )
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
        let suiteName = "SyncRecoveryCoordinatorTests.\(UUID().uuidString)"
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

private struct ConfiguredSchedulerHarness {
    // Retaining the container keeps the in-memory ModelContext alive for each test.
    let container: ModelContainer
    let client: FakeSyncClient
    let scheduler: SyncScheduler
}

@MainActor
private final class StubSyncAuthenticationClient: SyncAuthenticationClient {
    private let result: Result<String, Error>
    private let waitsForResume: Bool
    private var continuations: [CheckedContinuation<Result<String, Error>, Never>] = []
    private(set) var loginFromCacheCallCount = 0
    private(set) var logoutCallCount = 0

    var hasPendingLogin: Bool {
        !continuations.isEmpty
    }

    var pendingLoginCount: Int {
        continuations.count
    }

    init(result: Result<String, Error>, waitsForResume: Bool = false) {
        self.result = result
        self.waitsForResume = waitsForResume
    }

    func loginFromCache() async -> Result<String, Error> {
        loginFromCacheCallCount += 1
        if waitsForResume {
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return result
    }

    func logout() async {
        logoutCallCount += 1
    }

    func resumeLogin() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: result)
    }
}

@MainActor
private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class ActiveSessionState {
    var isActive = true
}

@MainActor
private final class SessionIdentifierState {
    var identifier: String

    init(identifier: String) {
        self.identifier = identifier
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
