import SwiftData
import SwiftUI

struct ExerciseHistoryDetailView: View {
    let summary: ExerciseHistorySummary
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var sessionGroups: [ExerciseHistorySessionGroup] {
        ExerciseHistorySessionGroup.makeGroups(from: sessions, matching: summary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last performed \(summary.lastPerformedLabel)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Completed Sets")
                            .font(.system(size: 16, weight: .bold))
                        Text("\(summary.completedSetCount) tracked sets across completed workouts.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                ForEach(sessionGroups) { group in
                    sessionGroupCard(group)
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sessionGroupCard(_ group: ExerciseHistorySessionGroup) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
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

                ForEach(group.setEntries) { entry in
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
    }

    private func setSummary(for set: LoggedSet) -> String {
        let weight = set.weight.map(WorkoutFormatters.number) ?? "-"
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
