import BarosCore
import SwiftData
import SwiftUI

struct CompletedWorkoutEditView: View {
    @AppStorage(RPEPreference.storageKey) private var rpeEnabled = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @ScaledMetric(relativeTo: .headline) private var scaledActionHeight: CGFloat = 50

    let session: WorkoutSession
    let weightUnit: MeasurementUnit
    private let initialDate: Date
    private let initialDurationSeconds: Int
    private let initialDurationSelection: CompletedWorkoutDurationSelection
    @State private var draft: CompletedWorkoutEditDraft
    @State private var durationSelection: CompletedWorkoutDurationSelection
    @State private var hasEditedDuration = false
    @State private var isDurationEditorPresented = false
    @State private var isAddExercisePresented = false
    @State private var isReorderPresented = false
    @State private var swappingExercise: CompletedWorkoutEditExerciseDraft?
    @State private var exerciseRemovalCandidate: CompletedWorkoutEditExerciseDraft?
    @State private var numberInputTexts: [CompletedWorkoutEditFocusedField: WorkoutNumberInputText] = [:]
    @State private var revealedExerciseNoteIDs: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var removalCandidate: CompletedWorkoutSetRemovalCandidate?
    @State private var timeEdit: CompletedWorkoutSetTimeEdit?
    @FocusState private var focusedField: CompletedWorkoutEditFocusedField?

    init(session: WorkoutSession, draft: CompletedWorkoutEditDraft, weightUnit: MeasurementUnit) {
        self.session = session
        self.weightUnit = weightUnit
        initialDate = draft.date
        initialDurationSeconds = draft.durationSeconds
        initialDurationSelection = CompletedWorkoutDurationSelection(seconds: draft.durationSeconds)
        _draft = State(initialValue: draft)
        _durationSelection = State(initialValue: CompletedWorkoutDurationSelection(seconds: draft.durationSeconds))
    }

    private var showsRPE: Bool {
        rpeEnabled || session.sortedLoggedExercises.contains { exercise in
            exercise.sortedSets.contains { WorkoutNumericInputPolicy.validatedRPE($0.rpe) != nil }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    workoutHeader

                    WorkoutNotesField(
                        title: "NOTES",
                        placeholder: "How did this session feel? Any notes for next time...",
                        text: $draft.notes,
                        focusTarget: .notes,
                        focusedField: $focusedField,
                        accessibilityIdentifier: "CompletedWorkoutNotesField"
                    )

                    let groupIDs = draft.exercises.map(\.supersetGroupID)
                    let exerciseIndexes = Dictionary(
                        uniqueKeysWithValues: draft.exercises.enumerated().map { ($1.id, $0) }
                    )
                    ForEach(SupersetGrouping.blocks(draft.exercises, groupID: \.supersetGroupID)) { block in
                        if block.isSuperset {
                            SupersetRail(count: block.members.count) {
                                ForEach(block.members) { exercise in
                                    exerciseEditor(
                                        exercise,
                                        exerciseIndex: exerciseIndexes[exercise.id] ?? 0,
                                        groupIDs: groupIDs
                                    )
                                }
                            }
                        } else {
                            exerciseEditor(
                                block.members[0],
                                exerciseIndex: exerciseIndexes[block.id] ?? 0,
                                groupIDs: groupIDs
                            )
                        }
                    }

                    exerciseActions
                }
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .revealsSetTimeCell(editing: timeEdit?.id)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if timeEdit != nil, focusedField == nil {
                    HStack {
                        Spacer()
                        Button("Done") { endTimeEdit() }
                            .font(.system(size: 16, weight: .semibold))
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("DoneSetTimeButton")
                    }
                    .padding(.horizontal, AppTheme.shellPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                }
            }
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .accessibilityIdentifier("SaveCompletedWorkoutEditButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .accessibilityIdentifier("DismissKeyboardButton")
                }
            }
            .sheet(isPresented: $isDurationEditorPresented) {
                CompletedWorkoutDurationEditor(
                    selection: $durationSelection,
                    hasEditedDuration: $hasEditedDuration
                )
            }
            .sheet(isPresented: $isAddExercisePresented) {
                NavigationStack {
                    ExercisePickerView(
                        mode: .add(existingExerciseIDs: draft.exerciseIDs)
                    ) { exercises, asSuperset in
                        withAnimation(.snappy) {
                            draft.appendExercises(
                                exercises,
                                asSuperset: asSuperset,
                                history: exerciseHistory(),
                                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
                            )
                        }
                        isAddExercisePresented = false
                    }
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $isReorderPresented) {
                CompletedWorkoutReorderSheet(draft: draft) { reordered in
                    let keptIDs = Set(reordered.exercises.map(\.id))
                    for exercise in draft.exercises where !keptIDs.contains(exercise.id) {
                        forgetInputState(for: exercise.id)
                    }
                    withAnimation(.snappy) {
                        draft = reordered
                    }
                }
            }
            .sheet(item: $swappingExercise) { exercise in
                CompletedWorkoutSwapExerciseSheet(exercise: exercise) { replacement in
                    withAnimation(.snappy) {
                        swap(exercise, with: replacement)
                    }
                }
            }
            .confirmationDialog(
                "Remove \(exerciseRemovalCandidate?.name ?? "Exercise")?",
                isPresented: Binding(
                    get: { exerciseRemovalCandidate != nil },
                    set: { isPresented in
                        if !isPresented {
                            exerciseRemovalCandidate = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: exerciseRemovalCandidate
            ) { exercise in
                Button("Remove Exercise", role: .destructive) {
                    withAnimation(.snappy) {
                        removeExercise(exercise)
                    }
                }
                .accessibilityIdentifier("ConfirmRemoveHistoryExerciseButton")
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the exercise and its sets from this workout when you save.")
            }
            .alert(
                "Remove Set?",
                isPresented: Binding(
                    get: { removalCandidate != nil },
                    set: { isPresented in
                        if !isPresented {
                            removalCandidate = nil
                        }
                    }
                )
            ) {
                Button("Remove", role: .destructive) {
                    if let removalCandidate {
                        removeSet(removalCandidate)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes set \(removalCandidate?.displayNumber ?? 1) from the completed workout.")
            }
            .alert(
                "Couldn't Save Workout",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Try saving again.")
            }
            .onChange(of: focusedField) { previousField, newField in
                if newField != nil { endTimeEdit() }
                guard let previousField, previousField != newField else { return }

                switch previousField {
                case .setWeight, .setReps, .setRPE:
                    numberInputTexts[previousField]?.endEditing()
                case .title, .notes, .exerciseNotes:
                    break
                }
            }
        }
    }

    private var workoutHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledWorkoutTitleField(
                label: "WORKOUT NAME",
                placeholder: "Workout Name",
                text: $draft.title,
                focusTarget: .title,
                focusedField: $focusedField,
                accessibilityIdentifier: "CompletedWorkoutTitleField",
                labelIdentifier: "CompletedWorkoutTitleLabel",
                editAffordanceIdentifier: "CompletedWorkoutTitleEditAffordance"
            )

            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                Text("Date")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                DatePicker(
                    "Date",
                    selection: $draft.date,
                    in: ...datePickerMaximum,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.calendar, draft.calendar)
                .environment(\.timeZone, draft.calendar.timeZone)
                .accessibilityIdentifier("CompletedWorkoutDatePicker")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(
                AppTheme.fieldSurface,
                in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
            )

            Button {
                focusedField = nil
                isDurationEditorPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                    Text("Duration")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text(durationDisplayText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(
                    AppTheme.fieldSurface,
                    in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Duration \(durationDisplayText)")
            .accessibilityIdentifier("CompletedWorkoutDurationButton")
        }
        .padding(.horizontal, 4)
    }

    /// Mirrors the Active Workout's Edit and Add Exercise actions.
    private var exerciseActions: some View {
        let actionHeight = max(50, scaledActionHeight)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if draft.exercises.count > 1 {
                Button {
                    focusedField = nil
                    endTimeEdit()
                    isReorderPresented = true
                } label: {
                    Label("Reorder", systemImage: "arrow.up.arrow.down")
                        .font(.headline)
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .fixedSize()
                        .padding(.horizontal, 20)
                        .frame(minWidth: 108, minHeight: actionHeight)
                        .background(AppTheme.fieldSurface, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ReorderHistoryExercisesButton")
            }

            Button {
                focusedField = nil
                endTimeEdit()
                isAddExercisePresented = true
            } label: {
                Label("Add Exercise", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(maxWidth: .infinity, minHeight: actionHeight)
                    .background(AppTheme.brandAccentMuted, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AddHistoryExerciseButton")
        }
    }

    private var durationDisplayText: String {
        hasDurationChange ? durationSelection.displayText : AppTheme.formatDuration(initialDurationSeconds)
    }

    private var datePickerMaximum: Date {
        max(initialDate, draft.calendar.startOfDay(for: .now))
    }

    private var hasDurationChange: Bool {
        hasEditedDuration && durationSelection != initialDurationSelection
    }

    private static let menuButtonSize: CGFloat = 44

    private func exerciseEditor(
        _ exercise: CompletedWorkoutEditExerciseDraft,
        exerciseIndex: Int,
        groupIDs: [UUID?]
    ) -> some View {
        let exerciseID = exercise.id

        return SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                WorkoutExerciseHeaderContent(
                    title: exercise.exerciseSnapshotName,
                    metadata: exercise.metadataDisplayText,
                    progress: exerciseProgress(for: exercise),
                    isCollapsed: nil,
                    titleTrailingInset: Self.menuButtonSize
                )
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                    exerciseMenu(exercise, exerciseIndex: exerciseIndex, groupIDs: groupIDs)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 18)
                        WorkoutSetColumnHeader(title: weightUnit.fieldLabel)
                        WorkoutSetColumnHeader(title: exercise.trackingMethod.fieldLabel)
                        if showsRPE { WorkoutSetColumnHeader(title: "RPE") }
                        Color.clear.frame(width: 44)
                        Color.clear.frame(width: 34)
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        let setIndices = visibleSetIndices(in: exercise)
                        ForEach(Array(setIndices.enumerated()), id: \.element) { visibleIndex, setIndex in
                            setEditor(
                                exerciseID: exerciseID,
                                exerciseIndex: exerciseIndex,
                                setIndex: setIndex,
                                visibleIndex: visibleIndex
                            )
                            .padding(.horizontal, 16)
                        }
                    }

                    WorkoutAddRowButton(
                        title: "Add Set",
                        accessibilityIdentifier: "AddHistorySetButton-\(exerciseIndex)"
                    ) {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                            addSet(to: exerciseID)
                        }
                    }
                    .padding(.horizontal, 16)

                    Divider()
                        .overlay(AppTheme.subtleBorder)
                        .padding(.horizontal, 16)

                    WorkoutProgressiveNoteControl(
                        notes: exerciseNotesBinding(exerciseID: exerciseID),
                        addTitle: "Add exercise note",
                        addSystemImage: "note.text.badge.plus",
                        placeholder: "Exercise notes...",
                        accessibilityLabel: "Exercise note",
                        addAccessibilityIdentifier: "AddCompletedWorkoutExerciseNoteButton-\(exerciseIndex)",
                        fieldAccessibilityIdentifier: "CompletedWorkoutExerciseNotesField-\(exerciseIndex)",
                        addAccessibilityHint: nil,
                        addButtonHorizontalPadding: 0,
                        focusTarget: .exerciseNotes(exerciseID),
                        isRevealed: exerciseNoteRevealBinding(exerciseID: exerciseID),
                        focusedField: $focusedField
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func exerciseMenu(
        _ exercise: CompletedWorkoutEditExerciseDraft,
        exerciseIndex: Int,
        groupIDs: [UUID?]
    ) -> some View {
        Menu {
            Button {
                focusedField = nil
                endTimeEdit()
                swappingExercise = exercise
            } label: {
                Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("SwapHistoryExerciseButton-\(exerciseIndex)")

            // Each link action shows unless that neighbor is already in this
            // exercise's superset. Join Previous comes first: it joins upward.
            if exerciseIndex > 0, !SupersetGrouping.areGrouped(groupIDs, exerciseIndex, exerciseIndex - 1) {
                Button {
                    changeSuperset(.joinPrevious, for: exercise)
                } label: {
                    Label("Join Previous Superset", systemImage: "link")
                }
                .accessibilityIdentifier("JoinPreviousHistorySupersetButton-\(exerciseIndex)")
            }

            if exerciseIndex + 1 < groupIDs.count,
               !SupersetGrouping.areGrouped(groupIDs, exerciseIndex, exerciseIndex + 1) {
                Button {
                    changeSuperset(.joinNext, for: exercise)
                } label: {
                    Label("Superset with Next", systemImage: "link")
                }
                .accessibilityIdentifier("HistorySupersetWithNextButton-\(exerciseIndex)")
            }

            if SupersetGrouping.isGrouped(groupIDs, at: exerciseIndex) {
                Button {
                    changeSuperset(.remove, for: exercise)
                } label: {
                    Label("Remove from Superset", systemImage: "minus.circle")
                }
                .accessibilityIdentifier("RemoveFromHistorySupersetButton-\(exerciseIndex)")
            }

            Button(role: .destructive) {
                focusedField = nil
                endTimeEdit()
                exerciseRemovalCandidate = exercise
            } label: {
                Label("Remove Exercise", systemImage: "trash")
                    .foregroundStyle(AppTheme.destructiveForeground)
            }
            .tint(AppTheme.destructiveForeground)
            .accessibilityIdentifier("RemoveHistoryExerciseButton-\(exerciseIndex)")
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
        .accessibilityLabel("\(exercise.name) options")
        .accessibilityIdentifier("HistoryExerciseMenuButton-\(exerciseIndex)")
    }

    @ViewBuilder
    private func setEditor(exerciseID: UUID, exerciseIndex: Int, setIndex: Int, visibleIndex: Int) -> some View {
        if let set = draftSet(exerciseID: exerciseID, setIndex: setIndex) {
            let isCompleted = set.isCompleted
            let exercise = draft.exercises.first { $0.id == exerciseID }

            HStack(spacing: 10) {
                Text("\(visibleIndex + 1)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 18)

                WorkoutNumericTextField(
                    placeholder: weightUnit.fieldPlaceholder,
                    text: weightBinding(exerciseID: exerciseID, setIndex: setIndex),
                    keyboard: .decimalPad,
                    focusTarget: .setWeight(exerciseID, setIndex),
                    focusedField: $focusedField,
                    accessibilityIdentifier: "HistorySetWeightField-\(exerciseIndex)-\(visibleIndex)"
                )

                if let exercise, exercise.trackingMethod == .duration {
                    timeButton(exercise, exerciseIndex: exerciseIndex, setIndex: setIndex, visibleIndex: visibleIndex)
                } else {
                    WorkoutNumericTextField(
                        placeholder: ExerciseTrackingMethod.reps.fieldLabel,
                        text: repsBinding(exerciseID: exerciseID, setIndex: setIndex),
                        keyboard: .numberPad,
                        focusTarget: .setReps(exerciseID, setIndex),
                        focusedField: $focusedField,
                        accessibilityIdentifier: "HistorySetRepsField-\(exerciseIndex)-\(visibleIndex)"
                    )
                }

                if showsRPE {
                    WorkoutNumericTextField(
                        placeholder: "RPE",
                        text: rpeBinding(exerciseID: exerciseID, setIndex: setIndex),
                        keyboard: .decimalPad,
                        focusTarget: .setRPE(exerciseID, setIndex),
                        focusedField: $focusedField,
                        accessibilityIdentifier: "HistorySetRPEField-\(exerciseIndex)-\(visibleIndex)"
                    )
                }

                Button {
                    updateDraftSet(exerciseID: exerciseID, setIndex: setIndex) { set in
                        set.isCompleted.toggle()
                    }
                } label: {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isCompleted ? AppTheme.brandAccentFill : AppTheme.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCompleted ? "Mark set incomplete" : "Mark set complete")
                .accessibilityIdentifier("HistorySetCompletionButton-\(exerciseIndex)-\(visibleIndex)")

                Button(role: .destructive) {
                    removalCandidate = CompletedWorkoutSetRemovalCandidate(
                        exerciseID: exerciseID,
                        setIndex: setIndex,
                        displayNumber: visibleIndex + 1
                    )
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.destructiveForeground)
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove set")
                .accessibilityIdentifier("RemoveHistorySetButton-\(exerciseIndex)-\(visibleIndex)")
            }
        }
    }

    private func exerciseProgress(for exercise: CompletedWorkoutEditExerciseDraft) -> WorkoutExerciseProgress {
        let visibleSets = exercise.sets.filter { !$0.isRemoved }
        return WorkoutExerciseProgress(
            completed: visibleSets.filter(\.isCompleted).count,
            total: visibleSets.count
        )
    }

    private func weightBinding(exerciseID: UUID, setIndex: Int) -> Binding<String> {
        let focusTarget = CompletedWorkoutEditFocusedField.setWeight(exerciseID, setIndex)

        return Binding(
            get: {
                guard let set = draftSet(exerciseID: exerciseID, setIndex: setIndex) else {
                    return numberInputTexts[focusTarget]?.displayText(for: nil) ?? ""
                }
                let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: set.weight)
                return numberInputTexts[focusTarget, default: WorkoutNumberInputText()].displayText(for: displayWeight)
            },
            set: { value in
                updateDraftSet(exerciseID: exerciseID, setIndex: setIndex) { set in
                    numberInputTexts[focusTarget, default: WorkoutNumberInputText()].updateDraft(value)
                    set.weight = WorkoutNumericInputPolicy.parseWeight(value, unit: weightUnit)
                }
            }
        )
    }

    private func repsBinding(exerciseID: UUID, setIndex: Int) -> Binding<String> {
        let focusTarget = CompletedWorkoutEditFocusedField.setReps(exerciseID, setIndex)

        return Binding(
            get: {
                guard let set = draftSet(exerciseID: exerciseID, setIndex: setIndex) else {
                    return numberInputTexts[focusTarget]?.displayText(for: nil) ?? ""
                }
                let reps = WorkoutNumericInputPolicy.validatedReps(set.reps)
                return numberInputTexts[focusTarget, default: WorkoutNumberInputText()]
                    .displayText(fallback: reps.map(String.init) ?? "")
            },
            set: { value in
                updateDraftSet(exerciseID: exerciseID, setIndex: setIndex) { set in
                    numberInputTexts[focusTarget, default: WorkoutNumberInputText()].updateDraft(value)
                    set.reps = WorkoutNumericInputPolicy.parseReps(value)
                }
            }
        )
    }

    private func timeButton(
        _ exercise: CompletedWorkoutEditExerciseDraft,
        exerciseIndex: Int,
        setIndex: Int,
        visibleIndex: Int
    ) -> some View {
        let isEditing = timeEdit?.exerciseID == exercise.id && timeEdit?.setIndex == setIndex
        let stored = WorkoutNumericInputPolicy.validatedDuration(exercise.sets[setIndex].durationSeconds)
        let seconds = isEditing ? WorkoutNumericInputPolicy.validatedDuration(timeEdit?.seconds) ?? stored : stored
        let placeholder = exercise.trackingMethod.fieldLabel
        let timeAbove = exercise.sets[..<setIndex].reversed().lazy
            .filter { !$0.isRemoved }
            .compactMap { WorkoutNumericInputPolicy.validatedDuration($0.durationSeconds) }
            .first
        let startingSeconds = stored ?? timeAbove ?? 0
        return Button {
            guard !isEditing else { return }
            endTimeEdit()
            timeEdit = CompletedWorkoutSetTimeEdit(
                exerciseID: exercise.id,
                setIndex: setIndex,
                seconds: SetTimeEntry.clamped(startingSeconds)
            )
        } label: {
            Text(seconds.map(WorkoutFormatters.setDuration) ?? placeholder)
                .font(.body.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(seconds == nil ? AppTheme.textTertiary : AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    AppTheme.fieldSurface,
                    in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                        .strokeBorder(isEditing ? AppTheme.brandFocus : .clear, lineWidth: 1.5)
                }
                .animation(.easeOut(duration: 0.15), value: isEditing)
        }
        .buttonStyle(.plain)
        .setTimeInput(
            isEditing: isEditing,
            startingSeconds: timeEdit?.seconds ?? 0,
            onChange: { seconds in
                guard let timeEdit, isEditing else { return }
                self.timeEdit?.seconds = seconds
                setTime(seconds, for: timeEdit)
            },
            onEnd: { if isEditing { endTimeEdit() } }
        )
        .accessibilityLabel(placeholder)
        .accessibilityValue(seconds.map(WorkoutFormatters.setDurationAccessibilityDescription) ?? "No time")
        .accessibilityHint("Opens the time wheels.")
        .accessibilityAddTraits(isEditing ? .isSelected : [])
        .accessibilityIdentifier("HistorySetTimeField-\(exerciseIndex)-\(visibleIndex)")
    }

    private func endTimeEdit() {
        guard let timeEdit else { return }
        if timeEdit.seconds > 0 { setTime(timeEdit.seconds, for: timeEdit) }
        self.timeEdit = nil
    }

    private func setTime(_ seconds: Int, for edit: CompletedWorkoutSetTimeEdit) {
        updateDraftSet(exerciseID: edit.exerciseID, setIndex: edit.setIndex) { set in
            set.durationSeconds = seconds > 0 ? seconds : nil
        }
    }

    private func rpeBinding(exerciseID: UUID, setIndex: Int) -> Binding<String> {
        let focusTarget = CompletedWorkoutEditFocusedField.setRPE(exerciseID, setIndex)

        return Binding(
            get: {
                guard let set = draftSet(exerciseID: exerciseID, setIndex: setIndex) else {
                    return numberInputTexts[focusTarget]?.displayText(for: nil) ?? ""
                }
                return numberInputTexts[focusTarget, default: WorkoutNumberInputText()].displayText(for: set.rpe)
            },
            set: { value in
                updateDraftSet(exerciseID: exerciseID, setIndex: setIndex) { set in
                    numberInputTexts[focusTarget, default: WorkoutNumberInputText()].updateDraft(value)
                    set.rpe = WorkoutNumericInputPolicy.parseRPE(value)
                }
            }
        )
    }

    private func exerciseIndex(for exerciseID: UUID) -> Int? {
        draft.exercises.firstIndex { $0.id == exerciseID }
    }

    private func draftSet(exerciseID: UUID, setIndex: Int) -> CompletedWorkoutEditSetDraft? {
        guard let exerciseIndex = exerciseIndex(for: exerciseID),
              draft.exercises[exerciseIndex].sets.indices.contains(setIndex)
        else { return nil }
        return draft.exercises[exerciseIndex].sets[setIndex]
    }

    private func exerciseNotesBinding(exerciseID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let exerciseIndex = exerciseIndex(for: exerciseID) else { return "" }
                return draft.exercises[exerciseIndex].notes
            },
            set: { notes in
                guard let exerciseIndex = exerciseIndex(for: exerciseID) else { return }
                draft.exercises[exerciseIndex].notes = notes
            }
        )
    }

    private func exerciseNoteRevealBinding(exerciseID: UUID) -> Binding<Bool> {
        Binding(
            get: { revealedExerciseNoteIDs.contains(exerciseID) },
            set: { isRevealed in
                if isRevealed {
                    revealedExerciseNoteIDs.insert(exerciseID)
                } else {
                    revealedExerciseNoteIDs.remove(exerciseID)
                }
            }
        )
    }

    private func updateDraftSet(
        exerciseID: UUID,
        setIndex: Int,
        update: (inout CompletedWorkoutEditSetDraft) -> Void
    ) {
        guard let exerciseIndex = exerciseIndex(for: exerciseID),
              draft.exercises[exerciseIndex].sets.indices.contains(setIndex)
        else { return }
        update(&draft.exercises[exerciseIndex].sets[setIndex])
    }

    private func visibleSetIndices(in exercise: CompletedWorkoutEditExerciseDraft) -> [Int] {
        exercise.sets.indices.filter { !exercise.sets[$0].isRemoved }
    }

    private func addSet(to exerciseID: UUID) {
        guard let exerciseIndex = exerciseIndex(for: exerciseID) else { return }
        let exercise = draft.exercises[exerciseIndex]
        let visibleIndices = visibleSetIndices(in: exercise)
        let setIndex = exercise.sets.count
        // A new row continues the kind of the row above it, as in an active workout.
        let kind = visibleIndices.last.map { exercise.sets[$0].kind } ?? .working
        draft.exercises[exerciseIndex].sets.append(
            CompletedWorkoutEditSetDraft(orderIndex: visibleIndices.count, kind: kind)
        )
        focusedField = .setWeight(exerciseID, setIndex)
    }

    private func removeSet(_ candidate: CompletedWorkoutSetRemovalCandidate) {
        endTimeEdit()
        guard let exerciseIndex = exerciseIndex(for: candidate.exerciseID),
              draft.exercises[exerciseIndex].sets.indices.contains(candidate.setIndex)
        else { return }

        if draft.exercises[exerciseIndex].sets[candidate.setIndex].id == nil {
            rebaseNumberInputTextsAfterRemovingSet(
                exerciseID: candidate.exerciseID,
                removedSetIndex: candidate.setIndex
            )
            draft.exercises[exerciseIndex].sets.remove(at: candidate.setIndex)
        } else {
            draft.exercises[exerciseIndex].sets[candidate.setIndex].isRemoved = true
        }
        reindexDraftSets(for: exerciseIndex)
    }

    private func changeSuperset(
        _ change: ActiveWorkoutEngine.SupersetChange,
        for exercise: CompletedWorkoutEditExerciseDraft
    ) {
        focusedField = nil
        endTimeEdit()
        withAnimation(.snappy) {
            draft.changeSuperset(change, forExerciseID: exercise.id)
        }
    }

    private func removeExercise(_ exercise: CompletedWorkoutEditExerciseDraft) {
        focusedField = nil
        endTimeEdit()
        forgetInputState(for: exercise.id)
        draft.removeExercises([exercise.id])
    }

    private func swap(_ exercise: CompletedWorkoutEditExerciseDraft, with replacement: Exercise) {
        focusedField = nil
        endTimeEdit()
        forgetInputState(for: exercise.id)
        draft.swapExercise(
            id: exercise.id,
            with: replacement,
            history: exerciseHistory(),
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        )
    }

    private func forgetInputState(for exerciseID: UUID) {
        numberInputTexts = numberInputTexts.filter { $0.key.exerciseID != exerciseID }
        revealedExerciseNoteIDs.remove(exerciseID)
    }

    /// Completed workouts for an added exercise's starting set kinds.
    private func exerciseHistory() -> [WorkoutSession] {
        (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
    }

    private func rebaseNumberInputTextsAfterRemovingSet(exerciseID: UUID, removedSetIndex: Int) {
        var rebasedInputTexts: [CompletedWorkoutEditFocusedField: WorkoutNumberInputText] = [:]
        for (field, inputText) in numberInputTexts {
            if let rebasedField = field.rebasedAfterRemovingSet(exerciseID: exerciseID, removedSetIndex: removedSetIndex) {
                rebasedInputTexts[rebasedField] = inputText
            }
        }
        numberInputTexts = rebasedInputTexts
        focusedField = focusedField?.rebasedAfterRemovingSet(exerciseID: exerciseID, removedSetIndex: removedSetIndex)
    }

    private func reindexDraftSets(for exerciseIndex: Int) {
        let exercise = draft.exercises[exerciseIndex]
        for (visibleIndex, setIndex) in visibleSetIndices(in: exercise).enumerated() {
            draft.exercises[exerciseIndex].sets[setIndex].orderIndex = visibleIndex
        }
    }

    private func save() {
        focusedField = nil
        endTimeEdit()

        draft.prepareTitleForSave()

        if hasDurationChange {
            draft.durationSeconds = durationSelection.totalSeconds
        } else {
            draft.durationSeconds = initialDurationSeconds
        }

        do {
            #if DEBUG
            try UITestFixtureSeeder.simulateConcurrentHistorySave(session: session, context: modelContext)
            #endif
            try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
                draft,
                for: session,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                context: modelContext
            )
            syncScheduler.requestSync()
            errorMessage = nil
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct CompletedWorkoutSetTimeEdit {
    let exerciseID: UUID
    let setIndex: Int
    var seconds: Int

    var id: String { "\(exerciseID)-\(setIndex)" }
}

/// The Active Workout's exercise list editor (reorder, remove, add, and link)
/// over a copy of the draft. Done hands the copy back; Cancel drops it.
private struct CompletedWorkoutReorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @State private var draft: CompletedWorkoutEditDraft
    /// The draft before each edit, latest last.
    @State private var history: [CompletedWorkoutEditDraft] = []
    @State private var notice: ReorderNotice?
    @State private var showsPicker = false
    @State private var confirmsDiscard = false
    let onDone: (CompletedWorkoutEditDraft) -> Void

    init(draft: CompletedWorkoutEditDraft, onDone: @escaping (CompletedWorkoutEditDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ReorderExercisesList(
                exercises: draft.exercises,
                rearrange: { order, groups in
                    edit {
                        draft.reorderExercises(order)
                        draft.regroup(groups)
                    }
                },
                remove: { id in
                    guard let removed = draft.exercises.first(where: { $0.id == id }) else { return }
                    edit { draft.removeExercises([id]) }
                    notice = ReorderNotice(title: "Removed \(removed.name)")
                },
                add: { showsPicker = true },
                undo: history.isEmpty ? nil : { undo() },
                notice: $notice
            )
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .overlay {
                if draft.exercises.isEmpty {
                    Text("No exercises")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("ReorderExercisesEmptyState")
                }
            }
            .navigationDestination(isPresented: $showsPicker) {
                ExercisePickerView(
                    mode: .add(existingExerciseIDs: draft.exerciseIDs),
                    showsCancel: false,
                    onSelect: append
                )
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if history.isEmpty { dismiss() } else { confirmsDiscard = true }
                    }
                    .accessibilityIdentifier("CancelReorderExercisesButton")
                    .confirmationDialog(
                        "Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible
                    ) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(draft)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityIdentifier("DoneReorderExercisesButton")
                }
            }
        }
        // A swipe down would discard edits without asking; Cancel asks instead.
        .interactiveDismissDisabled(!history.isEmpty)
        .presentationDragIndicator(.visible)
    }

    /// Keeps the draft from before an edit, for Undo.
    private func edit(_ change: () -> Void) {
        history.append(draft)
        change()
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        notice = nil
        withAnimation(.snappy(duration: 0.3)) { draft = previous }
    }

    private func append(_ exercises: [Exercise], asSuperset: Bool) {
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        edit {
            draft.appendExercises(
                exercises,
                asSuperset: asSuperset,
                history: sessions,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
            )
        }
        showsPicker = false
    }
}

/// Picks a replacement. The picker confirms before the draft drops the sets.
private struct CompletedWorkoutSwapExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSwap: (Exercise) -> Void
    @State private var impactAtOpen: SwapExerciseImpact

    init(exercise: CompletedWorkoutEditExerciseDraft, onSwap: @escaping (Exercise) -> Void) {
        self.onSwap = onSwap
        _impactAtOpen = State(initialValue: SwapExerciseImpact(original: exercise))
    }

    var body: some View {
        NavigationStack {
            ExercisePickerView(mode: .swap(impactAtOpen)) { exercises, _ in
                guard let replacement = exercises.first else { return }
                onSwap(replacement)
                dismiss()
            }
        }
        .presentationDetents([.large])
    }
}

private struct CompletedWorkoutDurationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: CompletedWorkoutDurationSelection
    @Binding var hasEditedDuration: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                SurfaceCard {
                    VStack(spacing: 18) {
                        durationStepper(
                            title: "Hours",
                            value: selection.hours,
                            decrementIdentifier: "DurationHoursDecrementButton",
                            incrementIdentifier: "DurationHoursIncrementButton",
                            decrement: { update(hours: max(0, selection.hours - 1)) },
                            increment: { update(hours: min(99, selection.hours + 1)) }
                        )

                        Divider()
                            .overlay(AppTheme.subtleBorder)

                        durationStepper(
                            title: "Minutes",
                            value: selection.minutes,
                            decrementIdentifier: "DurationMinutesDecrementButton",
                            incrementIdentifier: "DurationMinutesIncrementButton",
                            quickDecrementIdentifier: "DurationMinutesDecrementFiveButton",
                            quickIncrementIdentifier: "DurationMinutesIncrementFiveButton",
                            decrement: { update(minutes: max(0, selection.minutes - 1)) },
                            increment: { update(minutes: min(59, selection.minutes + 1)) },
                            quickDecrement: { update(minutes: max(0, selection.minutes - 5)) },
                            quickIncrement: { update(minutes: min(59, selection.minutes + 5)) }
                        )
                    }
                }

                Text(selection.displayText)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("CompletedWorkoutDurationPreview")

                Spacer()
            }
            .padding(AppTheme.shellPadding)
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("DoneDurationEditButton")
                }
            }
        }
    }

    private func durationStepper(
        title: String,
        value: Int,
        decrementIdentifier: String,
        incrementIdentifier: String,
        quickDecrementIdentifier: String? = nil,
        quickIncrementIdentifier: String? = nil,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        quickDecrement: (() -> Void)? = nil,
        quickIncrement: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            if let quickDecrement, let quickDecrementIdentifier {
                durationStepButton(
                    title: "-5",
                    accessibilityIdentifier: quickDecrementIdentifier,
                    action: quickDecrement
                )
            }

            Button(action: decrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.brandAccentForeground)
            .accessibilityIdentifier(decrementIdentifier)

            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 44)

            Button(action: increment) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.brandAccentForeground)
            .accessibilityIdentifier(incrementIdentifier)

            if let quickIncrement, let quickIncrementIdentifier {
                durationStepButton(
                    title: "+5",
                    accessibilityIdentifier: quickIncrementIdentifier,
                    action: quickIncrement
                )
            }
        }
        .frame(minHeight: 44)
    }

    private func durationStepButton(
        title: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.brandAccentForeground)
                .frame(width: 34, height: 34)
                .background(
                    AppTheme.brandAccentMuted,
                    in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func update(hours: Int? = nil, minutes: Int? = nil) {
        selection = CompletedWorkoutDurationSelection(
            hours: hours ?? selection.hours,
            minutes: minutes ?? selection.minutes
        )
        hasEditedDuration = true
    }
}

private struct CompletedWorkoutDurationSelection: Equatable {
    var hours: Int
    var minutes: Int

    init(seconds: Int) {
        let totalMinutes = max(0, seconds) / 60
        hours = totalMinutes / 60
        minutes = totalMinutes % 60
    }

    init(hours: Int, minutes: Int) {
        self.hours = max(0, min(99, hours))
        self.minutes = max(0, min(59, minutes))
    }

    var totalSeconds: Int {
        ((hours * 60) + minutes) * 60
    }

    var displayText: String {
        switch (hours, minutes) {
        case (0, 0):
            return "0 min"
        case (0, let minutes):
            return "\(minutes) min"
        case (let hours, 0):
            return "\(hours) hr"
        default:
            return "\(hours) hr \(minutes) min"
        }
    }
}

private struct CompletedWorkoutSetRemovalCandidate: Identifiable {
    let id = UUID()
    let exerciseID: UUID
    let setIndex: Int
    let displayNumber: Int
}

/// Exercise fields key by id, so adding, removing, or swapping an exercise
/// leaves the others' focus and in-progress text in place. A set keys by its
/// index in the exercise's draft sets.
private enum CompletedWorkoutEditFocusedField: Hashable {
    case title
    case notes
    case exerciseNotes(UUID)
    case setWeight(UUID, Int)
    case setReps(UUID, Int)
    case setRPE(UUID, Int)

    var exerciseID: UUID? {
        switch self {
        case .title, .notes:
            return nil
        case let .exerciseNotes(exerciseID),
             let .setWeight(exerciseID, _),
             let .setReps(exerciseID, _),
             let .setRPE(exerciseID, _):
            return exerciseID
        }
    }

    func rebasedAfterRemovingSet(exerciseID: UUID, removedSetIndex: Int) -> CompletedWorkoutEditFocusedField? {
        switch self {
        case let .setWeight(fieldExerciseID, setIndex) where fieldExerciseID == exerciseID && setIndex == removedSetIndex:
            return nil
        case let .setReps(fieldExerciseID, setIndex) where fieldExerciseID == exerciseID && setIndex == removedSetIndex:
            return nil
        case let .setRPE(fieldExerciseID, setIndex) where fieldExerciseID == exerciseID && setIndex == removedSetIndex:
            return nil
        case let .setWeight(fieldExerciseID, setIndex) where fieldExerciseID == exerciseID && setIndex > removedSetIndex:
            return .setWeight(fieldExerciseID, setIndex - 1)
        case let .setReps(fieldExerciseID, setIndex) where fieldExerciseID == exerciseID && setIndex > removedSetIndex:
            return .setReps(fieldExerciseID, setIndex - 1)
        case let .setRPE(fieldExerciseID, setIndex) where fieldExerciseID == exerciseID && setIndex > removedSetIndex:
            return .setRPE(fieldExerciseID, setIndex - 1)
        default:
            return self
        }
    }
}
