import SwiftData
import XCTest
@testable import Baros

@MainActor
final class AccountDeletionCoordinatorTests: XCTestCase {
    func testAccountDeletionStopsBeforeClerkWhenConvexFails() async throws {
        struct ConvexError: LocalizedError {
            var errorDescription: String? { "network failed" }
        }

        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        client.deleteAccountDataError = ConvexError()
        let accountDeleter = FakeAccountDeleter()
        let attemptStore = TestAccountDeletionAttemptStore()
        let scheduler = SyncScheduler()
        scheduler.configure(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
            attemptStore: attemptStore,
            localDataResetService: LocalDataResetService(),
            syncScheduler: scheduler,
            modelContext: context
        )

        await coordinator.deleteAccount()

        XCTAssertEqual(client.deleteAccountDataCallCount, 1)
        XCTAssertEqual(
            attemptStore.persistedCancellationToken(for: "issuer|owner_a"),
            client.deleteAccountDataTokens.first
        )
        XCTAssertEqual(accountDeleter.deleteCallCount, 0)
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserSettings>()).count, 1)
        let outboxEntries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(outboxEntries.count, 0)
        XCTAssertEqual(coordinator.phase, .failed("Cloud data could not be deleted. Your account and data are still intact."))
        XCTAssertFalse(scheduler.isDeletionModeEnabled)
    }

    func testAccountDeletionKeepsLocalDataWhenClerkFailsAfterConvexSucceeds() async throws {
        struct ClerkError: LocalizedError {
            var errorDescription: String? { "Clerk failed" }
        }

        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let accountDeleter = FakeAccountDeleter()
        accountDeleter.error = ClerkError()
        let attemptStore = TestAccountDeletionAttemptStore()
        let scheduler = SyncScheduler()
        scheduler.configure(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
            attemptStore: attemptStore,
            localDataResetService: LocalDataResetService(),
            syncScheduler: scheduler,
            modelContext: context
        )

        await coordinator.deleteAccount()

        XCTAssertEqual(client.deleteAccountDataCallCount, 1)
        XCTAssertEqual(client.cancelAccountDeletionCallCount, 1)
        XCTAssertEqual(client.deleteAccountDataTokens.count, 1)
        XCTAssertEqual(client.cancelAccountDeletionTokens.count, 1)
        XCTAssertEqual(client.cancelAccountDeletionTokens, client.deleteAccountDataTokens)
        XCTAssertNil(attemptStore.persistedCancellationToken(for: "issuer|owner_a"))
        XCTAssertEqual(accountDeleter.deleteCallCount, 1)
        XCTAssertEqual(
            client.operationLog,
            ["deleteAccountData", "cancelAccountDeletion"]
        )
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserSettings>()).count, 1)
        let outboxEntries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(outboxEntries.count, 1)
        XCTAssertEqual(outboxEntries.first?.entityKind, .userSettings)
        XCTAssertEqual(outboxEntries.first?.operation, .create)
        XCTAssertEqual(outboxEntries.first?.ownerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(coordinator.phase, .failed("Account deletion could not finish. Your local data is still saved on this iPhone."))
        XCTAssertFalse(scheduler.isDeletionModeEnabled)
    }

    func testAccountDeletionResetsLocalDataAfterCloudAndClerkSucceed() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let accountDeleter = FakeAccountDeleter()
        let attemptStore = TestAccountDeletionAttemptStore()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
            attemptStore: attemptStore,
            localDataResetService: LocalDataResetService(),
            syncScheduler: scheduler,
            modelContext: context
        )

        await coordinator.deleteAccount()

        XCTAssertEqual(client.deleteAccountDataCallCount, 1)
        XCTAssertEqual(accountDeleter.deleteCallCount, 1)
        XCTAssertNil(attemptStore.persistedCancellationToken(for: "issuer|owner_a"))
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertEqual(coordinator.phase, .completed)
        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserSettings>()).count, 1)
        XCTAssertNil(try context.fetch(FetchDescriptor<UserSettings>()).first?.syncOwnerTokenIdentifier)
    }

    func testDeleteLocalDataSkipsConvexAndClerk() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let accountDeleter = FakeAccountDeleter()
        let attemptStore = TestAccountDeletionAttemptStore()
        let scheduler = SyncScheduler()
        context.insert(UserSettings())
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
            attemptStore: attemptStore,
            localDataResetService: LocalDataResetService(),
            syncScheduler: scheduler,
            modelContext: context
        )

        await coordinator.deleteLocalData()

        XCTAssertEqual(client.deleteAccountDataCallCount, 0)
        XCTAssertEqual(accountDeleter.deleteCallCount, 0)
        XCTAssertEqual(coordinator.phase, .completed)
        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserSettings>()).count, 1)
    }

    func testAccountDeletionRetryReusesPersistedCancellationToken() async throws {
        struct ClerkError: LocalizedError {
            var errorDescription: String? { "Clerk failed" }
        }

        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        let accountDeleter = FakeAccountDeleter()
        accountDeleter.error = ClerkError()
        let attemptStore = TestAccountDeletionAttemptStore()
        let persistedToken = UUID()
        attemptStore.setPersistedCancellationToken(persistedToken, for: "issuer|owner_a")
        let scheduler = SyncScheduler()
        scheduler.configure(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
            attemptStore: attemptStore,
            localDataResetService: LocalDataResetService(),
            syncScheduler: scheduler,
            modelContext: context
        )

        await coordinator.deleteAccount()

        XCTAssertEqual(client.deleteAccountDataTokens, [persistedToken])
        XCTAssertEqual(client.cancelAccountDeletionTokens, [persistedToken])
        XCTAssertNil(attemptStore.persistedCancellationToken(for: "issuer|owner_a"))
        XCTAssertEqual(coordinator.phase, .failed("Account deletion could not finish. Your local data is still saved on this iPhone."))
    }

    func testAccountDeletionPreservesPersistedTokenWhenCancellationFails() async throws {
        struct ClerkError: LocalizedError {
            var errorDescription: String? { "Clerk failed" }
        }

        struct CancellationError: LocalizedError {
            var errorDescription: String? { "Cancellation failed" }
        }

        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let client = FakeSyncClient()
        client.cancelAccountDeletionError = CancellationError()
        let accountDeleter = FakeAccountDeleter()
        accountDeleter.error = ClerkError()
        let attemptStore = TestAccountDeletionAttemptStore()
        let scheduler = SyncScheduler()
        scheduler.configure(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
            attemptStore: attemptStore,
            localDataResetService: LocalDataResetService(),
            syncScheduler: scheduler,
            modelContext: context
        )

        await coordinator.deleteAccount()

        XCTAssertEqual(client.deleteAccountDataTokens.count, 1)
        XCTAssertEqual(client.cancelAccountDeletionTokens, client.deleteAccountDataTokens)
        XCTAssertEqual(
            attemptStore.persistedCancellationToken(for: "issuer|owner_a"),
            client.deleteAccountDataTokens.first
        )
        XCTAssertEqual(scheduler.requestCount, 0)
        XCTAssertFalse(scheduler.isDeletionModeEnabled)
        XCTAssertEqual(coordinator.phase, .failed("Account deletion could not finish. Your local data is still saved on this iPhone."))
    }

    func testUserDefaultsDeletionAttemptStoreScopesTokensByOwner() {
        let suiteName = "AccountDeletionCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = UserDefaultsAccountDeletionAttemptStore(defaults: defaults)
        let ownerAToken = UUID()
        let ownerBToken = UUID()

        store.setPersistedCancellationToken(ownerAToken, for: "issuer|owner_a")
        store.setPersistedCancellationToken(ownerBToken, for: "issuer|owner_b")

        XCTAssertEqual(store.persistedCancellationToken(for: "issuer|owner_a"), ownerAToken)
        XCTAssertEqual(store.persistedCancellationToken(for: "issuer|owner_b"), ownerBToken)

        store.setPersistedCancellationToken(nil, for: "issuer|owner_b")

        XCTAssertEqual(store.persistedCancellationToken(for: "issuer|owner_a"), ownerAToken)
        XCTAssertNil(store.persistedCancellationToken(for: "issuer|owner_b"))
    }

    func testUserDefaultsDeletionAttemptStoreMigratesLegacyTokenToOwnerScope() {
        let suiteName = "AccountDeletionCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let baseKey = "AccountDeletionCoordinatorTests.persistedCancellationToken"
        let store = UserDefaultsAccountDeletionAttemptStore(
            defaults: defaults,
            baseKey: baseKey
        )
        let legacyToken = UUID()
        defaults.set(legacyToken.uuidString.lowercased(), forKey: baseKey)

        XCTAssertEqual(
            store.persistedCancellationToken(for: "issuer|owner_a"),
            legacyToken
        )
        XCTAssertNil(defaults.string(forKey: baseKey))
        XCTAssertEqual(
            store.persistedCancellationToken(for: "issuer|owner_a"),
            legacyToken
        )
    }
}

@MainActor
private final class FakeAccountDeleter: AccountDeleting {
    var deleteCallCount = 0
    var error: Error?

    func deleteCurrentAccount() async throws {
        deleteCallCount += 1
        if let error {
            throw error
        }
    }
}

@MainActor
private final class TestAccountDeletionAttemptStore: AccountDeletionAttemptStoring {
    private var persistedTokens: [String: UUID] = [:]

    func persistedCancellationToken(for ownerTokenIdentifier: String?) -> UUID? {
        persistedTokens[key(for: ownerTokenIdentifier)]
    }

    func setPersistedCancellationToken(_ token: UUID?, for ownerTokenIdentifier: String?) {
        let key = key(for: ownerTokenIdentifier)
        if let token {
            persistedTokens[key] = token
        } else {
            persistedTokens[key] = nil
        }
    }

    private func key(for ownerTokenIdentifier: String?) -> String {
        ownerTokenIdentifier ?? "ownerless"
    }
}
