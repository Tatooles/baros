import SwiftUI

struct ExerciseHistoryRow: View {
    let summary: ExerciseHistorySummary
    let showsDivider: Bool

    var body: some View {
        HistoryOverviewRow(showsDivider: showsDivider) {
            HistoryOverviewIconTile(systemName: "dumbbell.fill")
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                if let metadataDisplayText = summary.metadataDisplayText {
                    Text(metadataDisplayText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Text(summary.performanceSummaryLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
