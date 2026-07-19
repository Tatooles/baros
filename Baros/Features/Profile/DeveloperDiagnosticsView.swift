#if DEBUG
import Combine
import ConvexMobile
import SwiftData
import SwiftUI

@MainActor
struct DeveloperDiagnosticsView: View {
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \SyncOutboxEntry.updatedAt, order: .reverse) private var outboxEntries: [SyncOutboxEntry]
    @State private var client = ConvexClientFactory.makeAuthenticatedClient()
    @State private var authStateLabel = "Loading"
    @State private var smokeResult = "Not checked"
    @State private var authStateTask: Task<Void, Never>?
    @State private var smokeTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Source") {
                if let sourceMetadata = AppBuildInfo.current.sourceMetadata {
                    diagnosticsRow(
                        title: "Branch",
                        value: sourceMetadata.branchDisplay,
                        valueIdentifier: "DeveloperDiagnosticsSourceBranch"
                    )
                    diagnosticsRow(
                        title: "Source",
                        value: sourceMetadata.sourceDescription,
                        valueIdentifier: "DeveloperDiagnosticsSourceDescription"
                    )
                    diagnosticsRow(
                        title: "Built",
                        value: sourceMetadata.builtAtDisplay,
                        valueIdentifier: "DeveloperDiagnosticsBuiltAt"
                    )
                    diagnosticsRow(
                        title: "Configuration",
                        value: sourceMetadata.configurationDisplay,
                        valueIdentifier: "DeveloperDiagnosticsBuildConfiguration"
                    )
                } else {
                    diagnosticsRow(
                        title: "Source",
                        value: "Unavailable",
                        valueIdentifier: "DeveloperDiagnosticsSourceDescription"
                    )
                }
            }

            Section("Environment") {
                diagnosticsRow(
                    title: "Mode",
                    value: AppEnvironmentConfiguration.current.environment.rawValue,
                    valueIdentifier: "DeveloperDiagnosticsEnvironment"
                )
                diagnosticsRow(
                    title: "Clerk Domain",
                    value: ClerkConfiguration.associatedDomain,
                    valueIdentifier: "DeveloperDiagnosticsClerkDomain"
                )
            }

            Section("Convex") {
                diagnosticsRow(
                    title: "Deployment",
                    value: ConvexConfiguration.deploymentURLString,
                    valueIdentifier: "DeveloperDiagnosticsConvexDeployment"
                )
                diagnosticsRow(
                    title: "Auth State",
                    value: authStateLabel,
                    valueIdentifier: "DeveloperDiagnosticsAuthState"
                )
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

            Section("Sync") {
                Text(syncDiagnostics.summary)
                    .font(.footnote.monospaced())
                    .foregroundStyle(AppTheme.textSecondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("DeveloperDiagnosticsSyncSummary")
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

    private var syncDiagnostics: SyncDiagnosticsSnapshot {
        let entries = outboxEntries
            .filter { entry in
                guard entry.isActive else { return false }
                guard entry.entityKind?.isV1Synced == true else { return false }
                if let owner = syncScheduler.currentOwnerTokenIdentifier {
                    return entry.ownerTokenIdentifier == owner || entry.ownerTokenIdentifier == nil
                }
                return true
            }
            .map { entry in
                SyncDiagnosticsEntry(
                    entityKind: entry.entityKindRaw,
                    operation: entry.operationRaw,
                    status: entry.statusRaw,
                    ownerTokenIdentifier: entry.ownerTokenIdentifier,
                    attemptCount: entry.attemptCount,
                    updatedAt: entry.updatedAt,
                    lastErrorMessage: entry.lastErrorMessage
                )
            }

        return SyncDiagnosticsSnapshot.make(
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            isSyncing: syncScheduler.isSyncing,
            lastFailureMessage: syncScheduler.lastFailure?.message,
            entries: entries
        )
    }

    private func diagnosticsRow(title: String, value: String, valueIdentifier: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .accessibilityIdentifier(valueIdentifier)
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
