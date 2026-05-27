import SwiftData
import SwiftUI

struct ExerciseQuickHistorySheet: View {
    let loggedExercise: LoggedExercise
    let openFullHistory: (ExerciseHistoryRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var route: ExerciseHistoryRoute {
        ExerciseHistoryRoute(loggedExercise: loggedExercise)
    }

    private var completedSessions: [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(from: sessions)
    }

    private var summary: ExerciseHistorySummary? {
        ExerciseHistorySummary.find(
            in: ExerciseHistorySummary.makeSummaries(from: completedSessions),
            matching: route
        )
    }

    private var recentGroups: [ExerciseHistorySessionGroup] {
        guard let summary else { return [] }

        return ExerciseHistorySessionGroup.recentGroups(
            from: completedSessions,
            matching: summary,
            limit: 3
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if recentGroups.isEmpty {
                        EmptyStateView(
                            title: "No History Yet",
                            message: "Completed workouts for this exercise will appear here."
                        )
                    } else {
                        ForEach(recentGroups) { group in
                            ExerciseHistorySessionGroupCard(group: group)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.vertical, 16)
            }
            .background(AppTheme.subtleBackground.ignoresSafeArea())
            .navigationTitle(loggedExercise.exerciseSnapshotName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if summary != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Full History") {
                            dismiss()
                            openFullHistory(route)
                        }
                        .accessibilityIdentifier("FullExerciseHistoryButton")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
