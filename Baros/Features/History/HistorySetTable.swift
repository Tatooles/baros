import SwiftUI

/// The shared set ledger for History details and Quick History.
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
    @ScaledMetric(relativeTo: .body) private var separatorWidth = 12.0

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(weightUnit.fieldLabel) × REPS")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            } else {
                GridRow {
                    Text("SET").gridColumnAlignment(.leading)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        valueColumns(weight: weightUnit.fieldLabel, reps: "REPS", showsRecord: false)
                        if hasRPE { rpePlaceholder }
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
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
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(AppTheme.subtleBorder)
                        .frame(height: 0.5)
                        .gridCellUnsizedAxes(.horizontal)
                        .accessibilityHidden(true)
                }
            }
        }
        .font(.body.monospacedDigit())
    }

    private func result(_ row: Row) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            valueColumns(
                weight: weightText(row.set),
                reps: repsText(row.set),
                showsRecord: !row.recordKinds.isEmpty
            )
            .foregroundStyle(AppTheme.textPrimary)
            if let rpe = WorkoutNumericInputPolicy.validatedRPE(row.set.rpe) {
                Text("@ \(WorkoutFormatters.number(rpe))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 40, alignment: .trailing)
            } else if !dynamicTypeSize.isAccessibilitySize && hasRPE {
                rpePlaceholder
            }
        }
    }

    // Header and data use the same columns, including space reserved for record/RPE annotations.
    private func valueColumns(weight: String, reps: String, showsRecord: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(weight)
                .fixedSize()
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : weightWidth, alignment: .trailing)
            Text("×")
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : separatorWidth)
            Text(reps)
                .fixedSize()
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : repsWidth, alignment: .trailing)
            Image(systemName: "trophy.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.brandAccentForeground)
                .opacity(showsRecord ? 1 : 0)
                .accessibilityHidden(true)
        }
    }

    private var hasRPE: Bool {
        rows.contains { WorkoutNumericInputPolicy.validatedRPE($0.set.rpe) != nil }
    }

    private var rpePlaceholder: some View {
        Color.clear.frame(width: 40, height: 1).accessibilityHidden(true)
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

/// A shared informational count; the containing view owns any navigation action.
struct HistorySetCountPill: View {
    let count: Int

    var body: some View {
        Text(count == 1 ? "1 set" : "\(count) sets")
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.brandAccentForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.brandAccentMuted, in: Capsule())
            .fixedSize()
    }
}
