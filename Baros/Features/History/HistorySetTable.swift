import BarosCore
import SwiftUI
import UIKit

struct HistorySetTable: View {
    struct Row: Identifiable {
        let set: LoggedSet
        let number: Int
        let accessibilityIdentifier: String
        var id: UUID { self.set.id }
    }

    let rows: [Row]
    let weightUnit: MeasurementUnit
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
        let widths = (
            weight: stacked ? weightWidth : fittedWidth(measuredSets.map { weightText($0) }, minimum: weightWidth),
            reps: stacked ? repsWidth : fittedWidth(measuredSets.map { measureText($0) }, minimum: repsWidth)
        )
        let weightHeader = showsWeight ? weightUnit.shortUnitLabel.uppercased() : ""
        return Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
            if stacked {
                Text(weightHeader.isEmpty ? measureHeader : "\(weightHeader) × \(measureHeader)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            } else {
                GridRow {
                    Text("SET").gridColumnAlignment(.leading)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        valueColumns(weight: weightHeader, reps: measureHeader, stacked: false, widths: widths)
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
                reps: measureText(row.set),
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

    @ViewBuilder
    private func valueColumns(weight: String, reps: String, stacked: Bool, widths: (weight: Double, reps: Double)) -> some View {
        if stacked, weight.isEmpty {
            Text(reps).frame(maxWidth: .infinity, alignment: .leading)
        } else if stacked {
            let separator = Text(" × ").foregroundColor(AppTheme.textSecondary)
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
                .opacity(weight.isEmpty ? 0 : 1)
            Text(reps)
                .fixedSize()
                .frame(width: widths.reps, alignment: .trailing)
        }
    }

    private func fittedWidth(_ values: [String], minimum: Double) -> Double {
        let font = UIFont.monospacedDigitSystemFont(ofSize: valuePointSize, weight: .regular)
        return max(minimum, values.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0)
    }

    private var measuredSets: [LoggedSet] {
        rows.map(\.set) + alignedSets
    }

    private var measureHeader: String {
        (rows.first?.set.trackingMethod ?? .reps).fieldLabel
    }

    private var showsWeight: Bool {
        rows.contains { !weightText($0.set).isEmpty }
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

    private func measureText(_ set: LoggedSet) -> String {
        Self.measureText(set)
    }

    private func accessibilityLabel(_ row: Row) -> String {
        Self.accessibilityLabel(set: row.set, number: row.number, recordKinds: [], unit: weightUnit)
    }

    static func weightText(_ set: LoggedSet, unit: MeasurementUnit) -> String {
        unit.displayWeight(fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(set.weight))
            .map(WorkoutFormatters.groupedNumber) ?? (set.trackingMethod == .duration ? "" : "–")
    }

    static func measureText(_ set: LoggedSet) -> String {
        if set.trackingMethod == .duration {
            return WorkoutNumericInputPolicy.validatedDuration(set.durationSeconds)
                .map(WorkoutFormatters.setDuration) ?? "–"
        }
        return WorkoutNumericInputPolicy.validatedReps(set.reps)
            .map { WorkoutFormatters.groupedNumber(Double($0)) } ?? "–"
    }

    static func valueText(_ set: LoggedSet, unit: MeasurementUnit) -> Text {
        let weight = weightText(set, unit: unit)
        guard !weight.isEmpty else { return Text(measureText(set)) }
        return Text("\(weight)\(Text(" × ").foregroundColor(AppTheme.textSecondary))\(measureText(set))")
    }

    static func valueCaption(for sets: [LoggedSet], unit: MeasurementUnit) -> String {
        guard sets.first?.trackingMethod == .duration else { return "\(unit.shortUnitLabel) × reps" }
        let hasWeight = sets.contains { WorkoutNumericInputPolicy.validatedWeight($0.weight) != nil }
        return hasWeight ? "\(unit.shortUnitLabel) × time" : "time"
    }

    static func accessibilityLabel(
        set: LoggedSet, number: Int, recordKinds: [ExerciseHistoryRecordKind], unit: MeasurementUnit
    ) -> String {
        let isTimed = set.trackingMethod == .duration
        let weight = unit.displayWeight(
            fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(set.weight)
        ).map { "\(WorkoutFormatters.number($0)) \(unit.displayName.lowercased())" }
            ?? (isTimed ? nil : "no weight")
        let measure = isTimed
            ? WorkoutNumericInputPolicy.validatedDuration(set.durationSeconds)
                .map(WorkoutFormatters.setDurationAccessibilityDescription) ?? "no time"
            : WorkoutNumericInputPolicy.validatedReps(set.reps)
                .map { "\($0) \($0 == 1 ? "rep" : "reps")" } ?? "no reps"
        let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe)
            .map { ", RPE \(WorkoutFormatters.number($0))" } ?? ""
        let spoken = ["Set \(number)", weight, measure].compactMap { $0 }.joined(separator: ", ")
        return ([spoken + rpe] + recordKinds.map(\.title))
            .joined(separator: ", ")
    }
}

struct HistorySetCountPill: View {
    let count: Int

    var body: some View {
        Text(count == 1 ? "1 set" : "\(count) sets")
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.recessedSurface, in: Capsule())
            .fixedSize()
    }
}
