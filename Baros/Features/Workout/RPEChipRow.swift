import SwiftData
import SwiftUI

struct RPEChipRow: View {
    static let values: [Double] = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]
    let selected: Double?
    let onSelect: (Double?) -> Void

    /// Tapping the selected value clears it, so the row needs no Clear chip
    /// and every value fits without scrolling.
    static func selection(afterTapping value: Double, current: Double?) -> Double? {
        current == value ? nil : value
    }

    var body: some View {
        // No spacing: each chip insets its own capsule, so the gaps between
        // capsules still belong to a chip and the row has no dead zones.
        HStack(spacing: 0) {
            ForEach(Self.values, id: \.self) { value in
                chip(value: value)
                    .accessibilityIdentifier("RPEChip-\(WorkoutFormatters.number(value))")
            }
        }
    }

    private func chip(value: Double) -> some View {
        let isSelected = selected == value

        return Button {
            onSelect(Self.selection(afterTapping: value, current: selected))
        } label: {
            Text(WorkoutFormatters.number(value))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isSelected ? AppTheme.onBrandAccent : AppTheme.textPrimary)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ? AnyShapeStyle(AppTheme.brandAccentFill) : AnyShapeStyle(AppTheme.recessedSurface),
                    in: Capsule()
                )
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Clears the RPE" : "")
    }
}

@MainActor
enum RPEChipSelectionAction {
    static func apply(
        value: Double?,
        preparedValues: ActiveWorkoutSetInput.Values? = nil,
        to set: LoggedSet,
        engine: ActiveWorkoutEngine,
        context: ModelContext,
        now: Date = .now
    ) throws {
        try engine.applyActiveSetRPESelection(
            set,
            rpe: value,
            preparedValues: preparedValues ?? .init(weight: set.weight, reps: set.reps),
            context: context,
            now: now
        )
    }
}
