#if DEBUG
import Combine
import ConvexMobile
import SwiftUI

@MainActor
struct DeveloperDiagnosticsView: View {
    @State private var client = ConvexClientFactory.makeAuthenticatedClient()
    @State private var authStateLabel = "Loading"
    @State private var smokeResult = "Not checked"
    @State private var authStateTask: Task<Void, Never>?
    @State private var smokeTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Convex") {
                LabeledContent("Deployment", value: ConvexConfiguration.deploymentURLString)
                LabeledContent("Auth State", value: authStateLabel)
            }

            Section("Auth Smoke") {
                Button {
                    checkConvexAuth()
                } label: {
                    Label("Check Convex Auth", systemImage: "checkmark.shield")
                }
                .accessibilityIdentifier("DeveloperDiagnosticsCheckConvexAuthButton")

                Text(smokeResult)
                    .font(.footnote.monospaced())
                    .foregroundStyle(AppTheme.textSecondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("DeveloperDiagnosticsConvexAuthResult")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle("Developer Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            observeAuthState()
        }
        .onDisappear {
            authStateTask?.cancel()
            authStateTask = nil
            smokeTask?.cancel()
            smokeTask = nil
        }
    }

    private func observeAuthState() {
        guard authStateTask == nil else { return }

        authStateTask = Task {
            for await state in client.authState.values {
                switch state {
                case .loading:
                    authStateLabel = "Loading"
                case .unauthenticated:
                    authStateLabel = "Unauthenticated"
                case .authenticated:
                    authStateLabel = "Authenticated"
                }
            }
        }
    }

    private func checkConvexAuth() {
        smokeTask?.cancel()
        smokeResult = "Checking..."

        smokeTask = Task {
            do {
                let publisher = client.subscribe(
                    to: "authSmoke:me",
                    yielding: ConvexAuthSmokeIdentity.self
                )

                for try await identity in publisher.values {
                    smokeResult = """
                    tokenIdentifier: \(identity.tokenIdentifier)
                    subject: \(identity.subject)
                    issuer: \(identity.issuer)
                    email: \(identity.email ?? "nil")
                    """
                    break
                }
            } catch {
                smokeResult = error.localizedDescription
            }
        }
    }
}

private struct ConvexAuthSmokeIdentity: Decodable {
    let tokenIdentifier: String
    let subject: String
    let issuer: String
    let email: String?
}
#endif
