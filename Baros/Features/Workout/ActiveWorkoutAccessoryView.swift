import SwiftUI

struct ActiveWorkoutAccessoryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    let session: WorkoutSession
    let restTimer: RestTimerCoordinator
    let showsReturnAction: Bool
    let returnToActiveWorkout: () -> Void

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1, paused: !showsReturnAction)
        ) { timeline in
            let metrics = WorkoutMetrics(session: session, now: timeline.date)

            let restState = ActiveWorkoutAccessoryRestState(
                period: restTimer.current, sessionID: session.id, now: timeline.date
            )
            let restSubtitle = restState?.subtitle

            Button(action: returnToActiveWorkout) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(
                            "\(session.title) · "
                                + (restSubtitle ?? WorkoutFormatters.elapsedCompactDescription(metrics.durationSeconds))
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    } else if accessoryPlacement == .inline {
                        HStack(spacing: 4) {
                            Text(session.title)
                                .lineLimit(1)
                            Text("·")
                            Text(restSubtitle ?? WorkoutFormatters.elapsedCompactDescription(metrics.durationSeconds))
                                .foregroundStyle(restState != nil ? AppTheme.brandAccentForeground : AppTheme.textSecondary)
                                .fixedSize()
                        }
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: restState?.systemImage ?? "timer")
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
                                Text(restSubtitle ?? WorkoutFormatters.elapsedDescription(metrics.durationSeconds))
                                    .font(.caption)
                                    .foregroundStyle(restState != nil ? AppTheme.brandAccentForeground : AppTheme.textSecondary)
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
                    minHeight: dynamicTypeSize.isAccessibilitySize ? 96 : accessoryPlacement == .inline ? 44 : 52
                )
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Return to Workout")
                .accessibilityValue(
                    "\(session.title), "
                        + "\(restSubtitle ?? WorkoutFormatters.elapsedAccessibilityDescription(metrics.durationSeconds)), "
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

enum ActiveWorkoutAccessoryRestState: Equatable {
    case resting(seconds: Int)
    case finished

    init?(period: RestTimerPeriod?, sessionID: UUID, now: Date) {
        guard let period, period.rest.sessionID == sessionID, !period.rest.wasSkipped else { return nil }
        self = period.isFinished ? .finished : .resting(seconds: period.rest.remainingSeconds(at: now))
    }

    var subtitle: String {
        switch self {
        case let .resting(seconds):
            "Rest " + String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .finished:
            "Rest over"
        }
    }

    var systemImage: String {
        switch self {
        case .resting: "hourglass"
        case .finished: "checkmark"
        }
    }
}
