import SwiftData
import SwiftUI

struct ExerciseHistoryDetailView: View {
    let summary: ExerciseHistorySummary
    @State private var workoutSelection: WorkoutHistorySelection?
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
        let groups = sessionGroups
        let records = ExerciseHistoryRecords.make(from: groups, equipmentRaw: summary.equipmentRaw)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExerciseHistoryHeading(
                    name: summary.name,
                    metadata: summary.metadataDisplayText,
                    performanceSummary: summary.historyDetailSummaryLabel
                )
                .accessibilityIdentifier("ExerciseHistoryHeading")

                if let records {
                    ExerciseHistoryRecordsCard(records: records, weightUnit: weightUnit)
                }

                ForEach(groups) { group in
                    ExerciseHistorySessionGroupCard(
                        group: group,
                        headingIdentity: ExerciseHistoryDisplayIdentity(
                            name: summary.name,
                            metadataDisplayText: summary.metadataDisplayText
                        ),
                        weightUnit: weightUnit,
                        records: records,
                        openWorkout: {
                            workoutSelection = WorkoutHistorySelection(id: group.session.id)
                        }
                    )
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $workoutSelection) { selection in
            WorkoutHistoryDestinationView(sessionID: selection.id)
        }
    }
}

private struct WorkoutHistorySelection: Identifiable, Hashable {
    let id: UUID
}
