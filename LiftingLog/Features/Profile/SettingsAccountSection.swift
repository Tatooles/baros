import SwiftUI

struct SettingsAccountSection: View {
    var body: some View {
        Section {
            syncStatusRow

            NavigationLink {
                DeleteAccountPlaceholderView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delete Account")
                            .foregroundStyle(.red)
                        Text("Available before release.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundStyle(.red)
                }
            }
            .accessibilityIdentifier("SettingsDeleteAccountRow")
        } header: {
            Text("Account")
                .accessibilityIdentifier("Account")
        }
    }

    private var syncStatusRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sync Status")
                Text("Cloud sync is not configured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Local only")
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("SettingsSyncStatusRow")
    }
}

private struct DeleteAccountPlaceholderView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.red)

                    Text("Account deletion is not available yet.")
                        .font(.headline)
                        .accessibilityIdentifier("SettingsDeleteAccountPlaceholder")

                    Text("This release still stores your workouts locally. Account deletion will be available before release after cloud data deletion is connected.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}
