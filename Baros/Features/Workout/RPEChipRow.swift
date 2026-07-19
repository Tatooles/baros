import SwiftData
import SwiftUI

struct RPEChipRow: View {
    static let values: [Double] = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]
    let selected: Double?
    let onSelect: (Double?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Clear", value: nil)
                    .accessibilityIdentifier("RPEChipClear")

                ForEach(Self.values, id: \.self) { value in
                    chip(title: WorkoutFormatters.number(value), value: value)
                        .accessibilityIdentifier("RPEChip-\(WorkoutFormatters.number(value))")
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func chip(title: String, value: Double?) -> some View {
        let isSelected = selected == value

        return Button {
            onSelect(value)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? AnyShapeStyle(AppTheme.accentBright) : AnyShapeStyle(AppTheme.surfaceMuted),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

enum RPEChipSelectionAction {
    static func apply(value: Double?, to set: LoggedSet, engine: ActiveWorkoutEngine, context: ModelContext) throws {
        try engine.updateSet(set, weight: set.weight, reps: set.reps, rpe: value, context: context)
    }
}
