import SwiftData
import SwiftUI

struct StartWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var completedSessions: [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(from: sessions)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Start Workout")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("StartWorkoutTitle")

                Button {
                    startBlankWorkout()
                } label: {
                    SurfaceCard {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(AppTheme.accentGradient)
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Blank Workout")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Start logging sets from scratch.")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("StartBlankWorkoutButton")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Use Past Workout")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    PastWorkoutPickerView(sessions: completedSessions) { session in
                        startWorkout(fromPast: session)
                    }
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func startBlankWorkout() {
        do {
            _ = try activeWorkoutEngine.startBlankWorkout(context: modelContext)
            navigationState.selectedTab = .workout
        } catch {
            activeWorkoutEngine.lastErrorMessage = error.localizedDescription
        }
    }

    private func startWorkout(fromPast session: WorkoutSession) {
        do {
            _ = try activeWorkoutEngine.startWorkout(fromPast: session, context: modelContext)
            navigationState.selectedTab = .workout
        } catch {
            activeWorkoutEngine.lastErrorMessage = error.localizedDescription
        }
    }
}
