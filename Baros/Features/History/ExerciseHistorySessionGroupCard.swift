import SwiftUI

struct ExerciseHistoryHeading: View {
    let name: String
    let metadata: String?
    let performanceSummary: String?
    var isCompact = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isCompact && !dynamicTypeSize.isAccessibilitySize {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.brandAccentMuted)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(AppTheme.brandAccentForeground)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(isCompact ? .title2.bold() : .largeTitle.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let metadata {
                        Text(metadata)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let performanceSummary {
                    Text(performanceSummary)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseHistorySessionGroupCard: View {
    let group: ExerciseHistorySessionGroup
    let headingIdentity: ExerciseHistoryDisplayIdentity
    var weightUnit: MeasurementUnit = .pounds
    var records: ExerciseHistoryRecords? = nil
    var showsExerciseNotes: Bool = true
    var openWorkout: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            loggedExerciseEntries
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppTheme.subtleBorder)
                .frame(width: 1)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var header: some View {
        if let openWorkout {
            Button(action: openWorkout) {
                headerContent(showsDisclosureIndicator: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(group.title), \(WorkoutFormatters.compactDate(group.startedAt)), "
                    + setCountLabel(for: group.completedSetCount)
            )
            .accessibilityHint("Opens completed workout.")
            .accessibilityIdentifier("ExercisePerformanceWorkoutButton-\(group.id.uuidString)")
        } else {
            headerContent(showsDisclosureIndicator: false)
        }
    }

    private func headerContent(showsDisclosureIndicator: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(WorkoutFormatters.compactDate(group.startedAt))
                    .accessibilityIdentifier("ExerciseHistorySessionDate-\(group.id.uuidString)")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(group.title)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(setCountLabel(for: group.completedSetCount))
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .accessibilityHidden(true)
            }
        }
    }

    private var loggedExerciseEntries: some View {
        VStack(spacing: 16) {
            ForEach(Array(group.loggedExerciseEntries.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 8) {
                    if entry.showsIdentity(comparedTo: headingIdentity) {
                        entryIdentity(entry.displayIdentity)
                    }

                    HistorySetTable(rows: entry.setEntries.map { item in
                        HistorySetTable.Row(
                            set: item.set,
                            number: item.displaySetNumber,
                            recordKinds: records?.kinds(for: item.id) ?? [],
                            accessibilityIdentifier: "ExerciseHistorySetValue-\(item.id.uuidString)"
                        )
                    }, weightUnit: weightUnit)

                    if showsExerciseNotes {
                        ExerciseHistoryNoteBlock(note: entry.exerciseNotes)
                    }
                }

                if index < group.loggedExerciseEntries.count - 1 {
                    Divider()
                        .overlay(AppTheme.subtleBorder)
                }
            }
        }
    }

    private func entryIdentity(_ identity: ExerciseHistoryDisplayIdentity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(identity.name)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let metadataDisplayText = identity.metadataDisplayText {
                Text(metadataDisplayText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setCountLabel(for count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }
}
