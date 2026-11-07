import SwiftUI

struct ExerciseHistoryHeading: View {
    let name: String
    let metadata: String?
    let performanceSummary: String?
    var isCompact = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isCompact && !dynamicTypeSize.isAccessibilitySize {
                HistoryOverviewIconTile(systemName: "dumbbell.fill")
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(isCompact ? .title2.bold() : .largeTitle.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let metadata {
                        Text(metadata)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(isCompact ? 1 : nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let performanceSummary {
                    Text(performanceSummary)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
