import SwiftData
import SwiftUI

struct ExerciseCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let loggedExercise: LoggedExercise
    let exerciseIndex: Int
    @Bindable var engine: ActiveWorkoutEngine
    @Binding var isCollapsed: Bool
    @Binding var isNoteRevealed: Bool
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
        isNoteRevealed: Binding<Bool>,
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
        self._isNoteRevealed = isNoteRevealed
        self.focusedField = focusedField
        self.weightUnit = weightUnit
        self.previousSets = previousSets
        self.canReorder = canReorder
        self.viewHistory = viewHistory
        self.onReorderExercises = onReorderExercises
        self.onEditRPE = onEditRPE
    }

    var body: some View {
        SurfaceCard(role: .focus, padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
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
                                .foregroundStyle(AppTheme.destructiveForeground)
                        }
                        .tint(AppTheme.destructiveForeground)
                        .accessibilityIdentifier("RemoveExerciseButton-\(exerciseIndex)")
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions[VerticalAlignment.center] + 6
                            }
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
                        if !dynamicTypeSize.isAccessibilitySize {
                            HStack(spacing: 10) {
                                Text("SET")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .frame(width: 28)
                                WorkoutSetColumnHeader(title: "PREVIOUS")
                                WorkoutSetColumnHeader(title: weightUnit.fieldLabel)
                                WorkoutSetColumnHeader(title: "REPS")
                                Text("COMPLETE")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                    .frame(width: 44)
                            }
                            .padding(.horizontal, 16)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(loggedExercise.sortedSets.enumerated()), id: \.element.id) { index, set in
                                if index > 0 {
                                    Divider()
                                        .overlay(AppTheme.subtleBorder)
                                        .padding(.horizontal, 16)
                                }
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

                            Divider()
                                .overlay(AppTheme.subtleBorder)
                        }

                        exerciseActions
                            .padding(.horizontal, 16)

                        if isNoteVisible {
                            Divider()
                                .overlay(AppTheme.subtleBorder)

                            ExerciseNotesDraftField(
                                notes: loggedExercise.notes,
                                exerciseID: loggedExercise.id,
                                exerciseIndex: exerciseIndex,
                                isRevealed: $isNoteRevealed,
                                focusedField: focusedField
                            ) { draft in
                                try? engine.updateExerciseNotes(draft, loggedExercise: loggedExercise, context: modelContext)
                            }
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

    private var exerciseActions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    addSetButton
                    addExerciseNoteButton
                }
            } else {
                HStack(spacing: 12) {
                    addSetButton
                    Spacer(minLength: 8)
                    addExerciseNoteButton
                }
            }
        }
    }

    private var addSetButton: some View {
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
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var addExerciseNoteButton: some View {
        if !isNoteVisible {
            Button {
                isNoteRevealed = true
                Task { @MainActor in
                    await Task.yield()
                    focusedField.wrappedValue = .exerciseNotes(loggedExercise.id)
                }
            } label: {
                Label("Add exercise note", systemImage: "note.text.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AddExerciseNoteButton-\(exerciseIndex)")
        }
    }

    private var isNoteVisible: Bool {
        isNoteRevealed || !loggedExercise.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    @Binding var isRevealed: Bool
    var focusedField: FocusState<WorkoutField?>.Binding
    let commit: (String) -> Void
    @State private var draft: String?

    private var focusTarget: WorkoutField {
        .exerciseNotes(exerciseID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EXERCISE NOTE")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(isFocused ? AppTheme.brandFocus : AppTheme.textTertiary)

            TextField(
                "Exercise notes...",
                text: Binding(
                    get: { draft ?? notes },
                    set: { draft = $0 }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1...6)
            .focused(focusedField, equals: focusTarget)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(minHeight: 44, alignment: .topLeading)
            .workoutInputTapTarget(focusedField, equals: focusTarget)
            .background(
                isFocused ? AnyShapeStyle(AppTheme.brandAccentMuted) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityIdentifier("ExerciseNotesField-\(exerciseIndex)")
            .id(focusTarget)
        }
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onChange(of: focusedField.wrappedValue) { previousField, newField in
            if previousField == focusTarget, newField != focusTarget {
                commitAndUpdateDisclosure()
            }
        }
        .onDisappear {
            commitAndUpdateDisclosure()
        }
    }

    private func commitIfNeeded() {
        guard let draft else { return }
        commit(draft)
        self.draft = nil
    }

    private func commitAndUpdateDisclosure() {
        let shouldHide = currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        commitIfNeeded()
        if shouldHide {
            isRevealed = false
        }
    }

    private var currentText: String {
        draft ?? notes
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == focusTarget
    }
}
