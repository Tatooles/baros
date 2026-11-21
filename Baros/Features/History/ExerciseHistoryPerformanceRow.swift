import BarosCore
import SwiftUI

struct ExerciseHistoryPerformanceRow: View {
    let group: ExerciseHistorySessionGroup
    let headingIdentity: ExerciseHistoryDisplayIdentity
    let weightUnit: MeasurementUnit
    let records: ExerciseHistoryRecords?
    var isHighlighted = false
    var showsDivider = false
    var accessibilityFocus: AccessibilityFocusState<UUID?>.Binding
    let openWorkout: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var recordSets: [(entry: ExerciseHistorySetEntry, kinds: [ExerciseHistoryRecordKind])] {
        guard let records else { return [] }
        return group.setEntries.compactMap { entry in
            let kinds = records.kinds(for: entry.id)
            return kinds.isEmpty ? nil : (entry, kinds)
        }
    }

    private var recordSummary: Text? {
        let kinds = ExerciseHistoryRecordKind.allCases.filter { kind in
            recordSets.contains { $0.kinds.contains(kind) }
        }
        guard !kinds.isEmpty else { return nil }
        return kinds.enumerated().reduce(Text(verbatim: "")) { text, item in
            let label = Text("\(Image(systemName: item.element.markerSymbol)) \(item.element.badgeTitle)")
                .fontWeight(.semibold)
                .foregroundStyle(item.element.markerColor)
            return item.offset == 0 ? Text("\(text)\(label)") : Text("\(text) · \(label)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(group.loggedExerciseEntries) { entry in
                        if entry.id != group.loggedExerciseEntries.first?.id {
                            Rectangle()
                                .fill(AppTheme.subtleBorder)
                                .frame(height: 1)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if entry.showsIdentity(comparedTo: headingIdentity) {
                                Text(entry.displayIdentity.metadataDisplayText.map {
                                    "\(entry.displayIdentity.name) · \($0)"
                                } ?? entry.displayIdentity.name)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HistoryFlowLayout(
                                horizontalSpacing: 6,
                                verticalSpacing: 8,
                                isSingleColumn: dynamicTypeSize.isAccessibilitySize
                            ) {
                                ForEach(entry.setEntries) { item in
                                    HistorySetToken(
                                        set: item.set,
                                        number: item.displaySetNumber,
                                        recordKinds: records?.kinds(for: item.id) ?? [],
                                        weightUnit: weightUnit,
                                        accessibilityIdentifier: "ExerciseHistorySetValue-\(item.id.uuidString)"
                                    )
                                }
                            }
                            ExerciseHistoryNoteBlock(note: entry.exerciseNotes, topPadding: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            // An explicit Rectangle: a bare style would fill the card's
            // container shape and round every row's corners.
            .background(
                AppTheme.brandAccentMuted.opacity(isHighlighted ? 1 : 0),
                in: Rectangle()
            )

            if showsDivider {
                Rectangle()
                    .fill(AppTheme.subtleBorder)
                    .frame(height: 1)
                    .padding(.leading, 16)
                    .accessibilityHidden(true)
            }
        }
    }

    private var header: some View {
        Button(action: openWorkout) {
            HStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HistoryDateTile(date: group.startedAt)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitleText {
                        subtitleText
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(group.title), \(WorkoutFormatters.compactDate(group.startedAt)), "
                + WorkoutFormatters.setCount(group.completedSetCount)
                + recordAccessibilitySuffix
        )
        .accessibilityHint("Opens completed workout.")
        .accessibilityFocused(accessibilityFocus, equals: group.id)
        .accessibilityIdentifier("ExercisePerformanceWorkoutButton-\(group.id.uuidString)")
    }

    private var subtitleText: Text? {
        switch (datePrefix, recordSummary) {
        case (nil, nil): nil
        case let (date?, nil): Text(date)
        case let (nil, records?): records
        case let (date?, records?):
            Text("\(date)\(dynamicTypeSize.isAccessibilitySize ? "\n" : " · ")\(records)")
        }
    }

    private var recordAccessibilitySuffix: String {
        let kinds = recordSets.flatMap(\.kinds)
        guard !kinds.isEmpty else { return "" }
        return ", holds " + kinds.map { "\($0.title) record" }.joined(separator: " and ")
    }

    private var datePrefix: String? {
        if dynamicTypeSize.isAccessibilitySize {
            return WorkoutFormatters.historyDate(group.startedAt)
        }
        if !Calendar.current.isDate(group.startedAt, equalTo: .now, toGranularity: .year) {
            return group.startedAt.formatted(.dateTime.year())
        }
        return nil
    }
}

struct HistorySetToken: View {
    let set: LoggedSet
    let number: Int
    let recordKinds: [ExerciseHistoryRecordKind]
    let weightUnit: MeasurementUnit
    let accessibilityIdentifier: String

    private var isRecord: Bool { !recordKinds.isEmpty }

    private var outlineColor: Color {
        recordKinds.count == 1 ? recordKinds[0].markerColor : AppTheme.textSecondary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            ForEach(recordKinds, id: \.self) { kind in
                Image(systemName: kind.markerSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(kind.markerColor)
            }
            HistorySetTable.valueText(set, unit: weightUnit)
                .font(.callout.monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe) {
                Text("@\(WorkoutFormatters.number(rpe))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.recessedSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if isRecord {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(outlineColor, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistorySetTable.accessibilityLabel(
            set: set, number: number, recordKinds: recordKinds, unit: weightUnit
        ))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct HistoryFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat
    var isSingleColumn = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: bounds.width)
        for (index, frame) in layout.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: layout.constrained[index] ? ProposedViewSize(width: bounds.width, height: nil) : .unspecified
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], constrained: [Bool], size: CGSize) {
        var frames: [CGRect] = []
        var constrained: [Bool] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            let isConstrained = size.width > width + 0.5
            if isConstrained {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            constrained.append(isConstrained)
            if x > 0, isSingleColumn || x + size.width > width + 0.5 {
                x = 0
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - horizontalSpacing)
        }
        return (frames, constrained, CGSize(width: width.isFinite ? width : maxX, height: y + lineHeight))
    }
}

extension ExerciseHistoryRecordKind {
    var markerSymbol: String {
        switch self {
        case .heaviestRep: "trophy.fill"
        case .estimated1RM: "chart.line.uptrend.xyaxis"
        }
    }

    var markerColor: Color {
        switch self {
        case .heaviestRep: AppTheme.recordHeaviestForeground
        case .estimated1RM: AppTheme.recordEstimateForeground
        }
    }
}
