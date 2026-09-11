import SwiftUI

struct HistoryOverviewRow<LeadingAccessory: View, Content: View>: View {
    let showsDivider: Bool
    @ViewBuilder let leadingAccessory: LeadingAccessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                leadingAccessory

                content
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if showsDivider {
                Rectangle()
                    .fill(AppTheme.subtleBorder)
                    .frame(height: 1)
                    .padding(.leading, 14)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}

struct HistoryOverviewRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                AppTheme.recessedSurface.opacity(configuration.isPressed ? 1 : 0)
            )
    }
}

struct HistoryOverviewIconTile: View {
    let systemName: String

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(AppTheme.brandAccentMuted)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 19))
                    .foregroundStyle(AppTheme.brandAccentForeground)
            }
            .accessibilityHidden(true)
    }
}

struct WorkoutHistoryRow: View {
    enum Presentation {
        case card
        case historyList
    }

    let session: WorkoutSession
    var presentation: Presentation = .card
    var showsDivider = false

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .card:
            cardPresentation
        case .historyList:
            historyListPresentation
        }
    }

    private var cardPresentation: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                Capsule()
                    .fill(AppTheme.brandAccentFill)
                    .frame(width: 4, height: 64)

                workoutSummaryContent

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var historyListPresentation: some View {
        HistoryOverviewRow(showsDivider: showsDivider) {
            HistoryOverviewIconTile(systemName: "calendar")
        } content: {
            workoutSummaryContent
        }
    }

    private var workoutSummaryContent: some View {
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
