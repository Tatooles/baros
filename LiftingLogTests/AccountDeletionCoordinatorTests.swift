import SwiftData
import XCTest
@testable import LiftingLog

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
        let scheduler = SyncScheduler()
        scheduler.configure(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
            localDataResetService: LocalDataResetService(),
            syncScheduler: scheduler,
            modelContext: context
        )

        await coordinator.deleteAccount()

        XCTAssertEqual(client.deleteAccountDataCallCount, 1)
        XCTAssertEqual(accountDeleter.deleteCallCount, 0)
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserSettings>()).count, 1)
        let outboxEntries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(outboxEntries.count, 1)
        XCTAssertEqual(outboxEntries.first?.entityKind, .userSettings)
        XCTAssertEqual(outboxEntries.first?.operation, .create)
        XCTAssertEqual(outboxEntries.first?.ownerTokenIdentifier, "issuer|owner_a")
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
        let scheduler = SyncScheduler()
        scheduler.configure(modelContext: context)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
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
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a"))
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
            localDataResetService: LocalDataResetService(),
            syncScheduler: scheduler,
            modelContext: context
        )

        await coordinator.deleteAccount()

        XCTAssertEqual(client.deleteAccountDataCallCount, 1)
        XCTAssertEqual(accountDeleter.deleteCallCount, 1)
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
        let scheduler = SyncScheduler()
        context.insert(UserSettings())
        try context.save()

        let coordinator = AccountDeletionCoordinator(
            syncClient: client,
            accountDeleter: accountDeleter,
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
