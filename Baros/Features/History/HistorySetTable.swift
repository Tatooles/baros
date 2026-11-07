import SwiftUI
import UIKit

/// The shared set ledger for History details and Quick History.
struct HistorySetTable: View {
    struct Row: Identifiable {
        let set: LoggedSet
        let number: Int
        let accessibilityIdentifier: String
        var id: UUID { self.set.id }
    }

    let rows: [Row]
    let weightUnit: MeasurementUnit
    /// Sets from sibling tables on the same screen. Their values widen the
    /// columns and reserve the RPE column so adjacent tables line up.
    var alignedSets: [LoggedSet] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var weightWidth = 64.0
    @ScaledMetric(relativeTo: .body) private var repsWidth = 28.0
    @ScaledMetric(relativeTo: .body) private var separatorWidth = 12.0
    @ScaledMetric(relativeTo: .body) private var valuePointSize = 17.0
    @ScaledMetric(relativeTo: .caption) private var rpeWidth = 40.0

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            table(stacked: true)
        } else {
            ViewThatFits(in: .horizontal) {
                table(stacked: false)
                table(stacked: true)
            }
        }
    }

    private func table(stacked: Bool) -> some View {
        // Measure once for the whole compact table, then reuse the same widths
        // for its header and every row. The stacked layout does not need them.
        let widths = (
            weight: stacked ? weightWidth : fittedWidth(measuredSets.map { weightText($0) }, minimum: weightWidth),
            reps: stacked ? repsWidth : fittedWidth(measuredSets.map { repsText($0) }, minimum: repsWidth)
        )
        return Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
            if stacked {
                Text("\(weightUnit.fieldLabel) × REPS")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            } else {
                GridRow {
                    Text("SET").gridColumnAlignment(.leading)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        valueColumns(weight: weightUnit.fieldLabel, reps: "REPS", stacked: false, widths: widths)
                        if hasRPE {
                            Text("RPE")
                                .fixedSize()
                                .frame(width: rpeWidth, alignment: .trailing)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if stacked {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set \(row.number)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        result(row, stacked: stacked, widths: widths)
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
                        result(row, stacked: stacked, widths: widths)
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

    private func result(_ row: Row, stacked: Bool, widths: (weight: Double, reps: Double)) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            valueColumns(
                weight: weightText(row.set),
                reps: repsText(row.set),
                stacked: stacked,
                widths: widths
            )
            .foregroundStyle(AppTheme.textPrimary)
            if let rpe = WorkoutNumericInputPolicy.validatedRPE(row.set.rpe) {
                Text(stacked ? "RPE \(WorkoutFormatters.number(rpe))" : WorkoutFormatters.number(rpe))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize()
                    .frame(width: stacked ? nil : rpeWidth, alignment: .trailing)
            } else if !stacked && hasRPE {
                rpePlaceholder
            }
        }
    }

    // Header and data use the same columns, including space reserved for record/RPE annotations.
    @ViewBuilder
    private func valueColumns(weight: String, reps: String, stacked: Bool, widths: (weight: Double, reps: Double)) -> some View {
        if stacked {
            let separator = Text(" × ").foregroundColor(AppTheme.textSecondary)
            // A single text run can wrap between values instead of forcing the
            // entire weight × reps expression beyond the block's available width.
            Text("\(weight)\(separator)\(reps)")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            compactValueColumns(weight: weight, reps: reps, widths: widths)
        }
    }

    private func compactValueColumns(weight: String, reps: String, widths: (weight: Double, reps: Double)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(weight)
                .fixedSize()
                .frame(width: widths.weight, alignment: .trailing)
            Text("×")
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: separatorWidth)
            Text(reps)
                .fixedSize()
                .frame(width: widths.reps, alignment: .trailing)
        }
    }

    // Measure the displayed strings in the same scaled, monospaced-digit font
    // used by the rows. Headers and rows share these widths after unit conversion.
    private func fittedWidth(_ values: [String], minimum: Double) -> Double {
        let font = UIFont.monospacedDigitSystemFont(ofSize: valuePointSize, weight: .regular)
        return max(minimum, values.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0)
    }

    private var measuredSets: [LoggedSet] {
        rows.map(\.set) + alignedSets
    }

    private var hasRPE: Bool {
        measuredSets.contains { WorkoutNumericInputPolicy.validatedRPE($0.rpe) != nil }
    }

    private var rpePlaceholder: some View {
        Color.clear.frame(width: rpeWidth, height: 1).accessibilityHidden(true)
    }

    private func weightText(_ set: LoggedSet) -> String {
        Self.weightText(set, unit: weightUnit)
    }

    private func repsText(_ set: LoggedSet) -> String {
        Self.repsText(set)
    }

    private func accessibilityLabel(_ row: Row) -> String {
        Self.accessibilityLabel(set: row.set, number: row.number, recordKinds: [], unit: weightUnit)
    }

    static func weightText(_ set: LoggedSet, unit: MeasurementUnit) -> String {
        unit.displayWeight(fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(set.weight))
            .map(WorkoutFormatters.number) ?? "–"
    }

    static func repsText(_ set: LoggedSet) -> String {
        WorkoutNumericInputPolicy.validatedReps(set.reps).map(String.init) ?? "–"
    }

    /// The complete spoken set, shared by tables and compact set tokens.
    static func accessibilityLabel(
        set: LoggedSet, number: Int, recordKinds: [ExerciseHistoryRecordKind], unit: MeasurementUnit
    ) -> String {
        let weight = unit.displayWeight(
            fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(set.weight)
        ).map { "\(WorkoutFormatters.number($0)) \(unit.displayName.lowercased())" } ?? "no weight"
        let reps = WorkoutNumericInputPolicy.validatedReps(set.reps)
            .map { "\($0) \($0 == 1 ? "rep" : "reps")" } ?? "no reps"
        let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe)
            .map { ", RPE \(WorkoutFormatters.number($0))" } ?? ""
        return (["Set \(number), \(weight), \(reps)\(rpe)"] + recordKinds.map(\.title))
            .joined(separator: ", ")
    }
}

/// A shared informational count; the containing view owns any navigation action.
struct HistorySetCountPill: View {
    let count: Int

    var body: some View {
        Text(count == 1 ? "1 set" : "\(count) sets")
            .font(.caption.weight(.medium))
            // Informational, so neutral: cobalt is reserved for interaction and state.
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.recessedSurface, in: Capsule())
            .fixedSize()
    }
}
