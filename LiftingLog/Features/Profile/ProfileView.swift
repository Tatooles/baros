import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    private var settings: UserSettings? {
        UserSettings.visibleSettingsRecords(from: settingsRecords).first
    }

    private var completedWorkoutCount: Int {
        WorkoutSession.visibleCompletedSessions(from: sessions).count
    }

    private var activeExerciseCount: Int {
        Exercise.visibleActiveExercises(from: exercises).count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Profile")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("ProfileTitle")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Kevin")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Offline lifting log")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                HStack(spacing: 10) {
                    statCard(title: "Workouts", value: "\(completedWorkoutCount)")
                    statCard(title: "Exercises", value: "\(activeExerciseCount)")
                    statCard(title: "Unit", value: settings?.weightUnit.fieldLabel ?? "--")
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        row("Units", value: settings?.weightUnit.displayName ?? "Pounds")
                        row("Theme", value: "Dark")
                        row("Data Source", value: "SwiftData")
                    }
                }

                if let settings {
                    NavigationLink {
                        SettingsView(settings: settings)
                    } label: {
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
        .task {
            if UserSettings.visibleSettingsRecords(from: settingsRecords).isEmpty {
                try? SeedDataService.seedIfNeeded(context: modelContext)
            }
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
