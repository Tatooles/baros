import SwiftUI

struct ActiveWorkoutAccessoryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: WorkoutSession
    let showsReturnAction: Bool
    let returnToActiveWorkout: () -> Void

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1, paused: !showsReturnAction)
        ) { timeline in
            let metrics = WorkoutMetrics(session: session, now: timeline.date)

            Button(action: returnToActiveWorkout) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(
                            "\(session.title) · "
                                + WorkoutFormatters.elapsedCompactDescription(metrics.durationSeconds)
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "timer")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.brandAccentForeground)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.brandAccentMuted, in: Circle())
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(WorkoutFormatters.elapsedDescription(metrics.durationSeconds))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(metrics.completedSetCount) of \(metrics.totalSetCount)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("sets")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(
                    maxWidth: .infinity,
                    minHeight: dynamicTypeSize.isAccessibilitySize ? 96 : 52
                )
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Return to Workout")
                .accessibilityValue(
                    "\(session.title), "
                        + "\(WorkoutFormatters.elapsedAccessibilityDescription(metrics.durationSeconds)), "
                        + "\(metrics.completedSetCount) of \(metrics.totalSetCount) sets completed"
                )
                .accessibilityIdentifier("ActiveWorkoutAccessory")
                .accessibilityHidden(!showsReturnAction)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(showsReturnAction)
        }
    }
}
