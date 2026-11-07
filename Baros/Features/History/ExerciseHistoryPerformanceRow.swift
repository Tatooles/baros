import SwiftUI

/// One Exercise Performance in the Exercise History log: the workout as a
/// navigable header, then every completed set as a compact `weight × reps`
/// token. Record source sets carry the record's name.
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
    @ScaledMetric(relativeTo: .headline) private var tileSide: CGFloat = 48

    private var setsLeading: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 0 : tileSide + 12
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
                .padding(.leading, setsLeading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                AppTheme.brandAccentMuted.opacity(isHighlighted ? 1 : 0)
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
                    Text(subtitle)
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
        )
        .accessibilityHint("Opens completed workout.")
        .accessibilityFocused(accessibilityFocus, equals: group.id)
        .accessibilityIdentifier("ExercisePerformanceWorkoutButton-\(group.id.uuidString)")
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

/// A completed set as `weight × reps`, with RPE and any record it holds, in
/// one quiet pill so each set reads as a unit.
struct HistorySetToken: View {
    let set: LoggedSet
    let number: Int
    let recordKinds: [ExerciseHistoryRecordKind]
    let weightUnit: MeasurementUnit
    let accessibilityIdentifier: String

    var body: some View {
        // The record name drops below the value when one line can't hold both.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                value
                if !recordKinds.isEmpty { HistoryRecordLabel(kinds: recordKinds) }
            }
            VStack(alignment: .leading, spacing: 2) {
                value
                if !recordKinds.isEmpty { HistoryRecordLabel(kinds: recordKinds) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.recessedSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistorySetTable.accessibilityLabel(
            set: set, number: number, recordKinds: recordKinds, unit: weightUnit
        ))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var value: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
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
        }
    }
}

/// Names the record a set holds. Informational, so neutral rather than cobalt.
struct HistoryRecordLabel: View {
    let kinds: [ExerciseHistoryRecordKind]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "trophy.fill")
                .imageScale(.small)
                .foregroundStyle(AppTheme.textSecondary)
            Text(kinds.map(\.badgeTitle).joined(separator: " · "))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .font(.caption.weight(.semibold))
        // A record name only wraps when a single line can't hold it at all.
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
        .accessibilityHidden(true)
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
