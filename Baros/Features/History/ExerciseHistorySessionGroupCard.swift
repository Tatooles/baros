import SwiftUI

struct ExerciseHistoryHeading: View {
    let name: String
    let metadata: String?
    let performanceSummary: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.accentMuted)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(AppTheme.accentBright)
                            .accessibilityHidden(true)
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
                            .lineLimit(1)
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
    var showsExerciseNotes: Bool = true

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                header

                Divider()
                    .overlay(AppTheme.border)

                loggedExerciseEntries
            }
        }
    }

    private var header: some View {
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
                .foregroundStyle(AppTheme.accentBright)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.accentMuted)
                .clipShape(Capsule())
        }
    }

    private var loggedExerciseEntries: some View {
        VStack(spacing: 12) {
            ForEach(Array(group.loggedExerciseEntries.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 10) {
                    if entry.showsIdentity(comparedTo: headingIdentity) {
                        entryIdentity(entry.displayIdentity)
                    }

                    setRows(for: entry.setEntries)

                    if showsExerciseNotes {
                        ExerciseHistoryNoteBlock(note: entry.exerciseNotes)
                    }
                }

                if index < group.loggedExerciseEntries.count - 1 {
                    Divider()
                        .overlay(AppTheme.border)
                }
            }
        }
    }

    private func entryIdentity(_ identity: ExerciseHistoryDisplayIdentity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(identity.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            if let metadataDisplayText = identity.metadataDisplayText {
                Text(metadataDisplayText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func setRows(for entries: [ExerciseHistorySetEntry]) -> some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                HStack {
                    Text("Set \(entry.displaySetNumber)")
                    Spacer()
                    Text(setSummary(for: entry.set))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            }
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

    private func setCountLabel(for count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }
}
