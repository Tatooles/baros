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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppTheme.recessedSurface)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .accessibilityHidden(true)
    }
}

/// Calendar-style leading tile: the date is the row's most useful anchor when
/// scanning History, so the tile carries it instead of a repeated glyph.
struct HistoryDateTile: View {
    let date: Date
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(AppTheme.textSecondary)
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: side, height: side)
        .background(
            AppTheme.recessedSurface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WorkoutFormatters.compactDate(date))
    }
}

struct WorkoutHistoryRow: View {
    enum Presentation {
        case card
        case historyList
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            // Accessibility sizes give the text the full row width and spell
            // the date out with the metrics instead.
            if !dynamicTypeSize.isAccessibilitySize {
                HistoryDateTile(date: session.startedAt)
            }
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        listMetrics(separated: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        listMetrics(separated: false)
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The tile shows month and day; other years need the year spelled out.
    private var listYearText: String? {
        if dynamicTypeSize.isAccessibilitySize {
            return WorkoutFormatters.compactDate(session.startedAt)
        }
        let calendar = Calendar.current
        guard calendar.component(.year, from: session.startedAt) != calendar.component(.year, from: .now) else {
            return nil
        }
        return session.startedAt.formatted(.dateTime.year())
    }

    @ViewBuilder
    private func listMetrics(separated: Bool) -> some View {
        let duration = AppTheme.formatDuration(metrics.durationSeconds)
        let items = [
            listYearText,
            duration,
            WorkoutFormatters.exerciseCount(session.visibleExerciseCount),
            WorkoutFormatters.setCount(metrics.totalSetCount),
        ].compactMap { $0 }
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            if separated, index > 0 {
                Text("·")
                    .foregroundStyle(AppTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            if item == duration {
                // Beside a date tile, a bare "20:00" reads as a time of day.
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(item)
                        .monospacedDigit()
                }
            } else {
                Text(item)
                    .monospacedDigit()
            }
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
        Text(WorkoutFormatters.exerciseCount(session.visibleExerciseCount))
        Text(WorkoutFormatters.setCount(metrics.totalSetCount))
    }

    private var durationLabel: some View {
        Label(AppTheme.formatDuration(metrics.durationSeconds), systemImage: "clock")
    }
}
