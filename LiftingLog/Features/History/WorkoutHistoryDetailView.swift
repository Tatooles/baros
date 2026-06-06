import SwiftData
import SwiftUI

struct WorkoutHistoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    @State private var deleteErrorMessage: String?

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(WorkoutFormatters.compactDate(session.startedAt))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 10) {
                    metricCard(title: "Duration", value: AppTheme.formatDuration(metrics.durationSeconds))
                    metricCard(title: "Exercises", value: "\(session.sortedLoggedExercises.count)")
                    metricCard(title: "Sets", value: "\(metrics.completedSetCount)")
                }

                if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.system(size: 16, weight: .bold))
                            Text(session.notes)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("WorkoutHistoryNotesCard")
                }

                ForEach(session.sortedLoggedExercises) { loggedExercise in
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loggedExercise.exerciseSnapshotName)
                                    .font(.system(size: 18, weight: .bold))
                                if let metadataDisplayText = loggedExercise.metadataDisplayText {
                                    Text(metadataDisplayText)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }

                            ForEach(loggedExercise.sortedSets) { set in
                                HStack {
                                    Text("Set \(set.orderIndex + 1)")
                                    Spacer()
                                    Text(set.weight.map(WorkoutFormatters.number) ?? "-")
                                    Text("x")
                                    Text(set.reps.map(String.init) ?? "-")
                                    Text(set.isCompleted ? "Done" : "Open")
                                        .foregroundStyle(set.isCompleted ? AppTheme.accentBright : AppTheme.textSecondary)
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            }

                            ExerciseHistoryNoteBlock(note: loggedExercise.notes)
                        }
                    }
                }

                Button(role: .destructive) {
                    do {
                        try WorkoutHistoryMutationService().deleteWorkoutHistory(session, context: modelContext)
                        deleteErrorMessage = nil
                        dismiss()
                    } catch {
                        modelContext.rollback()
                        deleteErrorMessage = error.localizedDescription
                    }
                } label: {
                    Text("Delete Workout")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.accentBright)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.accentBright.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn't Delete Workout",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Try deleting again.")
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        SurfaceCard {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
