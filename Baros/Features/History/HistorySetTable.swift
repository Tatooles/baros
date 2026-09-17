import SwiftUI

/// The same set ledger is used by both History detail screens.
struct HistorySetTable: View {
    struct Row: Identifiable {
        let set: LoggedSet
        let number: Int
        var recordKinds: [ExerciseHistoryRecordKind] = []
        let accessibilityIdentifier: String
        var id: UUID { self.set.id }
    }

    let rows: [Row]
    let weightUnit: MeasurementUnit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var weightWidth = 64.0
    @ScaledMetric(relativeTo: .body) private var repsWidth = 28.0

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Weight (\(weightUnit.fieldLabel.lowercased())) × Reps")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            } else {
                GridRow {
                    Text("Set").gridColumnAlignment(.leading)
                    Text("Weight (\(weightUnit.fieldLabel.lowercased())) × Reps")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            }

            ForEach(rows) { row in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set \(row.number)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        result(row)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(row))
                    .accessibilityIdentifier(row.accessibilityIdentifier)
                } else {
                    GridRow {
                        Text("\(row.number)")
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHidden(true)
                        // GridRow forwards accessibility modifiers to every cell.
                        // Give the result cell the single complete set announcement.
                        result(row)
                            .fixedSize(horizontal: true, vertical: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(accessibilityLabel(row))
                            .accessibilityIdentifier(row.accessibilityIdentifier)
                    }
                    .padding(.vertical, 8)
                }
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                    .accessibilityHidden(true)
            }
        }
        .font(.body.monospacedDigit())
    }

    private func result(_ row: Row) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(weightText(row.set))
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : weightWidth, alignment: .trailing)
                Text("×").foregroundStyle(AppTheme.textSecondary).fixedSize()
                Text(repsText(row.set))
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : repsWidth, alignment: .trailing)
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .opacity(row.recordKinds.isEmpty ? 0 : 1)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(AppTheme.textPrimary)
            if let rpe = WorkoutNumericInputPolicy.validatedRPE(row.set.rpe) {
                Text("@ \(WorkoutFormatters.number(rpe))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 40, alignment: .trailing)
            } else if !dynamicTypeSize.isAccessibilitySize && rows.contains(where: { WorkoutNumericInputPolicy.validatedRPE($0.set.rpe) != nil }) {
                Color.clear.frame(width: 40, height: 1).accessibilityHidden(true)
            }
        }
    }

    private func weightText(_ set: LoggedSet) -> String {
        weightUnit.displayWeight(fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(set.weight))
            .map(WorkoutFormatters.number) ?? "–"
    }

    private func repsText(_ set: LoggedSet) -> String {
        WorkoutNumericInputPolicy.validatedReps(set.reps).map(String.init) ?? "–"
    }

    private func accessibilityLabel(_ row: Row) -> String {
        let weight = weightUnit.displayWeight(
            fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(row.set.weight)
        ).map { "\(WorkoutFormatters.number($0)) \(weightUnit.displayName.lowercased())" } ?? "no weight"
        let reps = WorkoutNumericInputPolicy.validatedReps(row.set.reps)
            .map { "\($0) \($0 == 1 ? "rep" : "reps")" } ?? "no reps"
        let rpe = WorkoutNumericInputPolicy.validatedRPE(row.set.rpe)
            .map { ", RPE \(WorkoutFormatters.number($0))" } ?? ""
        return (["Set \(row.number), \(weight), \(reps)\(rpe)"] + row.recordKinds.map(\.title))
            .joined(separator: ", ")
    }
}
