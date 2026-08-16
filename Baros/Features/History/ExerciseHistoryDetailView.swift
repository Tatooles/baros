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
            VStack(alignment: .leading, spacing: 16) {
                ExerciseHistoryHeading(
                    name: summary.name,
                    metadata: summary.metadataDisplayText,
                    performanceSummary: summary.historyDetailSummaryLabel
                )
                .accessibilityIdentifier("ExerciseHistoryHeading")

                ForEach(sessionGroups) { group in
                    ExerciseHistorySessionGroupCard(
                        group: group,
                        headingIdentity: ExerciseHistoryDisplayIdentity(
                            name: summary.name,
                            metadataDisplayText: summary.metadataDisplayText
                        ),
                        weightUnit: weightUnit
                    )
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
