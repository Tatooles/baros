import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \SyncOutboxEntry.updatedAt, order: .reverse) private var outboxEntries: [SyncOutboxEntry]

    private var activeSession: WorkoutSession? {
        WorkoutSession.visibleActiveSessions(
            from: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first
    }

    private var syncDisplayState: SyncStatusDisplayState {
        let activeEntries = outboxEntries.filter { entry in
            guard entry.isActive else { return false }
            guard entry.entityKind?.isV1Synced == true else { return false }
            if let owner = syncScheduler.currentOwnerTokenIdentifier {
                return entry.ownerTokenIdentifier == owner || entry.ownerTokenIdentifier == nil
            }
            return false
        }
        return SyncStatusDisplayState.make(
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            isSyncing: syncScheduler.isSyncing,
            lastSyncedAt: syncScheduler.lastSyncedAt,
            lastFailureMessage: syncScheduler.lastFailure?.message,
            pendingCount: activeEntries.filter { $0.status == .pending || $0.status == .inFlight }.count,
            failedCount: activeEntries.filter { $0.status == .failed }.count
        )
    }

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            NavigationStack(path: $navigationState.historyPath) {
                HistoryView(navigationState: navigationState)
            }
            .tabItem {
                Label(AppTab.history.title(isWorkoutActive: activeSession != nil), systemImage: AppTab.history.symbolName(isWorkoutActive: activeSession != nil))
                    .accessibilityIdentifier(AppTab.history.accessibilityIdentifier)
            }
            .tag(AppTab.history)

            NavigationStack {
                if let activeSession {
                    WorkoutSessionView(session: activeSession, engine: activeWorkoutEngine, navigationState: navigationState)
                } else {
                    StartWorkoutView(navigationState: navigationState, activeWorkoutEngine: activeWorkoutEngine)
                }
            }
            .tabItem {
                Label(AppTab.workout.title(isWorkoutActive: activeSession != nil), systemImage: AppTab.workout.symbolName(isWorkoutActive: activeSession != nil))
                    .accessibilityIdentifier(AppTab.workout.accessibilityIdentifier)
            }
            .tag(AppTab.workout)

            NavigationStack(path: $navigationState.profilePath) {
                ProfileView()
            }
            .tabItem {
                Label(AppTab.profile.title(isWorkoutActive: activeSession != nil), systemImage: AppTab.profile.symbolName(isWorkoutActive: activeSession != nil))
                    .accessibilityIdentifier(AppTab.profile.accessibilityIdentifier)
            }
            .tag(AppTab.profile)
        }
        .tint(AppTheme.accentBright)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom) {
            if syncDisplayState.showsGlobalFailureNotice {
                GlobalSyncFailureBanner(
                    retry: { syncScheduler.retrySync() },
                    details: { navigationState.openSyncSettings() }
                )
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.bottom, 8)
            }
        }
        .task {
            activeWorkoutEngine.loadActiveSession(
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                context: modelContext
            )
        }
    }
}

private struct GlobalSyncFailureBanner: View {
    let retry: () -> Void
    let details: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(AppTheme.accentBright)
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud sync failed")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Your data is saved on this iPhone.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentBright)
                    .accessibilityIdentifier("GlobalSyncRetryButton")
                Button("Details", action: details)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("GlobalSyncDetailsButton")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.accentBright.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("GlobalSyncFailureBanner")
    }
}
