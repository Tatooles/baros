import ClerkKit
import Foundation

@MainActor
final class ClerkAccountDeleter: AccountDeleting {
    private let clerk: Clerk

    init(clerk: Clerk = .shared) {
        self.clerk = clerk
    }

    func deleteCurrentAccount() async throws {
        guard let user = clerk.user else {
            throw ClerkAccountDeletionError.noCurrentUser
        }

        try await user.delete()
    }
}

enum ClerkAccountDeletionError: LocalizedError {
    case noCurrentUser

    var errorDescription: String? {
        switch self {
        case .noCurrentUser:
            "No signed-in account is available to delete."
        }
    }
}
