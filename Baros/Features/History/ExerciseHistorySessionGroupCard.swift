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
                        .font(.title2.weight(.bold))
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
                        .foregroundStyle(
                            presentation == .openJournal
                                ? AppTheme.brandAccentForeground
                                : AppTheme.textSecondary
                        )
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        VStack(alignment: .leading, spacing: 13) {
            Divider()
                .overlay(AppTheme.subtleBorder)
                .accessibilityHidden(true)

            header

            loggedExerciseEntries
        }
        .padding(.top, 4)
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(WorkoutFormatters.compactDate(group.startedAt))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
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
        VStack(spacing: 12) {
            ForEach(Array(group.loggedExerciseEntries.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 10) {
                    if entry.showsIdentity(comparedTo: headingIdentity) {
                        entryIdentity(entry.displayIdentity)
                    }

                    if presentation == .openJournal && !dynamicTypeSize.isAccessibilitySize {
                        setColumnHeadings
                    }

                    setRows(for: entry.setEntries)

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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(
                    presentation == .openJournal
                        ? AppTheme.brandAccentForeground
                        : AppTheme.textPrimary
                )
                .fixedSize(horizontal: false, vertical: true)

            if let metadataDisplayText = identity.metadataDisplayText {
                Text(metadataDisplayText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setRows(for entries: [ExerciseHistorySetEntry]) -> some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                if presentation == .openJournal {
                    openJournalSetRow(entry)
                } else {
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
    }

    private var setColumnHeadings: some View {
        HStack(spacing: 12) {
            Text("Set")
                .frame(width: 42, alignment: .leading)
            Text("Weight (\(weightUnit.fieldLabel.lowercased()))")
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("Reps")
                .frame(width: 108, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary)
        .accessibilityElement(children: .combine)
    }

    private func openJournalSetRow(_ entry: ExerciseHistorySetEntry) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Set \(entry.displaySetNumber)")
                        .foregroundStyle(AppTheme.textSecondary)
                    valueRow(label: "Weight (\(weightUnit.fieldLabel.lowercased()))") {
                        weightAndBadges(for: entry)
                    }
                    valueRow(label: "Reps") {
                        repsText(for: entry.set)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(entry.displaySetNumber)")
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 42, alignment: .leading)
                    weightAndBadges(for: entry)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    repsText(for: entry.set)
                        .frame(width: 108, alignment: .trailing)
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(setAccessibilityLabel(for: entry))
        .accessibilityIdentifier("ExerciseHistorySetValue-\(entry.id.uuidString)")
    }

    private func valueRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 12)
            content()
        }
    }

    private func weightAndBadges(for entry: ExerciseHistorySetEntry) -> some View {
        let kinds = records?.kinds(for: entry.id) ?? []
        return VStack(alignment: .trailing, spacing: 3) {
            Text(weightText(for: entry.set))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
            if !kinds.isEmpty {
                ExerciseHistoryRecordBadges(kinds: kinds)
                    .accessibilityHidden(true)
            }
        }
    }

    private func repsText(for set: LoggedSet) -> Text {
        let reps = WorkoutNumericInputPolicy.validatedReps(set.reps).map(String.init) ?? "-"
        var result = Text(reps).foregroundColor(AppTheme.textPrimary)
        if let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe) {
            result = Text(
                "\(result)\(Text(" @ \(WorkoutFormatters.number(rpe))").foregroundColor(AppTheme.textSecondary))"
            )
        }
        return result.monospacedDigit()
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

    private func weightText(for set: LoggedSet) -> String {
        let validWeight = WorkoutNumericInputPolicy.validatedWeight(set.weight)
        return weightUnit.displayWeight(fromCanonicalPounds: validWeight)
            .map(WorkoutFormatters.number) ?? "-"
    }

    private func setAccessibilityLabel(for entry: ExerciseHistorySetEntry) -> String {
        let validWeight = WorkoutNumericInputPolicy.validatedWeight(entry.set.weight)
        let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: validWeight)
        let weightLabel = displayWeight.map {
            "\(WorkoutFormatters.number($0)) \(weightUnit.displayName.lowercased())"
        } ?? "no weight"
        let reps = WorkoutNumericInputPolicy.validatedReps(entry.set.reps)
        let repsLabel = reps.map { "\($0) \($0 == 1 ? "rep" : "reps")" } ?? "no reps"
        let rpe = WorkoutNumericInputPolicy.validatedRPE(entry.set.rpe)
            .map { ", RPE \(WorkoutFormatters.number($0))" } ?? ""
        let badges = (records?.kinds(for: entry.id) ?? []).map(\.title)
        return (["Set \(entry.displaySetNumber), \(weightLabel), \(repsLabel)\(rpe)"] + badges)
            .joined(separator: ", ")
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
