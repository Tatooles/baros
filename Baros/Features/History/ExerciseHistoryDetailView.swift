import SwiftData
import SwiftUI

struct ExerciseHistoryDetailView: View {
    let summary: ExerciseHistorySummary
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    private var sessionGroups: [ExerciseHistorySessionGroup] {
        ExerciseHistorySessionGroup.makeGroups(
            from: sessions,
            matching: summary,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last performed \(summary.lastPerformedLabel)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Completed Sets")
                            .font(.system(size: 16, weight: .bold))
                        Text("\(summary.completedSetCount) tracked sets across completed workouts.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ExerciseHistoryCompletedSetsCard")

                ForEach(sessionGroups) { group in
                    ExerciseHistorySessionGroupCard(group: group, weightUnit: weightUnit)
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
