import SwiftUI

struct ExerciseHistorySessionGroupCard: View {
    let group: ExerciseHistorySessionGroup
    var weightUnit: MeasurementUnit = .pounds
    var showsExerciseNotes: Bool = true

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                header
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
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.surfaceMuted)
                .clipShape(Capsule())
        }
    }

    private var loggedExerciseEntries: some View {
        VStack(spacing: 12) {
            ForEach(Array(group.loggedExerciseEntries.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.loggedExercise.exerciseSnapshotName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        if let metadataDisplayText = entry.loggedExercise.metadataDisplayText {
                            Text(metadataDisplayText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
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
        let weight = weightUnit.displayWeight(fromCanonicalPounds: set.weight).map(WorkoutFormatters.number) ?? "-"
        let reps = set.reps.map(String.init) ?? "-"

        if let rpe = set.rpe {
            return "\(weight) x \(reps) @ \(WorkoutFormatters.number(rpe))"
        }

        return "\(weight) x \(reps)"
    }

    private func setCountLabel(for count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }
}
