import SwiftUI

struct WorkoutSummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: WorkoutSession
    let weightUnit: MeasurementUnit

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(WorkoutFormatters.compactDate(session.startedAt))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("WorkoutSummaryDate")

            metricsLayout

            if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline.weight(.bold))
                        Text(session.notes)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("WorkoutSummaryNotesCard")
            }

            ForEach(session.sortedLoggedExercises) { loggedExercise in
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loggedExercise.exerciseSnapshotName)
                                .font(.title3.weight(.bold))
                            if let metadataDisplayText = loggedExercise.metadataDisplayText {
                                Text(metadataDisplayText)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }

                        ForEach(loggedExercise.sortedSets) { set in
                            HStack {
                                Text("Set \(set.orderIndex + 1)")
                                Spacer()
                                Text(setSummary(for: set))
                                    .foregroundStyle(
                                        set.isCompleted
                                            ? AppTheme.brandAccentForeground
                                            : AppTheme.textSecondary
                                    )
                                    .accessibilityIdentifier(
                                        "WorkoutSummarySetSummary-\(loggedExercise.orderIndex)-\(set.orderIndex)"
                                    )
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        }

                        ExerciseHistoryNoteBlock(note: loggedExercise.notes)
                            .accessibilityIdentifier(
                                "WorkoutSummaryExerciseNote-\(loggedExercise.orderIndex)"
                            )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("WorkoutSummaryExercise-\(loggedExercise.orderIndex)")
            }
        }
    }

    private var metricsLayout: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))

        return layout {
            metricCard(
                title: "Duration",
                value: AppTheme.formatDuration(metrics.durationSeconds)
            )
            metricCard(title: "Exercises", value: "\(session.sortedLoggedExercises.count)")
            metricCard(title: "Sets", value: "\(metrics.completedSetCount)")
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        SurfaceCard {
            VStack(spacing: 4) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .accessibilityIdentifier("WorkoutSummaryMetricValue-\(title)")
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func setSummary(for set: LoggedSet) -> String {
        let weight = weightText(for: set)
        let reps = WorkoutNumericInputPolicy.validatedReps(set.reps).map(String.init) ?? "-"
        let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe).map {
            " @ \(WorkoutFormatters.number($0))"
        } ?? ""
        let status = set.isCompleted ? "Done" : "Open"
        return "\(weight) x \(reps)\(rpe) · \(status)"
    }

    private func weightText(for set: LoggedSet) -> String {
        let validWeight = WorkoutNumericInputPolicy.validatedWeight(set.weight)
        guard let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: validWeight) else {
            return "-"
        }

        return WorkoutFormatters.number(displayWeight)
    }
}
