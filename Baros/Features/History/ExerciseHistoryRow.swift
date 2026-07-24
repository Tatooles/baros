import SwiftUI

struct ExerciseHistoryRow: View {
    let summary: ExerciseHistorySummary
    let showsDivider: Bool

    private var performanceAccessibilityIdentifier: String {
        let equipmentName = summary.equipmentRaw
            .flatMap(ExerciseEquipment.init(rawValue:))?
            .displayName ?? "Unknown"
        return "ExerciseHistoryPerformance-\(summary.name)-\(equipmentName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.accentMuted)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(AppTheme.accentBright)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if let metadataDisplayText = summary.metadataDisplayText {
                        Text(metadataDisplayText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Text(summary.performanceSummaryLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier(performanceAccessibilityIdentifier)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if showsDivider {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
    }
}
