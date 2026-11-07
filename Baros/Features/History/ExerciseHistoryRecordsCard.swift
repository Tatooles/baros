import Charts
import SwiftUI

/// The Exercise History summary: the two all-time records, each traceable to
/// its source set, and how the best estimate changed across workouts.
struct ExerciseHistoryRecordsCard: View {
    let records: ExerciseHistoryRecords
    let weightUnit: MeasurementUnit
    var showSource: (ExerciseHistoryRecord) -> Void = { _ in }
    @State private var showsInformation = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            SurfaceCard(padding: 0) {
                content
            }
        }
        .sheet(isPresented: $showsInformation) {
            StrengthRecordsInformationView()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Records")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if records.hasMixedEquipment {
                    Text("\(records.equipment.displayName) sets only")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Button { showsInformation = true } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("About strength records")
            .accessibilityIdentifier("AboutStrengthRecordsButton")
        }
        .padding(.leading, 4)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var content: some View {
        if let heaviest = records.heaviestRep {
            VStack(alignment: .leading, spacing: 0) {
                recordRow(heaviest, kind: .heaviestRep)
                divider
                if let estimate = records.estimated1RM {
                    recordRow(estimate, kind: .estimated1RM)
                } else {
                    missingEstimate
                }
                if records.estimateHistory.count >= ExerciseHistoryEstimateChart.minimumPoints {
                    divider
                    ExerciseHistoryEstimateChart(
                        points: records.estimateHistory,
                        recordWorkoutID: records.estimated1RM?.workoutID,
                        weightUnit: weightUnit
                    )
                    .padding(16)
                }
                if records.estimated1RM != nil {
                    Text("Estimates come from logged sets and don't account for effort.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .padding(.top, records.estimateHistory.count >= ExerciseHistoryEstimateChart.minimumPoints ? 0 : 4)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("No records yet")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Log a weight and reps on a completed set to see records here.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.subtleBorder)
            .frame(height: 1)
            .padding(.leading, 16)
            .accessibilityHidden(true)
    }

    private func recordRow(_ record: ExerciseHistoryRecord, kind: ExerciseHistoryRecordKind) -> some View {
        let isEstimate = kind == .estimated1RM
        let value = weightUnit.recordNumber(fromCanonicalPounds: record.value, isEstimate: isEstimate)
        let source = sourceText(record, kind: kind)
        return Button {
            showSource(record)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    RecordValue(
                        number: isEstimate ? "≈\u{2009}\(value)" : value,
                        unit: weightUnit.shortUnitLabel,
                        isHero: !isEstimate
                    )
                    Text(source)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if dynamicTypeSize.isAccessibilitySize {
                        Label("Show set", systemImage: "chevron.down")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.brandAccentForeground)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !dynamicTypeSize.isAccessibilitySize {
                    // Points down to the log, styled like the log's own chevrons.
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(HistoryOverviewRowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(record, kind: kind))
        .accessibilityHint("Shows the source set in your workouts below.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("ExerciseRecord-\(kind.rawValue)")
    }

    private var missingEstimate: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ExerciseHistoryRecordKind.estimated1RM.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text("No estimate yet")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text("Needs a completed set of 1–10 reps with weight.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private func sourceText(_ record: ExerciseHistoryRecord, kind: ExerciseHistoryRecordKind) -> String {
        let date = WorkoutFormatters.historyDate(record.workoutDate)
        if kind == .estimated1RM, records.recordsShareSource {
            return "From the same set"
        }
        let repCount = WorkoutFormatters.groupedNumber(Double(record.reps))
        let reps = record.reps == 1 ? "1 rep" : "\(repCount) reps"
        let lift = kind == .heaviestRep
            ? reps
            : "From \(weightUnit.recordNumber(fromCanonicalPounds: record.weight, isEstimate: false)) \(weightUnit.shortUnitLabel) × \(repCount)"
        return "\(lift) · \(date) · \(record.workoutTitle)"
    }

    private func accessibilityLabel(_ record: ExerciseHistoryRecord, kind: ExerciseHistoryRecordKind) -> String {
        let unit = weightUnit.displayName.lowercased()
        let value = weightUnit.recordNumber(fromCanonicalPounds: record.value, isEstimate: kind == .estimated1RM)
        let weight = weightUnit.recordNumber(fromCanonicalPounds: record.weight, isEstimate: false)
        let reps = record.reps == 1 ? "1 rep" : "\(record.reps) reps"
        let amount = kind == .estimated1RM ? "about \(value) \(unit)" : "\(value) \(unit)"
        return "\(kind.title), \(amount), from \(weight) \(unit) for \(reps), "
            + "Set \(record.displaySetNumber), \(record.workoutTitle), \(WorkoutFormatters.compactDate(record.workoutDate))"
    }
}

/// A record number with its unit on the same baseline, moving the unit to its
/// own line before the number would ever wrap between digits.
private struct RecordValue: View {
    let number: String
    let unit: String
    let isHero: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                numberText
                unitText
            }
            VStack(alignment: .leading, spacing: 0) {
                numberText
                unitText
            }
        }
    }

    private var numberText: some View {
        Text(number)
            .font((isHero ? Font.largeTitle : .title2).bold().monospacedDigit())
            .fontDesign(.rounded)
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var unitText: some View {
        Text(unit)
            .font((isHero ? Font.title3 : .body).weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
    }
}

/// Best Estimated 1RM per workout. Points only, no trend or projection, so the
/// series stays a record of logged performance rather than a forecast.
struct ExerciseHistoryEstimateChart: View {
    static let minimumPoints = 3

    let points: [ExerciseHistoryEstimatePoint]
    let recordWorkoutID: UUID?
    let weightUnit: MeasurementUnit
    @State private var selectedDate: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight = 150.0

    private func display(_ point: ExerciseHistoryEstimatePoint) -> Double {
        weightUnit.displayWeight(fromCanonicalPounds: point.value) ?? 0
    }

    private var selectedPoint: ExerciseHistoryEstimatePoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    /// Lowest and highest displayed estimates, rounded as the record is.
    private var yMarks: [Double] {
        let values = points.map(display)
        guard let low = values.min(), let high = values.max() else { return [] }
        let step = weightUnit == .kilograms ? 0.5 : 1
        let marks = [low, high].map { ($0 / step).rounded() * step }
        return marks[0] == marks[1] ? [marks[0]] : marks
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(display)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.18, high * 0.02)
        return (low - pad)...(high + pad)
    }

    /// Insets the first and last points from the plot edges.
    private var xDomain: ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date else { return Date.now...Date.now }
        let inset = max(last.timeIntervalSince(first) * 0.03, 12 * 3_600)
        return first.addingTimeInterval(-inset)...last.addingTimeInterval(inset)
    }

    private var showsYears: Bool {
        guard let first = points.first?.date, let last = points.last?.date else { return false }
        let calendar = Calendar.current
        return !calendar.isDate(first, equalTo: last, toGranularity: .year)
            || !calendar.isDate(last, equalTo: .now, toGranularity: .year)
    }

    private func axisDate(_ date: Date) -> some View {
        Text(date.formatted(showsYears ? .dateTime.month(.abbreviated).day().year() : .dateTime.month(.abbreviated).day()))
            .font(.caption2)
            .foregroundStyle(AppTheme.textSecondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // While dragging, the selected workout replaces the title so the
            // header keeps one height instead of squeezing both onto a line.
            HStack(alignment: .firstTextBaseline) {
                if let selectedPoint {
                    Text(selectionText(selectedPoint))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                } else {
                    Text("Estimated 1RM by workout")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer(minLength: 8)
                    if recordWorkoutID != nil {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppTheme.brandAccentForeground)
                                .frame(width: 8, height: 8)
                            Text("Record")
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 20)

            chart
                .frame(height: chartHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated 1RM by workout")
        .accessibilityValue(summary)
        .accessibilityChartDescriptor(self)
        .accessibilityIdentifier("ExerciseRecordEstimateChart")
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Estimated 1RM", display(point))
                )
                .foregroundStyle(AppTheme.brandAccentForeground.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if point.id == recordWorkoutID {
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Estimated 1RM", display(point))
                    )
                    .symbolSize(90)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                } else {
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Estimated 1RM", display(point))
                    )
                    .symbolSize(28)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                }
            }

            if let selectedPoint {
                RuleMark(x: .value("Date", selectedPoint.date, unit: .day))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        // Gridlines at the lowest and highest estimates, so the record point
        // always sits on a labeled line.
        .chartYAxis {
            AxisMarks(position: .trailing, values: yMarks) { value in
                AxisGridLine().foregroundStyle(AppTheme.subtleBorder)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(WorkoutFormatters.groupedNumber(number))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
        // The first and last workout dates, so any span reads correctly.
        .chartXAxis {
            AxisMarks(values: [points.first?.date].compactMap { $0 }) { value in
                AxisValueLabel(anchor: .topLeading) {
                    if let date = value.as(Date.self) { axisDate(date) }
                }
            }
            AxisMarks(values: [points.last?.date].compactMap { $0 }) { value in
                AxisValueLabel(anchor: .topTrailing) {
                    if let date = value.as(Date.self) { axisDate(date) }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
    }

    private func selectionText(_ point: ExerciseHistoryEstimatePoint) -> String {
        let value = weightUnit.recordNumber(fromCanonicalPounds: point.value, isEstimate: true)
        let weight = weightUnit.recordNumber(fromCanonicalPounds: point.record.weight, isEstimate: false)
        return "\(WorkoutFormatters.historyDate(point.date)) · ≈\u{2009}\(value) \(weightUnit.shortUnitLabel) from \(weight) × \(point.record.reps)"
    }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "" }
        let unit = weightUnit.displayName.lowercased()
        let values = points.map { weightUnit.recordNumber(fromCanonicalPounds: $0.value, isEstimate: true) }
        let sorted = points.sorted { $0.value < $1.value }
        let low = weightUnit.recordNumber(fromCanonicalPounds: sorted.first?.value ?? 0, isEstimate: true)
        let high = sorted.last.map { weightUnit.recordNumber(fromCanonicalPounds: $0.value, isEstimate: true) } ?? ""
        return "\(points.count) workouts from \(WorkoutFormatters.compactDate(first.date)) to "
            + "\(WorkoutFormatters.compactDate(last.date)), about \(low) to \(high) \(unit). "
            + "Most recent about \(values.last ?? "") \(unit)."
    }
}

extension ExerciseHistoryEstimateChart: @MainActor AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date.timeIntervalSince1970)
        let values = points.map(display)
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Workout date",
            range: (dates.min() ?? 0)...(dates.max() ?? 1),
            gridlinePositions: []
        ) { WorkoutFormatters.compactDate(Date(timeIntervalSince1970: $0)) }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Estimated 1RM (\(weightUnit.displayName.lowercased()))",
            range: (values.min() ?? 0)...(values.max() ?? 1),
            gridlinePositions: []
        ) { "about \(WorkoutFormatters.groupedNumber($0.rounded())) \(weightUnit.displayName.lowercased())" }
        let series = AXDataSeriesDescriptor(
            name: "Estimated 1RM",
            isContinuous: false,
            dataPoints: points.map { point in
                AXDataPoint(x: point.date.timeIntervalSince1970, y: display(point))
            }
        )
        return AXChartDescriptor(
            title: "Estimated 1RM by workout",
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

private struct StrengthRecordsInformationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Records describe sets you've saved. They aren't a measure of what you can lift today.")
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    section("Heaviest Rep") {
                        Text("The heaviest weight you've recorded for at least one completed rep in a finished workout.")
                    }
                    section("Estimated 1RM") {
                        Text("An estimate from your completed sets of 1–10 reps. For 2–10 reps, we use the Epley formula:")
                        Text("Weight × (1 + reps ÷ 30)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("A single rep uses its recorded weight. Warmup and drop sets don't count.")
                        Text("The estimate does not account for effort.")
                        Text("The chart shows the best estimate from each workout.")
                    }
                    section("Matching equipment") {
                        Text("Records use matching equipment. Bodyweight and resistance-band exercises are not included. Weight means the load you recorded.")
                    }
                    section("Source sets") {
                        Text("Tap a record to see the set behind it in your workouts. That set is marked with the record's name. For equal records, the most recent workout counts. Records update when your saved workouts change.")
                    }
                }
                .padding(AppTheme.shellPadding)
            }
            .background(AppTheme.canvasBackground)
            .navigationTitle("About strength records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            content()
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
