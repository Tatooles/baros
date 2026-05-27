import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var activeSession: WorkoutSession? {
        WorkoutSession.visibleActiveSessions(from: sessions).first
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

            NavigationStack {
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
        .task {
            activeWorkoutEngine.loadActiveSession(context: modelContext)
        }
    }
}
