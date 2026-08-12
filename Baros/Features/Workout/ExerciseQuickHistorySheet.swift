import SwiftData
import SwiftUI

struct ExerciseQuickHistorySheet: View {
    let loggedExercise: LoggedExercise
    let openFullHistory: (ExerciseHistoryRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    private var route: ExerciseHistoryRoute {
        ExerciseHistoryRoute(loggedExercise: loggedExercise)
    }

    private var completedSessions: [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        )
    }

    private var summary: ExerciseHistorySummary? {
        let ownerTokenIdentifier = syncScheduler.currentOwnerTokenIdentifier
        return ExerciseHistorySummary.makeResolvedHistory(
            from: sessions,
            exercises: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).summary(for: route)
    }

    private var recentGroups: [ExerciseHistorySessionGroup] {
        guard let summary else { return [] }

        return ExerciseHistorySessionGroup.recentGroups(
            from: sessions,
            matching: summary,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            limit: 3
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ExerciseHistoryHeading(
                        name: loggedExercise.exerciseSnapshotName,
                        metadata: loggedExercise.metadataDisplayText
                    )
                    .accessibilityIdentifier("QuickExerciseHistoryHeading")

                    if recentGroups.isEmpty {
                        EmptyStateView(
                            title: "No History Yet",
                            message: "Completed workouts for this exercise will appear here."
                        )
                    } else {
                        ForEach(recentGroups) { group in
                            ExerciseHistorySessionGroupCard(group: group, weightUnit: weightUnit)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.vertical, 16)
            }
            .background(AppTheme.subtleBackground.ignoresSafeArea())
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
