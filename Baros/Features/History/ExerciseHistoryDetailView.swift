import SwiftData
import SwiftUI

struct ExerciseHistoryDetailView: View {
    let summary: ExerciseHistorySummary
    @State private var workoutSelection: WorkoutHistorySelection?
    @State private var highlightedWorkoutID: UUID?
    @AccessibilityFocusState private var focusedWorkoutID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    private var sessionGroups: [ExerciseHistorySessionGroup] {
        ExerciseHistorySessionGroup.makeGroups(
            from: sessions,
            matching: summary,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        )
    }

    var body: some View {
        let groups = sessionGroups
        let records = ExerciseHistoryRecords.make(from: groups, equipmentRaw: summary.equipmentRaw)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ExerciseHistoryHeading(
                        name: summary.name,
                        metadata: summary.metadataDisplayText,
                        performanceSummary: summary.exerciseHistoryHeadingLabel,
                        isCompact: false
                    )
                    .accessibilityIdentifier("ExerciseHistoryHeading")

                    if let records {
                        ExerciseHistoryRecordsCard(
                            records: records,
                            weightUnit: weightUnit,
                            showSource: { record in reveal(record.workoutID, with: proxy) }
                        )
                    }

                    workouts(groups, records: records)
                }
                .padding(AppTheme.shellPadding)
            }
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $workoutSelection) { selection in
            WorkoutHistoryDestinationView(sessionID: selection.id, linksExercises: true)
        }
    }

    private func workouts(_ groups: [ExerciseHistorySessionGroup], records: ExerciseHistoryRecords?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workouts")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(weightUnit.shortUnitLabel) × reps")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)

            // Not lazy: every performance stays in the accessibility tree, and
            // a record tap can scroll to any of them.
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        ExerciseHistoryPerformanceRow(
                            group: group,
                            headingIdentity: ExerciseHistoryDisplayIdentity(
                                name: summary.name,
                                metadataDisplayText: summary.metadataDisplayText
                            ),
                            weightUnit: weightUnit,
                            records: records,
                            isHighlighted: highlightedWorkoutID == group.id,
                            showsDivider: index < groups.count - 1,
                            accessibilityFocus: $focusedWorkoutID,
                            openWorkout: {
                                workoutSelection = WorkoutHistorySelection(id: group.session.id)
                            }
                        )
                        .id(group.id)
                    }
                }
            }
        }
    }

    /// Scrolls a record's source workout into view, washes it briefly, and
    /// moves VoiceOver there so the source set is the next thing read.
    private func reveal(_ workoutID: UUID, with proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) {
            proxy.scrollTo(workoutID, anchor: .center)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            highlightedWorkoutID = workoutID
        }
        focusedWorkoutID = workoutID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard highlightedWorkoutID == workoutID else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                highlightedWorkoutID = nil
            }
        }
    }
}

private struct WorkoutHistorySelection: Identifiable, Hashable {
    let id: UUID
}
