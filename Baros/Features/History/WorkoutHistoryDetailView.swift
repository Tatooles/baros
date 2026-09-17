import SwiftData
import SwiftUI

struct WorkoutHistoryDestinationView: View {
    let sessionID: UUID

    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(
        filter: #Predicate<WorkoutSession> { session in
            session.statusRaw == "completed"
        },
        sort: \WorkoutSession.startedAt,
        order: .reverse
    ) private var sessions: [WorkoutSession]

    private var session: WorkoutSession? {
        WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first { $0.id == sessionID }
    }

    var body: some View {
        if let session {
            WorkoutHistoryDetailView(session: session)
        } else {
            EmptyStateView(
                title: "Workout Unavailable",
                message: "This workout is no longer available in History."
            )
            .background(AppTheme.canvasBackground.ignoresSafeArea())
        }
    }
}

struct WorkoutHistoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    let session: WorkoutSession
    @State private var deleteErrorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var editPresentation: CompletedWorkoutEditPresentation?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            VStack(alignment: .leading, spacing: 0) {
                if !allowsHistoryMutation {
                    readOnlyNoticeBanner
                        .padding(.bottom, 24)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(WorkoutFormatters.compactDate(session.startedAt))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("WorkoutHistoryHeading")

                summaryStats
                    .padding(.top, 24)

                if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(session.notes)
                        .font(.body.italic())
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)
                        .accessibilityIdentifier("WorkoutHistoryNoteText")
                }

                ForEach(Array(session.sortedLoggedExercises.enumerated()), id: \.element.id) { _, loggedExercise in
                    workoutExerciseSection(loggedExercise)
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsHistoryMutation {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Edit") {
                        editPresentation = CompletedWorkoutEditPresentation(session: session)
                    }
                    .accessibilityIdentifier("EditWorkoutButton")

                    Menu {
                        Button("Delete Workout", systemImage: "trash", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    } label: {
                        Label("Workout actions", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("WorkoutHistoryActionsMenu")
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
                .foregroundStyle(AppTheme.textSecondary)
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
                .strokeBorder(AppTheme.subtleBorder)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("WorkoutHistoryReadOnlyNotice")
    }

    private var summaryStats: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            stat("Duration", value: AppTheme.formatDuration(metrics.durationSeconds))
            stat("Exercises", value: "\(session.sortedLoggedExercises.count)")
            stat("Sets", value: "\(metrics.totalSetCount)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryAccessibilityLabel)
        .accessibilityIdentifier("WorkoutHistorySummary")
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryAccessibilityLabel: String {
        "\(AppTheme.formatDuration(metrics.durationSeconds)), "
            + "\(session.sortedLoggedExercises.count) \(exerciseCountLabel), "
            + "\(metrics.totalSetCount) \(setCountLabel)"
    }

    private var exerciseCountLabel: String {
        session.sortedLoggedExercises.count == 1 ? "exercise" : "exercises"
    }

    private var setCountLabel: String {
        metrics.totalSetCount == 1 ? "set" : "sets"
    }

    private func workoutExerciseSection(_ loggedExercise: LoggedExercise) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(loggedExercise.exerciseSnapshotName)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let metadata = loggedExercise.metadataDisplayText {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            HistorySetTable(rows: loggedExercise.sortedSets.map { set in
                HistorySetTable.Row(
                    set: set,
                    number: set.orderIndex + 1,
                    accessibilityIdentifier: "WorkoutHistorySetSummary-\(loggedExercise.orderIndex)-\(set.orderIndex)"
                )
            }, weightUnit: weightUnit)

            ExerciseHistoryNoteBlock(note: loggedExercise.notes, presentation: .openJournal)
        }
        .padding(.top, 32)
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
