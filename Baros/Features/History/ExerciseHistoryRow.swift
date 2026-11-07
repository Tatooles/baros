import SwiftUI

struct ExerciseHistoryRow: View {
    let summary: ExerciseHistorySummary
    let showsDivider: Bool

    var body: some View {
        // Every row would repeat the same glyph, so rows lead with the name.
        HistoryOverviewRow(showsDivider: showsDivider) {
            EmptyView()
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
                Text(summary.exerciseHistoryHeadingLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
