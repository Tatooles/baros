import SwiftData
import SwiftUI

struct ExerciseCardView: View {
    @Environment(\.modelContext) private var modelContext
    let loggedExercise: LoggedExercise
    let exerciseIndex: Int
    @Bindable var engine: ActiveWorkoutEngine
    @Binding var isCollapsed: Bool
    var focusedField: FocusState<WorkoutField?>.Binding
    let weightUnit: MeasurementUnit
    let previousSets: [PreviousSetPerformance]
    let canReorder: Bool
    let viewHistory: () -> Void
    let onReorderExercises: () -> Void
    let onEditRPE: (LoggedSet) -> Void
    @State private var showsRemoveConfirmation = false
    @State private var exerciseNotesDraft = RetryableWorkoutFieldDraft<String>()

    init(
        loggedExercise: LoggedExercise,
        exerciseIndex: Int,
        engine: ActiveWorkoutEngine,
        isCollapsed: Binding<Bool>,
        focusedField: FocusState<WorkoutField?>.Binding,
        weightUnit: MeasurementUnit,
        previousSets: [PreviousSetPerformance],
        canReorder: Bool,
        viewHistory: @escaping () -> Void,
        onReorderExercises: @escaping () -> Void,
        onEditRPE: @escaping (LoggedSet) -> Void
    ) {
        self.loggedExercise = loggedExercise
        self.exerciseIndex = exerciseIndex
        self.engine = engine
        self._isCollapsed = isCollapsed
        self.focusedField = focusedField
        self.weightUnit = weightUnit
        self.previousSets = previousSets
        self.canReorder = canReorder
        self.viewHistory = viewHistory
        self.onReorderExercises = onReorderExercises
        self.onEditRPE = onEditRPE
    }

    var body: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        toggleCollapse()
                    } label: {
                        HStack(spacing: 12) {
                            WorkoutExerciseHeaderContent(
                                title: loggedExercise.exerciseSnapshotName,
                                metadata: loggedExercise.metadataDisplayText,
                                progress: Self.setProgress(for: loggedExercise),
                                isCollapsed: isCollapsed
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ExerciseHeader-\(exerciseIndex)")

                    Menu {
                        Button(action: viewHistory) {
                            Label("View History", systemImage: "clock.arrow.circlepath")
                        }
                        .accessibilityIdentifier("ExerciseHistoryButton-\(exerciseIndex)")

                        if canReorder {
                            Button(action: onReorderExercises) {
                                Label("Reorder Exercises", systemImage: "arrow.up.arrow.down")
                            }
                            .accessibilityIdentifier("ReorderExercisesButton-\(exerciseIndex)")
                        }

                        Button(role: .destructive) {
                            showsRemoveConfirmation = true
                        } label: {
                            Label("Remove Exercise", systemImage: "trash")
                        }
                        .accessibilityIdentifier("RemoveExerciseButton-\(exerciseIndex)")
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(loggedExercise.exerciseSnapshotName) options")
                    .accessibilityIdentifier("ExerciseMenuButton-\(exerciseIndex)")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .confirmationDialog(
                    "Remove \(loggedExercise.exerciseSnapshotName)?",
                    isPresented: $showsRemoveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove Exercise", role: .destructive) {
                        do {
                            try engine.removeLoggedExercise(loggedExercise, context: modelContext)
                        } catch {
                            presentSaveError(error)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the exercise and its sets from this workout.")
                }

                if !isCollapsed {
                    let previousSetsForRows = previousSets
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Color.clear.frame(width: 18)
                            WorkoutSetColumnHeader(title: "PREVIOUS")
                            WorkoutSetColumnHeader(title: weightUnit.fieldLabel)
                            WorkoutSetColumnHeader(title: "REPS")
                            Color.clear.frame(width: 44)
                        }
                        .padding(.horizontal, 16)

                        VStack(spacing: 10) {
                            ForEach(Array(loggedExercise.sortedSets.enumerated()), id: \.element.id) { index, set in
                                SetRowView(
                                    set: set,
                                    exerciseIndex: exerciseIndex,
                                    index: index,
                                    engine: engine,
                                    focusedField: focusedField,
                                    weightUnit: weightUnit,
                                    previous: index < previousSetsForRows.count ? previousSetsForRows[index] : nil,
                                    onEditRPE: onEditRPE
                                )
                                    .padding(.horizontal, 16)
                            }
                        }

                        WorkoutAddRowButton(
                            title: "Add Set",
                            accessibilityIdentifier: "AddSetButton-\(exerciseIndex)"
                        ) {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                                do {
                                    let set = try engine.addSet(to: loggedExercise, context: modelContext)
                                    focusedField.wrappedValue = set.weight == nil ? .setWeight(set.id) : nil
                                } catch {
                                    presentSaveError(error)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        ExerciseNotesDraftField(
                            notes: loggedExercise.notes,
                            exerciseID: loggedExercise.id,
                            exerciseIndex: exerciseIndex,
                            focusedField: focusedField,
                            draft: $exerciseNotesDraft,
                            commit: { draft in
                                try engine.updateExerciseNotes(
                                    draft,
                                    loggedExercise: loggedExercise,
                                    context: modelContext
                                )
                            },
                            onFailure: presentSaveError
                        )

                        if let referenceNotes {
                            VStack(alignment: .leading, spacing: 6) {
                                Divider()
                                    .overlay(AppTheme.border)
                                    .padding(.bottom, 4)

                                Text("LAST TIME")
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.4)
                                    .foregroundStyle(AppTheme.textTertiary)
                                Text(referenceNotes)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    // Content stays put and fades while the clipped card edge
                    // swallows it; a .move transition here reads as jank.
                    .transition(.opacity)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var referenceNotes: String? {
        let trimmed = loggedExercise.referenceNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setProgress(for loggedExercise: LoggedExercise) -> WorkoutExerciseProgress {
        let visibleSets = loggedExercise.sortedSets
        let completed = visibleSets.filter(\.isCompleted).count
        return WorkoutExerciseProgress(completed: completed, total: visibleSets.count)
    }

    private func presentSaveError(_ error: Error) {
        engine.lastErrorMessage = error.localizedDescription
    }

    private func toggleCollapse() {
        if !isCollapsed {
            let shouldCollapse = ExerciseNotesCollapsePolicy.shouldCollapse(
                commit: {
                    try exerciseNotesDraft.commit { draft in
                        try engine.updateExerciseNotes(
                            draft,
                            loggedExercise: loggedExercise,
                            context: modelContext
                        )
                    }
                },
                onFailure: presentSaveError
            )
            guard shouldCollapse else { return }
        }

        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
            isCollapsed.toggle()
        }
    }
}

/// Edits the card-owned exercise-notes draft and commits one model write + save
/// when focus leaves the field or the field disappears. The card owns the draft
/// so collapsing this subtree cannot destroy text after a failed save.
private struct ExerciseNotesDraftField: View {
    let notes: String
    let exerciseID: UUID
    let exerciseIndex: Int
    var focusedField: FocusState<WorkoutField?>.Binding
    @Binding var draft: RetryableWorkoutFieldDraft<String>
    let commit: (String) throws -> Void
    let onFailure: (Error) -> Void

    private var focusTarget: WorkoutField {
        .exerciseNotes(exerciseID)
    }

    var body: some View {
        TextField(
            "Exercise notes...",
            text: Binding(
                get: { draft.value ?? notes },
                set: { draft.value = $0 }
            ),
            axis: .vertical
        )
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
        .focused(focusedField, equals: focusTarget)
        .padding(14)
        .frame(minHeight: 88, alignment: .topLeading)
        .workoutInputTapTarget(focusedField, equals: focusTarget)
        .background(
            AppTheme.fieldFill,
            in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                .strokeBorder(
                    focusedField.wrappedValue == focusTarget ? AppTheme.accentBright.opacity(0.7) : .clear,
                    lineWidth: 1.5
                )
        )
        .animation(.easeOut(duration: 0.15), value: focusedField.wrappedValue == focusTarget)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("ExerciseNotesField-\(exerciseIndex)")
        .id(focusTarget)
        .onChange(of: focusedField.wrappedValue) { previousField, newField in
            if previousField == focusTarget, newField != focusTarget {
                commitIfNeeded()
            }
        }
        .onDisappear {
            commitIfNeeded()
        }
    }

    private func commitIfNeeded() {
        do {
            try draft.commit(commit)
        } catch {
            onFailure(error)
        }
    }
}
