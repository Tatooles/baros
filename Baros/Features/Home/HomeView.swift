import SwiftUI

struct HomeView: View {
    let activeSession: WorkoutSession?
    let returnToActiveWorkout: () -> Void
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    @State private var isStartWorkoutPresented = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Home")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("HomeTitle")

                if let activeSession {
                    TimelineView(.periodic(from: activeSession.startedAt, by: 60)) { timeline in
                        let metrics = WorkoutMetrics(session: activeSession, now: timeline.date)
                        Button(action: returnToActiveWorkout) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Return to Workout")
                                    .font(.headline)
                                Text(activeSession.title)
                                    .font(.title3.weight(.semibold))
                                Text(WorkoutFormatters.elapsedMinuteDescription(metrics.durationSeconds))
                                    .font(.subheadline)
                            }
                            .foregroundStyle(AppTheme.onBrandAccent)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.brandAccentFill, in: .rect(cornerRadius: AppTheme.cardCornerRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Return to Workout")
                        .accessibilityValue(
                            "\(activeSession.title), "
                                + WorkoutFormatters.elapsedMinuteAccessibilityDescription(metrics.durationSeconds)
                        )
                        .accessibilityIdentifier("HomeReturnToWorkoutButton")
                    }
                } else {
                    Button {
                        isStartWorkoutPresented = true
                    } label: {
                        Text("Start Workout")
                            .font(.headline)
                            .foregroundStyle(AppTheme.onBrandAccent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(AppTheme.brandAccentFill, in: .rect(cornerRadius: AppTheme.cardCornerRadius))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("HomeStartWorkoutButton")
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isStartWorkoutPresented) {
            NavigationStack {
                StartWorkoutView(
                    navigationState: navigationState,
                    activeWorkoutEngine: activeWorkoutEngine,
                    onWorkoutStarted: {
                        isStartWorkoutPresented = false
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
