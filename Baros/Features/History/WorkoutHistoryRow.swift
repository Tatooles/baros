import SwiftUI

struct WorkoutHistoryRow: View {
    let session: WorkoutSession

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                Capsule()
                    .fill(AppTheme.brandAccentFill)
                    .frame(width: 4, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(WorkoutFormatters.compactDate(session.startedAt))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            workoutMetrics
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            workoutMetrics
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var workoutMetrics: some View {
        ViewThatFits(in: .horizontal) {
            durationLabel
            // Keep long durations intact even at the largest text size.
            durationLabel.labelStyle(.titleOnly)
        }
        Text("\(session.visibleExerciseCount) exercises")
        Text("\(metrics.completedSetCount) sets")
    }

    private var durationLabel: some View {
        Label(AppTheme.formatDuration(metrics.durationSeconds), systemImage: "clock")
    }
}
