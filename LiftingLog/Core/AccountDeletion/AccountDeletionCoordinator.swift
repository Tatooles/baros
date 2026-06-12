import Combine
import Foundation
import SwiftData

@MainActor
protocol AccountDeleting: AnyObject {
    func deleteCurrentAccount() async throws
}

enum AccountDeletionPhase: Equatable {
    case idle
    case deletingCloudData
    case deletingAccount
    case clearingLocalData
    case completed
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .deletingCloudData, .deletingAccount, .clearingLocalData:
            true
        case .idle, .completed, .failed:
            false
        }
    }
}

@MainActor
final class AccountDeletionCoordinator: ObservableObject {
    private let syncClient: any SyncClient & Sendable
    private let accountDeleter: any AccountDeleting
    private let localDataResetService: LocalDataResetService
    private let syncScheduler: SyncScheduler
    private let modelContext: ModelContext

    @Published private(set) var phase: AccountDeletionPhase = .idle

    init(
        syncClient: any SyncClient & Sendable,
        accountDeleter: any AccountDeleting,
        localDataResetService: LocalDataResetService,
        syncScheduler: SyncScheduler,
        modelContext: ModelContext
    ) {
        self.syncClient = syncClient
        self.accountDeleter = accountDeleter
        self.localDataResetService = localDataResetService
        self.syncScheduler = syncScheduler
        self.modelContext = modelContext
    }

    func deleteAccount() async {
        guard !phase.isRunning else { return }
        syncScheduler.beginDeletionMode()
        let cancellationToken = UUID()

        do {
            phase = .deletingCloudData
            _ = try await syncClient.deleteAccountData(cancellationToken: cancellationToken)

            phase = .deletingAccount
            do {
                try await accountDeleter.deleteCurrentAccount()
            } catch {
                _ = try await syncClient.cancelAccountDeletion(cancellationToken: cancellationToken)
                throw error
            }

            phase = .clearingLocalData
            try localDataResetService.reset(context: modelContext)
            syncScheduler.resetAfterDataDeletion()
            phase = .completed
        } catch {
            syncScheduler.endDeletionMode()
            switch phase {
            case .deletingCloudData:
                phase = .failed("Cloud data could not be deleted. Your account and data are still intact.")
            case .deletingAccount:
                phase = .failed("Account deletion could not finish. Your local data is still saved on this iPhone.")
            case .clearingLocalData:
                phase = .failed("Local data could not be cleared. Try deleting local data again.")
            case .idle, .completed, .failed:
                phase = .failed("Deletion could not finish. Your data is still saved on this iPhone.")
            }
        }
    }

    func deleteLocalData() async {
        guard !phase.isRunning else { return }
        syncScheduler.beginDeletionMode()

        do {
            phase = .clearingLocalData
            try localDataResetService.reset(context: modelContext)
            syncScheduler.resetAfterDataDeletion()
            phase = .completed
        } catch {
            syncScheduler.endDeletionMode()
            phase = .failed("Local data could not be deleted. Your data is still saved on this iPhone.")
        }
    }
}
