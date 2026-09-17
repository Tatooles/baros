import SwiftUI

enum ExerciseHistoryPresentation {
    case card
    case openJournal
}

struct ExerciseHistoryHeading: View {
    let name: String
    let metadata: String?
    let performanceSummary: String?
    var presentation: ExerciseHistoryPresentation = .card

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if presentation == .card && !dynamicTypeSize.isAccessibilitySize {
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
                        .font(presentation == .openJournal ? .largeTitle.bold() : .title2.bold())
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
    var presentation: ExerciseHistoryPresentation = .card

    var body: some View {
        if presentation == .openJournal {
            openJournalContent
        } else {
            SurfaceCard {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()
                .overlay(AppTheme.subtleBorder)

            loggedExerciseEntries
        }
    }

    private var openJournalContent: some View {
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

    @ViewBuilder
    private func headerContent(showsDisclosureIndicator: Bool) -> some View {
        if presentation == .openJournal {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(WorkoutFormatters.compactDate(group.startedAt))
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
        } else {
            cardHeaderContent(showsDisclosureIndicator: showsDisclosureIndicator)
        }
    }

    private func cardHeaderContent(showsDisclosureIndicator: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(WorkoutFormatters.compactDate(group.startedAt))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Text(setCountLabel(for: group.completedSetCount))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.brandAccentForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.brandAccentMuted)
                .clipShape(Capsule())

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var loggedExerciseEntries: some View {
        VStack(spacing: presentation == .openJournal ? 16 : 12) {
            ForEach(Array(group.loggedExerciseEntries.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: presentation == .openJournal ? 8 : 10) {
                    if entry.showsIdentity(comparedTo: headingIdentity) {
                        entryIdentity(entry.displayIdentity)
                    }

                    if presentation == .openJournal {
                        HistorySetTable(rows: entry.setEntries.map { item in
                            HistorySetTable.Row(
                                set: item.set,
                                number: item.displaySetNumber,
                                recordKinds: records?.kinds(for: item.id) ?? [],
                                accessibilityIdentifier: "ExerciseHistorySetValue-\(item.id.uuidString)"
                            )
                        }, weightUnit: weightUnit)
                    } else {
                        setRows(for: entry.setEntries)
                    }

                    if showsExerciseNotes {
                        ExerciseHistoryNoteBlock(note: entry.exerciseNotes, presentation: presentation)
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
                .font(presentation == .openJournal ? .title3.bold() : .system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let metadataDisplayText = identity.metadataDisplayText {
                Text(metadataDisplayText)
                    .font(presentation == .openJournal ? .caption : .system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setRows(for entries: [ExerciseHistorySetEntry]) -> some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Set \(entry.displaySetNumber)")
                        Spacer(minLength: 8)
                        setResult(for: entry)
                            .accessibilityHidden(true)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set \(entry.displaySetNumber)")
                        setResult(for: entry)
                            .accessibilityHidden(true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityRepresentation {
                    Text(cardSetAccessibilityLabel(for: entry))
                        .accessibilityIdentifier("ExerciseHistorySetValue-\(entry.id.uuidString)")
                }
            }
        }
    }

    private func setResult(for entry: ExerciseHistorySetEntry) -> some View {
        let kinds = records?.kinds(for: entry.id) ?? []
        return HStack(spacing: 8) {
            if !kinds.isEmpty {
                ExerciseHistoryRecordBadges(kinds: kinds)
            }
            Text(setSummary(for: entry.set))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setSummary(for set: LoggedSet) -> String {
        let validWeight = WorkoutNumericInputPolicy.validatedWeight(set.weight)
        let weight = weightUnit.displayWeight(fromCanonicalPounds: validWeight).map(WorkoutFormatters.number) ?? "-"
        let reps = WorkoutNumericInputPolicy.validatedReps(set.reps).map(String.init) ?? "-"

        if let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe) {
            return "\(weight) x \(reps) @ \(WorkoutFormatters.number(rpe))"
        }

        return "\(weight) x \(reps)"
    }

    private func cardSetAccessibilityLabel(for entry: ExerciseHistorySetEntry) -> String {
        (["Set \(entry.displaySetNumber)", setSummary(for: entry.set)]
            + (records?.kinds(for: entry.id) ?? []).map(\.title))
            .joined(separator: ", ")
    }

    private func setCountLabel(for count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }
}
