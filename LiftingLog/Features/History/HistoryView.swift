import SwiftData
import SwiftUI

struct HistoryView: View {
    @Bindable var navigationState: AppNavigationState
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var completedSessions: [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(from: sessions)
    }

    private var exerciseSummaries: [ExerciseHistorySummary] {
        ExerciseHistorySummary.makeSummaries(from: completedSessions)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("History")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("HistoryTitle")

                Picker("History Mode", selection: $navigationState.historyMode) {
                    ForEach(HistoryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("HistoryModePicker")

                switch navigationState.historyMode {
                case .workouts:
                    workoutContent
                case .exercises:
                    exerciseContent
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HistoryRoute.self) { route in
            switch route {
            case .exercise(let exerciseRoute):
                if let summary = ExerciseHistorySummary.find(in: exerciseSummaries, matching: exerciseRoute) {
                    ExerciseHistoryDetailView(summary: summary)
                } else {
                    EmptyStateView(
                        title: "No Exercise History",
                        message: "Completed sets for this exercise will appear here."
                    )
                    .background(AppTheme.subtleBackground.ignoresSafeArea())
                }
            }
        }
    }

    @ViewBuilder
    private var workoutContent: some View {
        if completedSessions.isEmpty {
            EmptyStateView(title: "No Workouts Yet", message: "Finished workouts will appear here.")
        } else {
            VStack(spacing: 10) {
                ForEach(Array(completedSessions.enumerated()), id: \.element.id) { index, session in
                    NavigationLink {
                        WorkoutHistoryDetailView(session: session)
                    } label: {
                        WorkoutHistoryRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("WorkoutHistoryButton-\(index)")
                }
            }
        }
    }

    @ViewBuilder
    private var exerciseContent: some View {
        if exerciseSummaries.isEmpty {
            EmptyStateView(title: "No Exercise History", message: "Completed sets will build exercise history.")
        } else {
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(exerciseSummaries.enumerated()), id: \.element.id) { index, summary in
                        NavigationLink {
                            ExerciseHistoryDetailView(summary: summary)
                        } label: {
                            ExerciseHistoryRow(summary: summary, showsDivider: index < exerciseSummaries.count - 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ExerciseHistoryButton-\(index)")
                    }
                }
            }
        }
    }
}
