import SwiftUI

struct WorkoutHistoryRow: View {
    let session: WorkoutSession

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.accentGradient)
                    .frame(width: 4, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(WorkoutFormatters.compactDate(session.startedAt))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    HStack(spacing: 12) {
                        Label(AppTheme.formatDuration(metrics.durationSeconds), systemImage: "clock")
                        Text("\(Self.exerciseCount(for: session)) exercises")
                        Text("\(metrics.totalSetCount) sets")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    static func exerciseCount(for session: WorkoutSession) -> Int {
        session.sortedLoggedExercises.count
    }
}
