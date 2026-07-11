import SwiftData
import SwiftUI

struct SettingsAccountSection: View {
    @Environment(SyncScheduler.self) private var syncScheduler
    @Environment(\.syncRecoveryAction) private var syncRecoveryAction
    @Query(sort: \SyncOutboxEntry.updatedAt, order: .reverse) private var outboxEntries: [SyncOutboxEntry]

    private var displayState: SyncStatusDisplayState {
        let entries = relevantOutboxEntries
        return SyncStatusDisplayState.make(
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            isSyncing: syncScheduler.isSyncing,
            lastSyncedAt: syncScheduler.lastSyncedAt,
            lastFailureMessage: syncScheduler.lastFailure?.message,
            lastFailureReason: syncScheduler.lastFailure?.reason,
            pendingCount: entries.filter { $0.status == .pending || $0.status == .inFlight }.count,
            failedCount: entries.filter { $0.status == .failed }.count
        )
    }

    private var relevantOutboxEntries: [SyncOutboxEntry] {
        outboxEntries.filter { entry in
            guard entry.isActive else { return false }
            guard entry.entityKind?.isV1Synced == true else { return false }
            if let owner = syncScheduler.currentOwnerTokenIdentifier {
                return entry.ownerTokenIdentifier == owner || entry.ownerTokenIdentifier == nil
            }
            return entry.ownerTokenIdentifier == nil
        }
    }

    var body: some View {
        Section {
            syncStatusRow

            #if DEBUG
            NavigationLink {
                DeveloperDiagnosticsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Developer Diagnostics")
                        Text("Environment and Convex auth checks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "stethoscope")
                        .foregroundStyle(AppTheme.accentBright)
                }
            }
            .accessibilityIdentifier("SettingsDeveloperDiagnosticsRow")
            #endif

        } header: {
            Text("Account")
                .accessibilityIdentifier("Account")
        }
    }

    private var syncStatusRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: displayState.systemImage)
                .foregroundStyle(displayTint)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayState.title)
                Text(displayState.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detailText = displayState.detailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if displayState.canRetry {
                Button("Retry") {
                    syncRecoveryAction(.manualRetry)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("SettingsSyncRetryButton")
            } else {
                Text(displayState.trailingText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayTint: Color {
        switch displayState.tint {
        case .secondary:
            return .secondary
        case .attention:
            return AppTheme.accentBright
        case .success:
            return AppTheme.success
        }
    }
}
