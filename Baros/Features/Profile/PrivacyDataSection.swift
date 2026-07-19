import ClerkKit
import SwiftData
import SwiftUI

enum PrivacyDataDeletionAction: Equatable {
    case account
    case localData

    static func resolve(isAuthenticated: Bool) -> Self {
        if isAuthenticated {
            return .account
        }

        return .localData
    }

    var mode: DeleteDataMode {
        switch self {
        case .account:
            .account
        case .localData:
            .localData
        }
    }

    var title: String {
        switch self {
        case .account:
            "Delete Account"
        case .localData:
            "Delete Local Data"
        }
    }

    var detail: String {
        switch self {
        case .account:
            "Delete cloud account and data."
        case .localData:
            "Delete data saved on this iPhone."
        }
    }

    var systemImage: String {
        switch self {
        case .account:
            "person.crop.circle.badge.xmark"
        case .localData:
            "trash"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .account:
            "SettingsDeleteAccountRow"
        case .localData:
            "SettingsDeleteLocalDataRow"
        }
    }
}

struct PrivacyDataSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accountDeletionFactory) private var accountDeletionFactory
    @Environment(\.openURL) private var openURL
    @Environment(Clerk.self) private var clerk
    @Environment(SyncScheduler.self) private var syncScheduler

    let exportWorkoutHistory: () -> Void
    let links: PrivacySupportConfiguration
    let onDeletionCompleted: () -> Void

    private var deletionAction: PrivacyDataDeletionAction {
        let isAuthenticated =
            UITestAuthOverride.isForcedSignedIn ||
            (!UITestAuthOverride.isForcedSignedOut && clerk.user != nil)

        return PrivacyDataDeletionAction.resolve(isAuthenticated: isAuthenticated)
    }

    var body: some View {
        Section("Privacy & Data") {
            Button(action: exportWorkoutHistory) {
                Label("Export Workout History", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("ExportWorkoutHistoryButton")

            linkRow(title: "Privacy Policy", systemImage: "hand.raised", url: links.privacyPolicyURL)
                .accessibilityIdentifier("SettingsPrivacyPolicyRow")

            linkRow(title: "Support", systemImage: "questionmark.circle", url: links.supportURL)
                .accessibilityIdentifier("SettingsSupportRow")

            NavigationLink {
                DeleteDataConfirmationView(
                    mode: deletionAction.mode,
                    coordinator: accountDeletionFactory.makeCoordinator(
                        modelContext,
                        syncScheduler,
                        clerk
                    ),
                    onCompleted: onDeletionCompleted
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deletionAction.title)
                            .foregroundStyle(.red)
                        Text(deletionAction.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: deletionAction.systemImage)
                        .foregroundStyle(.red)
                }
            }
            .accessibilityIdentifier(deletionAction.accessibilityIdentifier)
        }
    }

    @ViewBuilder
    private func linkRow(title: String, systemImage: String, url: URL?) -> some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                Label(title, systemImage: systemImage)
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(links.unavailableDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
        }
    }
}
