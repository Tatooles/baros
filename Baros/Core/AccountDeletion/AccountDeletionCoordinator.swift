import Combine
import Foundation
import SwiftData

@MainActor
protocol AccountDeleting: AnyObject {
    func deleteCurrentAccount() async throws
}

@MainActor
protocol AccountDeletionAttemptStoring: AnyObject {
    func persistedCancellationToken(for ownerTokenIdentifier: String?) -> UUID?
    func setPersistedCancellationToken(_ token: UUID?, for ownerTokenIdentifier: String?)
}

@MainActor
final class UserDefaultsAccountDeletionAttemptStore: AccountDeletionAttemptStoring {
    private let defaults: UserDefaults
    private let baseKey: String

    init(
        defaults: UserDefaults = .standard,
        baseKey: String = "AccountDeletionCoordinator.persistedCancellationToken"
    ) {
        self.defaults = defaults
        self.baseKey = baseKey
    }

    func persistedCancellationToken(for ownerTokenIdentifier: String?) -> UUID? {
        let scopedKey = key(for: ownerTokenIdentifier)
        if let rawValue = defaults.string(forKey: scopedKey) {
            return UUID(uuidString: rawValue)
        }

        guard
            scopedKey != baseKey,
            let legacyRawValue = defaults.string(forKey: baseKey),
            let legacyToken = UUID(uuidString: legacyRawValue)
        else {
            return nil
        }

        defaults.set(legacyToken.uuidString.lowercased(), forKey: scopedKey)
        defaults.removeObject(forKey: baseKey)
        return legacyToken
    }

    func setPersistedCancellationToken(_ token: UUID?, for ownerTokenIdentifier: String?) {
        let key = key(for: ownerTokenIdentifier)
        if let token {
            defaults.set(token.uuidString.lowercased(), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for ownerTokenIdentifier: String?) -> String {
        guard let ownerTokenIdentifier, !ownerTokenIdentifier.isEmpty else {
            return baseKey
        }

        return "\(baseKey).owner.\(ownerTokenIdentifier)"
    }
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
    private let attemptStore: any AccountDeletionAttemptStoring
    private let localDataResetService: LocalDataResetService
    private let syncScheduler: SyncScheduler
    private let modelContext: ModelContext

    @Published private(set) var phase: AccountDeletionPhase = .idle

    init(
        syncClient: any SyncClient & Sendable,
        accountDeleter: any AccountDeleting,
        attemptStore: any AccountDeletionAttemptStoring,
        localDataResetService: LocalDataResetService,
        syncScheduler: SyncScheduler,
        modelContext: ModelContext
    ) {
        self.syncClient = syncClient
        self.accountDeleter = accountDeleter
        self.attemptStore = attemptStore
        self.localDataResetService = localDataResetService
        self.syncScheduler = syncScheduler
        self.modelContext = modelContext
    }

    func deleteAccount() async {
        guard !phase.isRunning else { return }
        syncScheduler.beginDeletionMode()
        let ownerTokenIdentifier = syncScheduler.currentOwnerTokenIdentifier
        let cancellationToken = attemptStore.persistedCancellationToken(for: ownerTokenIdentifier) ?? UUID()
        attemptStore.setPersistedCancellationToken(cancellationToken, for: ownerTokenIdentifier)

        do {
            phase = .deletingCloudData
            _ = try await syncClient.deleteAccountData(cancellationToken: cancellationToken)

            phase = .deletingAccount
            do {
                try await accountDeleter.deleteCurrentAccount()
            } catch {
                do {
                    _ = try await syncClient.cancelAccountDeletion(cancellationToken: cancellationToken)
                    attemptStore.setPersistedCancellationToken(nil, for: ownerTokenIdentifier)
                    syncScheduler.recoverAfterFailedAccountDeletion()
                    throw error
                } catch {
                    throw error
                }
            }

            attemptStore.setPersistedCancellationToken(nil, for: ownerTokenIdentifier)
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
