import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    @Bindable var navigationState: AppNavigationState
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    private var settings: UserSettings? {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first
    }

    private var completedWorkoutCount: Int {
        WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).count
    }

    private var activeExerciseCount: Int {
        Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Profile")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("ProfileTitle")

                    #if DEBUG
                    if AppEnvironmentConfiguration.current.environment == .development {
                        Text("DEV")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.accentBright)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.accentBright.opacity(0.12), in: Capsule())
                            .accessibilityIdentifier("ProfileEnvironmentBadge")
                    }
                    #endif
                }

                ProfileAccountCard()

                HStack(spacing: 10) {
                    statCard(title: "Workouts", value: "\(completedWorkoutCount)")
                    statCard(title: "Exercises", value: "\(activeExerciseCount)")
                    statCard(title: "Unit", value: settings?.weightUnit.fieldLabel ?? "--")
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        row("Units", value: settings?.weightUnit.displayName ?? "Pounds")
                        row("Theme", value: "System")
                        row("Data Source", value: "SwiftData")
                    }
                }

                if settings != nil {
                    NavigationLink(value: ProfileRoute.settings) {
                        settingsRow(title: "Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ProfileSettingsLink")
                }

                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    settingsRow(title: "Exercise Library", systemImage: "dumbbell")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ProfileExerciseLibraryLink")
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: ProfileRoute.self) { route in
            switch route {
            case .settings:
                SettingsRouteView {
                    navigationState.profilePath = []
                }
            }
        }
        .task(id: syncScheduler.currentOwnerTokenIdentifier) {
            seedSettingsIfNeeded()
        }
    }

    private func seedSettingsIfNeeded() {
        if UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).isEmpty {
            try? SeedDataService.seedIfNeeded(
                context: modelContext,
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
            )
        }
    }

    private func settingsRow(title: String, systemImage: String) -> some View {
        SurfaceCard {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private func statCard(title: String, value: String) -> some View {
        SurfaceCard {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .font(.system(size: 16, weight: .medium))
    }
}

private struct SettingsRouteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    let onDataDeletionCompleted: () -> Void

    private var settings: UserSettings? {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first
    }

    var body: some View {
        Group {
            if let settings {
                SettingsView(
                    settings: settings,
                    onDataDeletionCompleted: onDataDeletionCompleted
                )
            } else {
                ProgressView()
                    .tint(AppTheme.accentBright)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.subtleBackground.ignoresSafeArea())
            }
        }
        .task(id: syncScheduler.currentOwnerTokenIdentifier) {
            seedSettingsIfNeeded()
        }
    }

    private func seedSettingsIfNeeded() {
        if UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).isEmpty {
            try? SeedDataService.seedIfNeeded(
                context: modelContext,
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
            )
        }
    }
}
