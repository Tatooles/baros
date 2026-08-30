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
    let draftStore: ActiveWorkoutSetDraftStore
    var focusedField: FocusState<WorkoutField?>.Binding
    let weightUnit: MeasurementUnit
    let previousSets: [PreviousSetPerformance]
    let canReorder: Bool
    let viewHistory: () -> Void
    let onSwapExercise: () -> Void
    let onReorderExercises: () -> Void
    let onEditRPE: (LoggedSet) -> Void
    @State private var showsRemoveConfirmation = false

    init(
        loggedExercise: LoggedExercise,
        exerciseIndex: Int,
        engine: ActiveWorkoutEngine,
        isCollapsed: Binding<Bool>,
        isNoteRevealed: Binding<Bool>,
        draftStore: ActiveWorkoutSetDraftStore,
        focusedField: FocusState<WorkoutField?>.Binding,
        weightUnit: MeasurementUnit,
        previousSets: [PreviousSetPerformance],
        canReorder: Bool,
        viewHistory: @escaping () -> Void,
        onSwapExercise: @escaping () -> Void,
        onReorderExercises: @escaping () -> Void,
        onEditRPE: @escaping (LoggedSet) -> Void
    ) {
        self.loggedExercise = loggedExercise
        self.exerciseIndex = exerciseIndex
        self.engine = engine
        self._isCollapsed = isCollapsed
        self._isNoteRevealed = isNoteRevealed
        self.draftStore = draftStore
        self.focusedField = focusedField
        self.weightUnit = weightUnit
        self.previousSets = previousSets
        self.canReorder = canReorder
        self.viewHistory = viewHistory
        self.onSwapExercise = onSwapExercise
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
                    .id("ExerciseHeaderScroll-\(loggedExercise.id.uuidString)")
                    .accessibilityIdentifier("ExerciseHeader-\(exerciseIndex)")

                    Menu {
                        Button(action: viewHistory) {
                            Label("View History", systemImage: "clock.arrow.circlepath")
                        }
                        .accessibilityIdentifier("ExerciseHistoryButton-\(exerciseIndex)")

                        Button(action: onSwapExercise) {
                            Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityIdentifier("SwapExerciseButton-\(exerciseIndex)")

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
                                Color.clear.frame(width: 28)
                                WorkoutSetColumnHeader(title: "PREVIOUS")
                                WorkoutSetColumnHeader(title: weightUnit.fieldLabel)
                                WorkoutSetColumnHeader(title: "REPS")
                                Color.clear.frame(width: 44)
                            }
                            .padding(.horizontal, 16)
                        }

                        VStack(spacing: 0) {
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
                                        draft: draftStore.draft(for: set.id),
                                        focusedField: focusedField,
                                        weightUnit: weightUnit,
                                        previous: index < previousSetsForRows.count ? previousSetsForRows[index] : nil,
                                        onEditRPE: onEditRPE
                                    )
                                        .padding(.horizontal, 16)
                                }

                                Divider()
                                    .overlay(AppTheme.subtleBorder)
                                    .padding(.horizontal, 16)
                            }

                            addSetButton
                                .padding(.horizontal, 4)

                            Divider()
                                .overlay(AppTheme.subtleBorder)
                        }

                        WorkoutProgressiveNoteControl(
                            notes: loggedExercise.notes,
                            addTitle: "Add exercise note",
                            addSystemImage: "note.text.badge.plus",
                            placeholder: "Exercise notes...",
                            accessibilityLabel: "Exercise note",
                            addAccessibilityIdentifier: "AddExerciseNoteButton-\(exerciseIndex)",
                            fieldAccessibilityIdentifier: "ExerciseNotesField-\(exerciseIndex)",
                            addAccessibilityHint: nil,
                            addButtonHorizontalPadding: 0,
                            focusTarget: .exerciseNotes(loggedExercise.id),
                            isRevealed: $isNoteRevealed,
                            focusedField: focusedField
                        ) { draft in
                            try? engine.updateExerciseNotes(draft, loggedExercise: loggedExercise, context: modelContext)
                        }
                        .padding(.horizontal, 16)
                    }
                    // Content stays put and fades while the clipped card edge
                    // swallows it; a .move transition here reads as jank.
                    .transition(.opacity)
                    .padding(.bottom, 16)
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
    }

    static func setProgress(for loggedExercise: LoggedExercise) -> WorkoutExerciseProgress {
        let visibleSets = loggedExercise.sortedSets
        let completed = visibleSets.filter(\.isCompleted).count
        return WorkoutExerciseProgress(completed: completed, total: visibleSets.count)
    }
}
