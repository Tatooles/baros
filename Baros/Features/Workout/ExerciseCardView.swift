import SwiftData
import SwiftUI

struct ExerciseCardView: View {
    /// The superset menu items that apply to this exercise; nil hides one.
    struct SupersetActions {
        var joinPrevious: (() -> Void)?
        var joinNext: (() -> Void)?
        var remove: (() -> Void)?
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let loggedExercise: LoggedExercise
    let exerciseIndex: Int
    @Bindable var engine: ActiveWorkoutEngine
    @Binding var isCollapsed: Bool
    @Binding var isNoteRevealed: Bool
    let setInputRegistry: ActiveSetInputRegistry
    var focusedField: FocusState<WorkoutField?>.Binding
    let weightUnit: MeasurementUnit
    let previousSets: [PreviousSetPerformance]
    let supersetActions: SupersetActions
    let viewHistory: () -> Void
    let onSwapExercise: () -> Void
    let onEditRPE: (LoggedSet) -> Void
    @State private var showsRemoveConfirmation = false
    @State private var cachedSortedSets: [LoggedSet]?
    @State private var setPreviews: [UUID: ActiveWorkoutSetInput.Values] = [:]

    init(
        loggedExercise: LoggedExercise,
        exerciseIndex: Int,
        engine: ActiveWorkoutEngine,
        isCollapsed: Binding<Bool>,
        isNoteRevealed: Binding<Bool>,
        setInputRegistry: ActiveSetInputRegistry,
        focusedField: FocusState<WorkoutField?>.Binding,
        weightUnit: MeasurementUnit,
        previousSets: [PreviousSetPerformance],
        supersetActions: SupersetActions,
        viewHistory: @escaping () -> Void,
        onSwapExercise: @escaping () -> Void,
        onEditRPE: @escaping (LoggedSet) -> Void
    ) {
        self.loggedExercise = loggedExercise
        self.exerciseIndex = exerciseIndex
        self.engine = engine
        self._isCollapsed = isCollapsed
        self._isNoteRevealed = isNoteRevealed
        self.setInputRegistry = setInputRegistry
        self.focusedField = focusedField
        self.weightUnit = weightUnit
        self.previousSets = previousSets
        self.supersetActions = supersetActions
        self.viewHistory = viewHistory
        self.onSwapExercise = onSwapExercise
        self.onEditRPE = onEditRPE
    }

    private static let menuButtonSize: CGFloat = 44
    // Let the title use a little of the menu's empty leading margin.
    private var titleMenuSpacingAllowance: CGFloat { dynamicTypeSize.isAccessibilitySize ? 0 : 5 }
    @ScaledMetric(relativeTo: .footnote) private var progressPillContentMinWidth = WorkoutExerciseHeaderContent.progressPillContentMinWidth

    /// Insets the menu so its ellipsis is centered over the progress pill below it.
    private var menuButtonTrailingInset: CGFloat {
        let pillWidth = progressPillContentMinWidth + 2 * WorkoutExerciseHeaderContent.progressPillHorizontalPadding
        return max(0, (pillWidth - Self.menuButtonSize) / 2)
    }

    var body: some View {
        let sortedSets = cachedSortedSets ?? loggedExercise.sortedSets
        let focusedFieldValue = focusedField.wrappedValue

        SurfaceCard(role: .focus, padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    WorkoutExerciseHeaderContent(
                        title: loggedExercise.exerciseSnapshotName,
                        metadata: loggedExercise.metadataDisplayText,
                        progress: Self.setProgress(for: sortedSets),
                        isCollapsed: isCollapsed,
                        titleTrailingInset: menuButtonTrailingInset + Self.menuButtonSize - titleMenuSpacingAllowance
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ExerciseHeader-\(exerciseIndex)")
                // The menu overlays the header so the metadata row and its progress pill
                // can run underneath it, leaving the title the full width.
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                    Menu {
                        Button(action: viewHistory) {
                            Label("View History", systemImage: "clock.arrow.circlepath")
                        }
                        .accessibilityIdentifier("ExerciseHistoryButton-\(exerciseIndex)")

                        Button(action: onSwapExercise) {
                            Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityIdentifier("SwapExerciseButton-\(exerciseIndex)")

                        // Join Previous comes first: the superset it joins is above.
                        if let joinPrevious = supersetActions.joinPrevious {
                            Button(action: joinPrevious) {
                                Label("Join Previous Superset", systemImage: "link")
                            }
                            .accessibilityIdentifier("JoinPreviousSupersetButton-\(exerciseIndex)")
                        }

                        if let joinNext = supersetActions.joinNext {
                            Button(action: joinNext) {
                                Label("Superset with Next", systemImage: "link")
                            }
                            .accessibilityIdentifier("SupersetWithNextButton-\(exerciseIndex)")
                        }

                        if let remove = supersetActions.remove {
                            Button(action: remove) {
                                Label("Remove from Superset", systemImage: "minus.circle")
                            }
                            .accessibilityIdentifier("RemoveFromSupersetButton-\(exerciseIndex)")
                        }

                        Button(role: .destructive) {
                            setInputRegistry.commit(focusedField.wrappedValue)
                            guard !engine.hasPendingSetSave else { return }
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
                            .frame(width: Self.menuButtonSize, height: Self.menuButtonSize)
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions[VerticalAlignment.center] + 6
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(loggedExercise.exerciseSnapshotName) options")
                    .accessibilityIdentifier("ExerciseMenuButton-\(exerciseIndex)")
                    .padding(.trailing, menuButtonTrailingInset)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .confirmationDialog(
                    "Remove \(loggedExercise.exerciseSnapshotName)?",
                    isPresented: $showsRemoveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove Exercise", role: .destructive) {
                        guard !engine.hasPendingSetSave else { return }
                        try? engine.removeLoggedExercise(loggedExercise, context: modelContext)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the exercise and its sets from this workout.")
                }

                if !isCollapsed {
                    let previousSetsForRows = previousSets
                    let suggestions = ActiveWorkoutSetSuggestions.resolve(for: sortedSets.map {
                        setPreviews[$0.id] ?? .init(weight: $0.weight, reps: $0.reps)
                    })
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
                                ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                                    SetRowView(
                                        set: set,
                                        setID: set.id,
                                        weight: set.weight,
                                        reps: set.reps,
                                        isCompleted: set.isCompleted,
                                        rpe: set.rpe,
                                        exerciseIndex: exerciseIndex,
                                        index: index,
                                        engine: engine,
                                        setInputRegistry: setInputRegistry,
                                        focusedField: focusedField,
                                        isWeightFocused: focusedFieldValue == .setWeight(set.id),
                                        isRepsFocused: focusedFieldValue == .setReps(set.id),
                                        weightUnit: weightUnit,
                                        previous: index < previousSetsForRows.count ? previousSetsForRows[index] : nil,
                                        suggestions: suggestions[index],
                                        onPreviewChange: { values in
                                            guard setPreviews[set.id] != values else { return }
                                            setPreviews[set.id] = values
                                        },
                                        onEditRPE: onEditRPE
                                    )
                                        .equatable()
                                        .padding(.horizontal, 16)
                                    RestSetDivider(setID: set.id, slot: engine.restTimer.slot(for: set.id), timer: engine.restTimer)
                                        .padding(.horizontal, 16)
                                }
                            }

                            .overlayPreferenceValue(RestGutterAnchorKey.self) { anchors in
                                RestGutterOverlay(anchors: anchors,
                                    slots: sortedSets.map { ($0.id, engine.restTimer.slot(for: $0.id)) },
                                    timer: engine.restTimer)
                            }

                            addSetButton
                                .padding(.horizontal, 4)

                            Divider()
                                .overlay(AppTheme.subtleBorder)
                        }

                        WorkoutProgressiveNoteControl(
                            notes: .constant(loggedExercise.notes),
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
                            focusedField: focusedField,
                            commitOnFocusLoss: { draft in
                                try? engine.updateExerciseNotes(
                                    draft,
                                    loggedExercise: loggedExercise,
                                    context: modelContext
                                )
                            }
                        )
                        .padding(.horizontal, 16)
                    }
                    // Content stays put and fades while the clipped card edge
                    // swallows it; a .move transition here reads as jank.
                    .transition(.opacity)
                    .padding(.bottom, 16)
                }
            }
        }
        .onChange(of: setStructureKey, initial: true) { _, _ in
            cachedSortedSets = loggedExercise.sortedSets
        }
    }

    private var addSetButton: some View {
        WorkoutAddRowButton(
            title: "Add Set",
            accessibilityIdentifier: "AddSetButton-\(exerciseIndex)"
        ) {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                _ = try? engine.addSet(to: loggedExercise, context: modelContext)
            }
        }
    }

    private var setStructureKey: Set<LoggedSetStructureValue> {
        Set(loggedExercise.sets.map(LoggedSetStructureValue.init))
    }

    static func setProgress(for sets: [LoggedSet]) -> WorkoutExerciseProgress {
        let completed = sets.filter(\.isCompleted).count
        return WorkoutExerciseProgress(completed: completed, total: sets.count)
    }

    static func setProgress(for loggedExercise: LoggedExercise) -> WorkoutExerciseProgress {
        setProgress(for: loggedExercise.sortedSets)
    }
}

private struct LoggedSetStructureValue: Hashable {
    let id: UUID
    let orderIndex: Int
    let deletedAt: Date?

    init(_ set: LoggedSet) {
        id = set.id
        orderIndex = set.orderIndex
        deletedAt = set.deletedAt
    }
}
