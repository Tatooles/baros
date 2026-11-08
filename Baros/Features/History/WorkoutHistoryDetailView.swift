import SwiftData
import SwiftUI

struct WorkoutHistoryDestinationView: View {
    let sessionID: UUID
    /// Only History's navigation stack can push Exercise History routes.
    var linksExercises = false

    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
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
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).first { $0.id == sessionID }
    }

    var body: some View {
        if let session {
            WorkoutHistoryDetailView(session: session, linksExercises: linksExercises)
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
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    let session: WorkoutSession
    var linksExercises = false
    @State private var deleteErrorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var editPresentation: CompletedWorkoutEditPresentation?
    @State private var templateDraft: NewTemplateFromWorkout?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    private var allowsHistoryMutation: Bool {
        session.allowsHistoryMutation(ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier)
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

                VStack(spacing: 12) {
                    ForEach(SupersetGrouping.blocks(session.sortedLoggedExercises, groupID: \.supersetGroupID)) { block in
                        if block.isSuperset {
                            SupersetRail(count: block.members.count, spacing: 12) {
                                ForEach(block.members) { loggedExercise in
                                    workoutExerciseSection(loggedExercise)
                                }
                            }
                        } else {
                            workoutExerciseSection(block.members[0])
                        }
                    }
                }
                .padding(.top, 24)
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
                        if session.visibleExerciseCount > 0 {
                            Button("Save as Template", systemImage: "list.bullet.clipboard") {
                                templateDraft = NewTemplateFromWorkout(session: session)
                            }
                            .accessibilityIdentifier("SaveAsTemplateButton")
                        }
                        Button("Delete Workout", systemImage: "trash", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .tint(AppTheme.destructive)
                    } label: {
                        Label("Workout actions", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("WorkoutHistoryActionsMenu")
                }
            }
        }
        .sheet(item: $templateDraft) { presentation in
            TemplateEditorSheet(newDraft: presentation.draft)
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
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
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
            + "\(WorkoutFormatters.exerciseCount(session.sortedLoggedExercises.count)), "
            + WorkoutFormatters.setCount(metrics.totalSetCount)
    }

    private func workoutExerciseSection(_ loggedExercise: LoggedExercise) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title and equipment read as one identity; the pill rides the
            // title's baseline instead of setting the row height.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    exerciseTitle(loggedExercise)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HistorySetCountPill(count: loggedExercise.sortedSets.count)
                        .accessibilityIdentifier("WorkoutHistorySetCount-\(loggedExercise.orderIndex)")
                }
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
            }, weightUnit: weightUnit, alignedSets: allSets)

            ExerciseHistoryNoteBlock(note: loggedExercise.notes)
        }
        .padding(16)
        .background(AppTheme.groupedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension WorkoutHistoryDetailView {
    /// Every set in the workout, so each exercise's table shares one column grid.
    fileprivate var allSets: [LoggedSet] {
        session.sortedLoggedExercises.flatMap(\.sortedSets)
    }

    /// In History, the exercise name opens that exercise's history.
    @ViewBuilder
    fileprivate func exerciseTitle(_ loggedExercise: LoggedExercise) -> some View {
        let title = Text(loggedExercise.exerciseSnapshotName)
            .font(.title3.bold())
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        if linksExercises, loggedExercise.sortedSets.contains(where: \.isCompleted) {
            NavigationLink(value: HistoryRoute.exercise(ExerciseHistoryRoute(loggedExercise: loggedExercise))) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    title
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens exercise history.")
            .accessibilityIdentifier("WorkoutHistoryExerciseLink-\(loggedExercise.orderIndex)")
        } else {
            title
        }
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
