import SwiftData
import SwiftUI

struct CompletedWorkoutEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    @Environment(SyncOutboxTransaction.self) private var syncOutboxTransaction

    let session: WorkoutSession
    let weightUnit: MeasurementUnit
    private let initialDurationSeconds: Int
    private let initialDurationSelection: CompletedWorkoutDurationSelection
    @State private var draft: CompletedWorkoutEditDraft
    @State private var durationSelection: CompletedWorkoutDurationSelection
    @State private var hasEditedDuration = false
    @State private var isDurationEditorPresented = false
    @State private var numberInputTexts: [CompletedWorkoutEditFocusedField: WorkoutNumberInputText] = [:]
    @State private var errorMessage: String?
    @State private var removalCandidate: CompletedWorkoutSetRemovalCandidate?
    @FocusState private var focusedField: CompletedWorkoutEditFocusedField?

    init(session: WorkoutSession, draft: CompletedWorkoutEditDraft, weightUnit: MeasurementUnit) {
        self.session = session
        self.weightUnit = weightUnit
        initialDurationSeconds = draft.durationSeconds
        initialDurationSelection = CompletedWorkoutDurationSelection(seconds: draft.durationSeconds)
        _draft = State(initialValue: draft)
        _durationSelection = State(initialValue: CompletedWorkoutDurationSelection(seconds: draft.durationSeconds))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    workoutHeader

                    ForEach(draft.exercises.indices, id: \.self) { exerciseIndex in
                        exerciseEditor(exerciseIndex: exerciseIndex)
                    }

                    WorkoutNotesField(
                        title: "WORKOUT NOTES",
                        placeholder: "How did this session feel? Any notes for next time...",
                        text: $draft.notes,
                        focusTarget: .notes,
                        focusedField: $focusedField,
                        accessibilityIdentifier: "CompletedWorkoutNotesField"
                    )
                }
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppTheme.subtleBackground.ignoresSafeArea())
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
                guard let previousField, previousField != newField else { return }

                switch previousField {
                case .setWeight, .setRPE:
                    numberInputTexts[previousField]?.endEditing()
                case .title, .notes, .setReps:
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

            Text(WorkoutFormatters.compactDate(session.startedAt))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 12)

            Button {
                focusedField = nil
                isDurationEditorPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentBright)
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
                    AppTheme.fieldFill,
                    in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Duration \(durationDisplayText)")
            .accessibilityIdentifier("CompletedWorkoutDurationButton")
        }
        .padding(.horizontal, 4)
    }

    private var durationDisplayText: String {
        hasDurationChange ? durationSelection.displayText : AppTheme.formatDuration(initialDurationSeconds)
    }

    private var hasDurationChange: Bool {
        hasEditedDuration && durationSelection != initialDurationSelection
    }

    private func exerciseEditor(exerciseIndex: Int) -> some View {
        let exercise = draft.exercises[exerciseIndex]

        return SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                WorkoutExerciseHeaderContent(
                    title: exercise.exerciseSnapshotName,
                    metadata: exercise.metadataDisplayText,
                    progress: exerciseProgress(for: exerciseIndex),
                    isCollapsed: nil
                )
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 18)
                        WorkoutSetColumnHeader(title: weightUnit.fieldLabel)
                        WorkoutSetColumnHeader(title: "REPS")
                        WorkoutSetColumnHeader(title: "RPE")
                        Color.clear.frame(width: 44)
                        Color.clear.frame(width: 34)
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        let setIndices = visibleSetIndices(for: exerciseIndex)
                        ForEach(Array(setIndices.enumerated()), id: \.element) { visibleIndex, setIndex in
                            setEditor(exerciseIndex: exerciseIndex, setIndex: setIndex, visibleIndex: visibleIndex)
                                .padding(.horizontal, 16)
                        }
                    }

                    WorkoutAddRowButton(
                        title: "Add Set",
                        accessibilityIdentifier: "AddHistorySetButton-\(exerciseIndex)"
                    ) {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                            addSet(to: exerciseIndex)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func setEditor(exerciseIndex: Int, setIndex: Int, visibleIndex: Int) -> some View {
        if draftSetExists(exerciseIndex: exerciseIndex, setIndex: setIndex) {
            let isCompleted = draft.exercises[exerciseIndex].sets[setIndex].isCompleted

            HStack(spacing: 10) {
                Text("\(visibleIndex + 1)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 18)

                WorkoutNumericTextField(
                    placeholder: weightUnit.fieldPlaceholder,
                    text: weightBinding(exerciseIndex: exerciseIndex, setIndex: setIndex),
                    keyboard: .decimalPad,
                    focusTarget: .setWeight(exerciseIndex, setIndex),
                    focusedField: $focusedField,
                    accessibilityIdentifier: "HistorySetWeightField-\(exerciseIndex)-\(visibleIndex)"
                )

                WorkoutNumericTextField(
                    placeholder: "REPS",
                    text: repsBinding(exerciseIndex: exerciseIndex, setIndex: setIndex),
                    keyboard: .numberPad,
                    focusTarget: .setReps(exerciseIndex, setIndex),
                    focusedField: $focusedField,
                    accessibilityIdentifier: "HistorySetRepsField-\(exerciseIndex)-\(visibleIndex)"
                )

                WorkoutNumericTextField(
                    placeholder: "RPE",
                    text: rpeBinding(exerciseIndex: exerciseIndex, setIndex: setIndex),
                    keyboard: .decimalPad,
                    focusTarget: .setRPE(exerciseIndex, setIndex),
                    focusedField: $focusedField,
                    accessibilityIdentifier: "HistorySetRPEField-\(exerciseIndex)-\(visibleIndex)"
                )

                Button {
                    updateDraftSet(exerciseIndex: exerciseIndex, setIndex: setIndex) { set in
                        set.isCompleted.toggle()
                    }
                } label: {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isCompleted ? AppTheme.accentBright : AppTheme.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCompleted ? "Mark set incomplete" : "Mark set complete")
                .accessibilityIdentifier("HistorySetCompletionButton-\(exerciseIndex)-\(visibleIndex)")

                Button(role: .destructive) {
                    removalCandidate = CompletedWorkoutSetRemovalCandidate(
                        exerciseIndex: exerciseIndex,
                        setIndex: setIndex,
                        displayNumber: visibleIndex + 1
                    )
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.accentBright)
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove set")
                .accessibilityIdentifier("RemoveHistorySetButton-\(exerciseIndex)-\(visibleIndex)")
            }
        }
    }

    private func exerciseProgress(for exerciseIndex: Int) -> WorkoutExerciseProgress {
        let visibleSets = visibleSetIndices(for: exerciseIndex)
            .map { draft.exercises[exerciseIndex].sets[$0] }
        return WorkoutExerciseProgress(
            completed: visibleSets.filter(\.isCompleted).count,
            total: visibleSets.count
        )
    }

    private func weightBinding(exerciseIndex: Int, setIndex: Int) -> Binding<String> {
        let focusTarget = CompletedWorkoutEditFocusedField.setWeight(exerciseIndex, setIndex)

        return Binding(
            get: {
                guard draftSetExists(exerciseIndex: exerciseIndex, setIndex: setIndex) else {
                    return numberInputTexts[focusTarget]?.displayText(for: nil) ?? ""
                }
                let canonicalWeight = draft.exercises[exerciseIndex].sets[setIndex].weight
                let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: canonicalWeight)
                return numberInputTexts[focusTarget, default: WorkoutNumberInputText()].displayText(for: displayWeight)
            },
            set: { value in
                updateDraftSet(exerciseIndex: exerciseIndex, setIndex: setIndex) { set in
                    numberInputTexts[focusTarget, default: WorkoutNumberInputText()].updateDraft(value)
                    let displayWeight = WorkoutFormatters.parseNumber(value)
                    set.weight = weightUnit.canonicalWeight(fromDisplayWeight: displayWeight)
                }
            }
        )
    }

    private func repsBinding(exerciseIndex: Int, setIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard draftSetExists(exerciseIndex: exerciseIndex, setIndex: setIndex) else { return "" }
                return draft.exercises[exerciseIndex].sets[setIndex].reps.map(String.init) ?? ""
            },
            set: { value in
                updateDraftSet(exerciseIndex: exerciseIndex, setIndex: setIndex) { set in
                    set.reps = Int(value)
                }
            }
        )
    }

    private func rpeBinding(exerciseIndex: Int, setIndex: Int) -> Binding<String> {
        let focusTarget = CompletedWorkoutEditFocusedField.setRPE(exerciseIndex, setIndex)

        return Binding(
            get: {
                guard draftSetExists(exerciseIndex: exerciseIndex, setIndex: setIndex) else {
                    return numberInputTexts[focusTarget]?.displayText(for: nil) ?? ""
                }
                let rpe = draft.exercises[exerciseIndex].sets[setIndex].rpe
                return numberInputTexts[focusTarget, default: WorkoutNumberInputText()].displayText(for: rpe)
            },
            set: { value in
                updateDraftSet(exerciseIndex: exerciseIndex, setIndex: setIndex) { set in
                    numberInputTexts[focusTarget, default: WorkoutNumberInputText()].updateDraft(value)
                    set.rpe = WorkoutFormatters.parseNumber(value)
                }
            }
        )
    }

    private func draftSetExists(exerciseIndex: Int, setIndex: Int) -> Bool {
        draft.exercises.indices.contains(exerciseIndex)
            && draft.exercises[exerciseIndex].sets.indices.contains(setIndex)
    }

    private func updateDraftSet(
        exerciseIndex: Int,
        setIndex: Int,
        update: (inout CompletedWorkoutEditSetDraft) -> Void
    ) {
        guard draftSetExists(exerciseIndex: exerciseIndex, setIndex: setIndex) else { return }
        update(&draft.exercises[exerciseIndex].sets[setIndex])
    }

    private func visibleSetIndices(for exerciseIndex: Int) -> [Int] {
        draft.exercises[exerciseIndex].sets.indices.filter { !draft.exercises[exerciseIndex].sets[$0].isRemoved }
    }

    private func addSet(to exerciseIndex: Int) {
        let visibleCount = visibleSetIndices(for: exerciseIndex).count
        let setIndex = draft.exercises[exerciseIndex].sets.count
        draft.exercises[exerciseIndex].sets.append(
            CompletedWorkoutEditSetDraft(orderIndex: visibleCount)
        )
        focusedField = .setWeight(exerciseIndex, setIndex)
    }

    private func removeSet(_ candidate: CompletedWorkoutSetRemovalCandidate) {
        guard draft.exercises.indices.contains(candidate.exerciseIndex),
              draft.exercises[candidate.exerciseIndex].sets.indices.contains(candidate.setIndex)
        else { return }

        if draft.exercises[candidate.exerciseIndex].sets[candidate.setIndex].id == nil {
            rebaseNumberInputTextsAfterRemovingSet(
                exerciseIndex: candidate.exerciseIndex,
                removedSetIndex: candidate.setIndex
            )
            draft.exercises[candidate.exerciseIndex].sets.remove(at: candidate.setIndex)
        } else {
            draft.exercises[candidate.exerciseIndex].sets[candidate.setIndex].isRemoved = true
        }
        reindexDraftSets(for: candidate.exerciseIndex)
    }

    private func rebaseNumberInputTextsAfterRemovingSet(exerciseIndex: Int, removedSetIndex: Int) {
        var rebasedInputTexts: [CompletedWorkoutEditFocusedField: WorkoutNumberInputText] = [:]
        for (field, inputText) in numberInputTexts {
            if let rebasedField = field.rebasedAfterRemovingSet(exerciseIndex: exerciseIndex, removedSetIndex: removedSetIndex) {
                rebasedInputTexts[rebasedField] = inputText
            }
        }
        numberInputTexts = rebasedInputTexts
        focusedField = focusedField?.rebasedAfterRemovingSet(exerciseIndex: exerciseIndex, removedSetIndex: removedSetIndex)
    }

    private func reindexDraftSets(for exerciseIndex: Int) {
        for (visibleIndex, setIndex) in visibleSetIndices(for: exerciseIndex).enumerated() {
            draft.exercises[exerciseIndex].sets[setIndex].orderIndex = visibleIndex
        }
    }

    private func save() {
        focusedField = nil

        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.title = trimmedTitle.isEmpty ? "Workout" : trimmedTitle

        if hasDurationChange {
            draft.durationSeconds = durationSelection.totalSeconds
        } else {
            draft.durationSeconds = initialDurationSeconds
        }

        do {
            try WorkoutHistoryMutationService(
                syncOutboxTransaction: syncOutboxTransaction
            ).saveCompletedWorkoutEdit(
                draft,
                for: session,
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                context: modelContext
            )
            errorMessage = nil
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
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
                            .overlay(AppTheme.border)

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
            .background(AppTheme.subtleBackground.ignoresSafeArea())
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
            .foregroundStyle(AppTheme.accentBright)
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
            .foregroundStyle(AppTheme.accentBright)
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
                .foregroundStyle(AppTheme.accentBright)
                .frame(width: 34, height: 34)
                .background(
                    AppTheme.accentMuted,
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
    let exerciseIndex: Int
    let setIndex: Int
    let displayNumber: Int
}

private enum CompletedWorkoutEditFocusedField: Hashable {
    case title
    case notes
    case setWeight(Int, Int)
    case setReps(Int, Int)
    case setRPE(Int, Int)

    func rebasedAfterRemovingSet(exerciseIndex: Int, removedSetIndex: Int) -> CompletedWorkoutEditFocusedField? {
        switch self {
        case let .setWeight(fieldExerciseIndex, setIndex) where fieldExerciseIndex == exerciseIndex && setIndex == removedSetIndex:
            return nil
        case let .setReps(fieldExerciseIndex, setIndex) where fieldExerciseIndex == exerciseIndex && setIndex == removedSetIndex:
            return nil
        case let .setRPE(fieldExerciseIndex, setIndex) where fieldExerciseIndex == exerciseIndex && setIndex == removedSetIndex:
            return nil
        case let .setWeight(fieldExerciseIndex, setIndex) where fieldExerciseIndex == exerciseIndex && setIndex > removedSetIndex:
            return .setWeight(fieldExerciseIndex, setIndex - 1)
        case let .setReps(fieldExerciseIndex, setIndex) where fieldExerciseIndex == exerciseIndex && setIndex > removedSetIndex:
            return .setReps(fieldExerciseIndex, setIndex - 1)
        case let .setRPE(fieldExerciseIndex, setIndex) where fieldExerciseIndex == exerciseIndex && setIndex > removedSetIndex:
            return .setRPE(fieldExerciseIndex, setIndex - 1)
        default:
            return self
        }
    }
}
