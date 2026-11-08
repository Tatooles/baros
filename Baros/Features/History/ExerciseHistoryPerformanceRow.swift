import SwiftUI

/// One Exercise Performance in the Exercise History log and Quick History:
/// the workout as a navigable header, then every completed set as a compact
/// `weight × reps` pill. A record set is outlined with a trophy, and the
/// header's subtitle names the record, so every pill keeps the same grammar.
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

    /// Completed sets in this workout that hold a record, in logged order.
    private var recordSets: [(entry: ExerciseHistorySetEntry, kinds: [ExerciseHistoryRecordKind])] {
        guard let records else { return [] }
        return group.setEntries.compactMap { entry in
            let kinds = records.kinds(for: entry.id)
            return kinds.isEmpty ? nil : (entry, kinds)
        }
    }

    /// "Est. 1RM", "Heaviest rep · Est. 1RM" for one set holding both, or each
    /// name with its value when different sets hold them.
    private var recordSummary: String? {
        let sets = recordSets
        guard !sets.isEmpty else { return nil }
        if sets.count == 1 {
            return sets[0].kinds.map(\.badgeTitle).joined(separator: " · ")
        }
        return sets.map { item in
            let value = "\(HistorySetTable.weightText(item.entry.set, unit: weightUnit)) × "
                + HistorySetTable.repsText(item.entry.set)
            return item.kinds.map { "\($0.badgeTitle) \(value)" }.joined(separator: " · ")
        }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(group.loggedExerciseEntries) { entry in
                        if entry.id != group.loggedExerciseEntries.first?.id {
                            // Repeated occurrences of the exercise stay visibly separate.
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
                                // One set per line at accessibility sizes.
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
            // container shape and round every row's corners. The card's clip
            // rounds only the first and last rows, so the highlight matches
            // the row it marks.
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
                    subtitleText
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    /// The set count, then the record this workout holds. At accessibility
    /// sizes the record gets its own line.
    private var subtitleText: Text {
        let base = Text(subtitle)
        guard let recordSummary else { return base }
        let trophy = Text("\(Image(systemName: "trophy.fill")) ")
            .foregroundStyle(AppTheme.textSecondary)
        let name = Text(recordSummary)
            .fontWeight(.semibold)
            .foregroundStyle(AppTheme.textPrimary)
        return Text("\(base)\(dynamicTypeSize.isAccessibilitySize ? "\n" : " · ")\(trophy)\(name)")
    }

    private var recordAccessibilitySuffix: String {
        let kinds = recordSets.flatMap(\.kinds)
        guard !kinds.isEmpty else { return "" }
        return ", holds " + kinds.map { "\($0.title) record" }.joined(separator: " and ")
    }

    /// The date tile carries month and day; the year and accessibility-size
    /// date move into the subtitle instead.
    private var subtitle: String {
        let sets = WorkoutFormatters.setCount(group.completedSetCount)
        if dynamicTypeSize.isAccessibilitySize {
            return "\(WorkoutFormatters.historyDate(group.startedAt)) · \(sets)"
        }
        if !Calendar.current.isDate(group.startedAt, equalTo: .now, toGranularity: .year) {
            return "\(group.startedAt.formatted(.dateTime.year())) · \(sets)"
        }
        return sets
    }
}

/// A completed set as one line: `weight × reps`, then RPE only when logged.
/// A record set adds a faint outline and a trophy; its name lives in the
/// workout's subtitle, so the pill never grows a label or a second line.
struct HistorySetToken: View {
    let set: LoggedSet
    let number: Int
    let recordKinds: [ExerciseHistoryRecordKind]
    let weightUnit: MeasurementUnit
    let accessibilityIdentifier: String

    private var isRecord: Bool { !recordKinds.isEmpty }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(HistorySetTable.weightText(set, unit: weightUnit))\(Text(" × ").foregroundColor(AppTheme.textSecondary))\(HistorySetTable.repsText(set))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe) {
                Text("@\(WorkoutFormatters.number(rpe))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize()
            }
            if isRecord {
                Image(systemName: "trophy.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.recessedSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if isRecord {
                // Neutral, not cobalt: records are information, not interaction.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AppTheme.textTertiary, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistorySetTable.accessibilityLabel(
            set: set, number: number, recordKinds: recordKinds, unit: weightUnit
        ))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Lays subviews out left to right, wrapping to a new line when the next one
/// would not fit. A subview wider than the line gets the full width.
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
            // A subview at its ideal size gets the same unspecified proposal it
            // was measured with, so rounding never squeezes it into wrapping.
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
            // Half a point of tolerance: placement must reproduce the lines
            // that sizing measured, or wrapped sets overlap the next row.
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
