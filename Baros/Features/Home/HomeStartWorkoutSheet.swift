import SwiftData
import SwiftUI

private enum HomeStartRoute: Hashable {
    case pastWorkouts
    case review(UUID)
}

struct HomeStartWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    let content: HomeContent
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    let onWorkoutStarted: (WorkoutSession) -> Void
    @State private var path: [HomeStartRoute] = []
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var actionError: HomeStartWorkoutActionError?

    var body: some View {
        NavigationStack(path: $path) {
            choices
                .navigationTitle("Start Workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("StartWorkoutCancelButton")
                    }
                }
                .navigationDestination(for: HomeStartRoute.self) { route in
                    switch route {
                    case .pastWorkouts:
                        HomePastWorkoutsView(content: content)
                    case .review(let sessionID):
                        if let session = content.completedSessions.first(where: { $0.id == sessionID }) {
                            HomePastWorkoutReviewView(
                                session: session,
                                startWorkout: { startWorkout(fromPast: session) }
                            )
                        } else {
                            EmptyStateView(
                                title: "Workout Unavailable",
                                message: "This workout is no longer available to reuse."
                            )
                            .background(AppTheme.canvasBackground.ignoresSafeArea())
                        }
                    }
                }
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.canvasBackground)
        .onChange(of: path) { _, newPath in
            selectedDetent = newPath.isEmpty ? .medium : .large
        }
        .alert(item: $actionError) { actionError in
            Alert(
                title: Text(actionError.title),
                message: Text(actionError.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
        .accessibilityIdentifier("StartWorkoutSheet")
    }

    private var choices: some View {
        VStack(spacing: 12) {
            Button(action: startBlankWorkout) {
                HomeStartChoiceRow(
                    title: "Blank Workout",
                    detail: "Add exercises as you go",
                    systemImage: "plus",
                    trailingText: nil
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("StartBlankWorkoutButton")

            NavigationLink(value: HomeStartRoute.pastWorkouts) {
                HomeStartChoiceRow(
                    title: "Use Past Workout",
                    detail: "Review and repeat a completed workout",
                    systemImage: "clock.arrow.circlepath",
                    trailingText: content.completedSessions.isEmpty ? "None yet" : nil
                )
            }
            .buttonStyle(.plain)
            .disabled(content.completedSessions.isEmpty)
            .accessibilityLabel("Use Past Workout")
            .accessibilityValue(content.completedSessions.isEmpty ? "None yet" : "")
            .accessibilityIdentifier("UsePastWorkoutButton")
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
    }

    private func startBlankWorkout() {
        performStart {
            try activeWorkoutEngine.startBlankWorkout(
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                context: modelContext
            )
        }
    }

    private func startWorkout(fromPast session: WorkoutSession) {
        performStart {
            try activeWorkoutEngine.startWorkout(
                fromPast: session,
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                context: modelContext
            )
        }
    }

    private func performStart(_ action: () throws -> WorkoutSession) {
        do {
            let session = try action()
            onWorkoutStarted(session)
            dismiss()
        } catch {
            showActionError(error)
        }
    }

    private func showActionError(_ error: Error) {
        let message = error.localizedDescription
        activeWorkoutEngine.lastErrorMessage = message
        actionError = HomeStartWorkoutActionError(
            title: "Couldn't Start Workout",
            message: message
        )
    }
}

private struct HomeStartChoiceRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let trailingText: String?

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.brandAccentMuted, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(detail)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if let trailingText {
                    Text(trailingText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
        }
    }
}

private struct HomePastWorkoutsView: View {
    let content: HomeContent
    @State private var searchText = ""

    private var results: [WorkoutSession] {
        content.pastWorkouts(matching: searchText)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if results.isEmpty {
                EmptyStateView(
                    title: "No Matching Workouts",
                    message: "Try a workout title or exercise name."
                )
                .padding(.top, 48)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, session in
                        NavigationLink(value: HomeStartRoute.review(session.id)) {
                            WorkoutHistoryRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("PastWorkoutButton-\(index)")
                    }
                }
                .padding(AppTheme.shellPadding)
            }
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("Use Past Workout")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search workouts")
        .accessibilityIdentifier("PastWorkoutsList")
    }
}

private struct HomePastWorkoutReviewView: View {
    let session: WorkoutSession
    let startWorkout: () -> Void

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    private var presentation: HomePastWorkoutReviewPresentation {
        HomePastWorkoutReviewPresentation(session: session)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                VStack(spacing: 7) {
                    Text(session.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("StartFromPastWorkoutSheetTitle")

                    Text("Completed \(WorkoutFormatters.compactDate(presentation.completedAt))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                HStack(spacing: 10) {
                    MetricSummaryCard(title: "Exercises", value: "\(session.visibleExerciseCount)")
                    MetricSummaryCard(title: "Sets", value: "\(metrics.completedSetCount)")
                }

                Button(action: startWorkout) {
                    Text("Start Workout")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(AppTheme.brandAccentFill)
                .accessibilityIdentifier("StartFromPastWorkoutConfirmButton")
            }
            .padding(20)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("Review Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HomeStartWorkoutActionError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
