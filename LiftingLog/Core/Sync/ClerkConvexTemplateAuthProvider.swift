import ClerkKit
@preconcurrency import ConvexMobile
import Foundation

@MainActor
final class ClerkConvexTemplateAuthProvider: AuthProvider {
    typealias T = String

    private let jwtTemplate: String
    private var onIdToken: (@Sendable (String?) -> Void)?
    private var tokenRefreshListenerTask: Task<Void, Never>?
    private var sessionSyncTask: Task<Void, Never>?
    private weak var client: ConvexClientWithAuth<String>?

    init(jwtTemplate: String) {
        self.jwtTemplate = jwtTemplate
    }

    func bind(client: ConvexClientWithAuth<String>) {
        self.client = client
        startSessionSync()
    }

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        try await authenticate(onIdToken: onIdToken)
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        try await authenticate(onIdToken: onIdToken)
    }

    func logout() async throws {
        tokenRefreshListenerTask?.cancel()
        tokenRefreshListenerTask = nil
        onIdToken = nil
        try await Clerk.shared.auth.signOut()
    }

    nonisolated func extractIdToken(from authResult: String) -> String {
        authResult
    }

    private func authenticate(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        self.onIdToken = onIdToken
        let token = try await fetchToken()
        setupTokenRefreshListener()
        return token
    }

    private func fetchToken() async throws -> String {
        guard Clerk.shared.isLoaded else {
            throw ClerkConvexTemplateAuthProviderError.clerkNotLoaded
        }

        guard let session = Clerk.shared.session, session.status == .active else {
            throw ClerkConvexTemplateAuthProviderError.noActiveSession
        }

        guard let token = try await session.getToken(.init(template: jwtTemplate)) else {
            throw ClerkConvexTemplateAuthProviderError.tokenRetrievalFailed("Token returned nil")
        }

        return token
    }

    private func setupTokenRefreshListener() {
        tokenRefreshListenerTask?.cancel()

        tokenRefreshListenerTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for await event in Clerk.shared.auth.events {
                guard !Task.isCancelled else { break }

                switch event {
                case .tokenRefreshed:
                    onIdToken?(try? await fetchToken())
                default:
                    break
                }
            }
        }
    }

    private func startSessionSync() {
        sessionSyncTask?.cancel()

        sessionSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await syncSession(newSession: Clerk.shared.session)

            for await event in Clerk.shared.auth.events {
                guard !Task.isCancelled else { break }

                switch event {
                case .sessionChanged(let oldSession, let newSession):
                    await syncSession(oldSession: oldSession, newSession: newSession)
                default:
                    break
                }
            }
        }
    }

    private func syncSession(oldSession: Session? = nil, newSession: Session?) async {
        guard let client else { return }

        if shouldLogin(oldSession: oldSession, newSession: newSession) {
            _ = await client.loginFromCache()
        } else if shouldLogout(oldSession: oldSession, newSession: newSession) {
            await client.logout()
        }
    }

    private func shouldLogin(oldSession: Session?, newSession: Session?) -> Bool {
        newSession?.status == .active
            && (oldSession?.status != .active || oldSession?.id != newSession?.id)
    }

    private func shouldLogout(oldSession: Session?, newSession: Session?) -> Bool {
        oldSession?.id != nil && newSession == nil
    }
}

private enum ClerkConvexTemplateAuthProviderError: LocalizedError, Sendable, Equatable {
    case clerkNotLoaded
    case noActiveSession
    case tokenRetrievalFailed(String)

    var errorDescription: String? {
        switch self {
        case .clerkNotLoaded:
            "Clerk has not finished loading. Ensure Clerk.shared.isLoaded is true before authenticating."
        case .noActiveSession:
            "No active Clerk session. Please sign in first using Clerk."
        case .tokenRetrievalFailed(let reason):
            reason
        }
    }
}
