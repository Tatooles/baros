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
                        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                            isCollapsed.toggle()
                        }
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
                        try? engine.removeLoggedExercise(loggedExercise, context: modelContext)
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
                                if let set = try? engine.addSet(to: loggedExercise, context: modelContext) {
                                    focusedField.wrappedValue = set.weight == nil ? .setWeight(set.id) : nil
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        ExerciseNotesDraftField(
                            notes: loggedExercise.notes,
                            exerciseID: loggedExercise.id,
                            exerciseIndex: exerciseIndex,
                            focusedField: focusedField
                        ) { draft in
                            try? engine.updateExerciseNotes(draft, loggedExercise: loggedExercise, context: modelContext)
                        }

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
}

/// Owns the exercise-notes draft so keystrokes re-render only this leaf, not
/// the whole card. Commits (one model write + save) when focus leaves the
/// field or the field disappears (e.g. the card collapses mid-edit).
private struct ExerciseNotesDraftField: View {
    let notes: String
    let exerciseID: UUID
    let exerciseIndex: Int
    var focusedField: FocusState<WorkoutField?>.Binding
    let commit: (String) -> Void
    @State private var draft: String?

    private var focusTarget: WorkoutField {
        .exerciseNotes(exerciseID)
    }

    var body: some View {
        TextField(
            "Exercise notes...",
            text: Binding(
                get: { draft ?? notes },
                set: { draft = $0 }
            ),
            axis: .vertical
        )
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
        .focused(focusedField, equals: focusTarget)
        .padding(14)
        .frame(minHeight: 88, alignment: .topLeading)
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
        guard let draft else { return }
        commit(draft)
        self.draft = nil
    }
}
