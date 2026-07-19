import SwiftData
import SwiftUI

struct WorkoutHistoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    let session: WorkoutSession
    @State private var deleteErrorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var editPresentation: CompletedWorkoutEditPresentation?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    private var allowsHistoryMutation: Bool {
        session.allowsHistoryMutation(ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !allowsHistoryMutation {
                    readOnlyNoticeBanner
                }

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
                                    Text(setSummary(for: set))
                                        .foregroundStyle(set.isCompleted ? AppTheme.accentBright : AppTheme.textSecondary)
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .accessibilityIdentifier("WorkoutHistorySetSummary-\(loggedExercise.orderIndex)-\(set.orderIndex)")
                            }

                            ExerciseHistoryNoteBlock(note: loggedExercise.notes)
                        }
                    }
                }

                if allowsHistoryMutation {
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
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
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsHistoryMutation {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        editPresentation = CompletedWorkoutEditPresentation(session: session)
                    }
                    .accessibilityIdentifier("EditWorkoutButton")
                }
            }
        }
        .sheet(item: $editPresentation) { presentation in
            CompletedWorkoutEditView(
                session: session,
                draft: presentation.draft,
                weightUnit: weightUnit
            )
        }
        .alert("Delete Workout?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWorkout()
            }
        } message: {
            Text("This removes it from your history. This can't be undone.")
        }
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

    private func deleteWorkout() {
        do {
            try WorkoutHistoryMutationService().deleteWorkoutHistory(
                session,
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                context: modelContext
            )
            syncScheduler.requestSync()
            deleteErrorMessage = nil
            dismiss()
        } catch {
            modelContext.rollback()
            deleteErrorMessage = error.localizedDescription
        }
    }

    private var readOnlyNoticeBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentBright)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Read-only workout")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Sign in to the matching account to edit or delete this synced workout.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppTheme.accentBright.opacity(0.4))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("WorkoutHistoryReadOnlyNotice")
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

    private func setSummary(for set: LoggedSet) -> String {
        let weight = weightText(for: set)
        let reps = set.reps.map(String.init) ?? "-"
        let rpe = set.rpe.map { " @ \(WorkoutFormatters.number($0))" } ?? ""
        let status = set.isCompleted ? "Done" : "Open"
        return "\(weight) x \(reps)\(rpe) · \(status)"
    }

    private func weightText(for set: LoggedSet) -> String {
        guard let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: set.weight) else {
            return "-"
        }

        return WorkoutFormatters.number(displayWeight)
    }
}

private struct CompletedWorkoutEditPresentation: Identifiable {
    let id: UUID
    let draft: CompletedWorkoutEditDraft

    init(session: WorkoutSession) {
        id = session.id
        draft = CompletedWorkoutEditDraft(session: session)
    }
}
