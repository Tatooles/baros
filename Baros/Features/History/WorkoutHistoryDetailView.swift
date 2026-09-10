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
                        .padding(.bottom, 20)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(WorkoutFormatters.compactDate(session.startedAt))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("WorkoutHistoryHeading")

                Text(summaryText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 15)
                    .accessibilityLabel(summaryAccessibilityLabel)
                    .accessibilityIdentifier("WorkoutHistorySummary")

                if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(session.notes)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                        .accessibilityIdentifier("WorkoutHistoryNoteText")
                }

                ForEach(Array(session.sortedLoggedExercises.enumerated()), id: \.element.id) { _, loggedExercise in
                    workoutExerciseSection(loggedExercise)
                }

                if allowsHistoryMutation {
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Text("Delete Workout")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.destructiveForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.destructiveForeground)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("")
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
                .foregroundStyle(AppTheme.brandAccentForeground)
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
                .strokeBorder(AppTheme.brandAccentForeground.opacity(0.4))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("WorkoutHistoryReadOnlyNotice")
    }

    private var summaryText: String {
        "\(AppTheme.formatDuration(metrics.durationSeconds)) · "
            + "\(session.sortedLoggedExercises.count) \(exerciseCountLabel) · "
            + "\(metrics.totalSetCount) \(setCountLabel)"
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
        VStack(alignment: .leading, spacing: 13) {
            Divider()
                .overlay(AppTheme.subtleBorder)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(loggedExercise.exerciseSnapshotName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .fixedSize(horizontal: false, vertical: true)

                if let metadataDisplayText = loggedExercise.metadataDisplayText {
                    Text(metadataDisplayText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                setColumnHeadings
            }

            VStack(spacing: 10) {
                ForEach(loggedExercise.sortedSets) { set in
                    workoutSetRow(set, exerciseOrderIndex: loggedExercise.orderIndex)
                }
            }

            ExerciseHistoryNoteBlock(note: loggedExercise.notes)
        }
        .padding(.top, 20)
    }

    private var setColumnHeadings: some View {
        HStack(spacing: 12) {
            Text("Set")
                .frame(width: 54, alignment: .leading)
            Text("Weight (\(weightUnit.fieldLabel.lowercased()))")
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("Reps")
                .frame(width: 112, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary)
        .accessibilityElement(children: .combine)
    }

    private func workoutSetRow(_ set: LoggedSet, exerciseOrderIndex: Int) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set \(set.orderIndex + 1)")
                        .foregroundStyle(AppTheme.textSecondary)
                    accessibleValueRow(label: "Weight (\(weightUnit.fieldLabel.lowercased()))") {
                        Text(weightText(for: set))
                    }
                    accessibleValueRow(label: "Reps") {
                        repsText(for: set)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(set.orderIndex + 1)")
                        .monospacedDigit()
                        .frame(width: 54, alignment: .leading)

                    Text(weightText(for: set))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    repsText(for: set)
                        .frame(width: 112, alignment: .trailing)
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(setAccessibilityLabel(for: set))
        .accessibilityIdentifier("WorkoutHistorySetSummary-\(exerciseOrderIndex)-\(set.orderIndex)")
    }

    private func accessibleValueRow<Content: View>(
        label: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 12)
            value()
        }
    }

    private func repsText(for set: LoggedSet) -> Text {
        let reps = WorkoutNumericInputPolicy.validatedReps(set.reps).map(String.init) ?? "-"
        var result = Text(reps)
            .foregroundColor(AppTheme.textPrimary)

        if let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe) {
            result = Text(
                "\(result)\(Text(" @ \(WorkoutFormatters.number(rpe))").foregroundColor(AppTheme.textSecondary))"
            )
        }

        return result.monospacedDigit()
    }

    private func setAccessibilityLabel(for set: LoggedSet) -> String {
        let validWeight = WorkoutNumericInputPolicy.validatedWeight(set.weight)
        let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: validWeight)
        let weightLabel = displayWeight.map {
            "\(WorkoutFormatters.number($0)) \(weightUnit.displayName.lowercased())"
        } ?? "no weight"
        let reps = WorkoutNumericInputPolicy.validatedReps(set.reps)
        let repsLabel = reps.map { "\($0) \($0 == 1 ? "rep" : "reps")" } ?? "no reps"
        let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe)
            .map { ", RPE \(WorkoutFormatters.number($0))" } ?? ""
        return "Set \(set.orderIndex + 1), \(weightLabel), \(repsLabel)\(rpe)"
    }

    private func weightText(for set: LoggedSet) -> String {
        let validWeight = WorkoutNumericInputPolicy.validatedWeight(set.weight)
        guard let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: validWeight) else {
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
