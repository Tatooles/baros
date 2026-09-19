import SwiftData
import SwiftUI

struct ExerciseQuickHistorySheet: View {
    let loggedExercise: LoggedExercise
    let openFullHistory: (ExerciseHistoryRoute) -> Void
    @State private var selectedWorkoutID: UUID?

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

    var body: some View {
        let ownerTokenIdentifier = syncScheduler.currentOwnerTokenIdentifier
        let historyRoute = route
        let historySnapshot = ExerciseHistoryViewSnapshot(
            sessions: sessions,
            exercises: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        let summary = historySnapshot.resolvedHistory.summary(for: historyRoute)
        let recentGroups = summary.map {
            ExerciseHistorySessionGroup.recentGroups(
                from: sessions,
                matching: $0,
                ownerTokenIdentifier: ownerTokenIdentifier,
                limit: 3
            )
        } ?? []

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ExerciseHistoryHeading(
                        name: loggedExercise.exerciseSnapshotName,
                        metadata: loggedExercise.metadataDisplayText,
                        performanceSummary: summary?.historyDetailSummaryLabel,
                        isCompact: true
                    )
                    .accessibilityIdentifier("QuickExerciseHistoryHeading")

                    if recentGroups.isEmpty {
                        EmptyStateView(
                            title: "No History Yet",
                            message: "Completed workouts for this exercise will appear here."
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(recentGroups) { group in
                                ExerciseHistorySessionGroupCard(
                                    group: group,
                                    headingIdentity: ExerciseHistoryDisplayIdentity(
                                        loggedExercise: loggedExercise
                                    ),
                                    weightUnit: weightUnit,
                                    openWorkout: { selectedWorkoutID = group.session.id }
                                )
                            }
                        }

                        if let summary, summary.performanceCount > recentGroups.count {
                            HStack(spacing: 6) {
                                Text("Showing \(recentGroups.count) of \(summary.performanceCount) workouts")
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .accessibilityIdentifier("QuickHistoryLimitFooter")

                                Text("·")
                                    .foregroundStyle(AppTheme.textTertiary)

                                Button("View all") {
                                    showFullHistory(historyRoute)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(AppTheme.brandAccentForeground)
                                .accessibilityIdentifier("QuickHistoryViewAllButton")
                            }
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.vertical, 16)
            }
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .navigationDestination(item: $selectedWorkoutID) { sessionID in
                WorkoutHistoryDestinationView(sessionID: sessionID)
            }
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
                            showFullHistory(historyRoute)
                        }
                        .accessibilityIdentifier("FullExerciseHistoryButton")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func showFullHistory(_ historyRoute: ExerciseHistoryRoute) {
        dismiss()
        openFullHistory(historyRoute)
    }
}
