import SwiftData
import SwiftUI

struct SetRowView: View, @MainActor Equatable {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let set: LoggedSet
    let setID: UUID
    let weight: Double?
    let reps: Int?
    let isCompleted: Bool
    let rpe: Double?
    let exerciseIndex: Int
    let index: Int
    @Bindable var engine: ActiveWorkoutEngine
    let setInputRegistry: ActiveSetInputRegistry
    var focusedField: FocusState<WorkoutField?>.Binding
    let isWeightFocused: Bool
    let isRepsFocused: Bool
    let weightUnit: MeasurementUnit
    let previous: PreviousSetPerformance?
    let onEditRPE: (LoggedSet) -> Void
    @State private var input = ActiveWorkoutSetInput()
    @State private var commitRegistrationID: UUID?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.setID == rhs.setID
            && lhs.weight == rhs.weight
            && lhs.reps == rhs.reps
            && lhs.isCompleted == rhs.isCompleted
            && lhs.rpe == rhs.rpe
            && lhs.index == rhs.index
            && lhs.exerciseIndex == rhs.exerciseIndex
            && lhs.weightUnit == rhs.weightUnit
            && lhs.previous == rhs.previous
            && lhs.isWeightFocused == rhs.isWeightFocused
            && lhs.isRepsFocused == rhs.isRepsFocused
    }

    var body: some View {
        SwipeToDeleteRow(
            deleteAccessibilityLabel: "Remove set",
            deleteAccessibilityIdentifier: "DeleteSetButton-\(exerciseIndex)-\(index)"
        ) {
            try? engine.removeSet(set, context: modelContext)
        } content: {
            rowContent
        }
        .sensoryFeedback(trigger: set.isCompleted) { _, isCompleted in
            isCompleted ? .impact(weight: .light) : nil
        }
    }

    private var rowContent: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityRowContent
            } else {
                standardRowContent
            }
        }
        .onAppear {
            guard commitRegistrationID == nil else { return }
            commitRegistrationID = setInputRegistry.register(
                fields: ownFields,
                commit: { commitDraftsIfNeeded() },
                prepareForRPESelection: prepareValuesForSetAction
            )
        }
        .onChange(of: previous) { _, _ in
            refreshSetInputRegistration()
        }
        .onChange(of: weightUnit) { _, _ in
            refreshSetInputRegistration()
        }
        .onDisappear {
            // Rows can leave the tree mid-edit (collapse, delete, finish); the
            // central focus transition can no longer reach them, so flush here.
            commitDraftsIfNeeded()
            if let commitRegistrationID {
                setInputRegistry.unregister(commitRegistrationID)
                self.commitRegistrationID = nil
            }
        }
    }

    private var standardRowContent: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 28)

            previousColumn()

            numericField(
                placeholder: weightUnit.fieldPlaceholder,
                text: weightBinding,
                keyboard: .decimalPad,
                focusTarget: .setWeight(set.id),
                isFocused: isWeightFocused,
                accessibilityIdentifier: "SetWeightField-\(exerciseIndex)-\(index)"
            )

            repsField

            completionButton
        }
    }

    private var accessibilityRowContent: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Text("Set \(index + 1)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)

                labeledColumn(
                    label: "PREVIOUS",
                    labelIdentifier: "SetPreviousLabel-\(exerciseIndex)-\(index)"
                ) {
                    previousColumn(accessibilityLabelIncludesContext: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                completionButton
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("SetAccessibilityTopRow-\(exerciseIndex)-\(index)")

            HStack(alignment: .top, spacing: 12) {
                labeledColumn(
                    label: weightUnit.fieldLabel,
                    labelIdentifier: "SetWeightLabel-\(exerciseIndex)-\(index)"
                ) {
                    numericField(
                        placeholder: weightUnit.fieldPlaceholder,
                        text: weightBinding,
                        keyboard: .decimalPad,
                        focusTarget: .setWeight(set.id),
                        isFocused: isWeightFocused,
                        accessibilityIdentifier: "SetWeightField-\(exerciseIndex)-\(index)"
                    )
                }

                labeledColumn(
                    label: "REPS",
                    labelIdentifier: "SetRepsLabel-\(exerciseIndex)-\(index)"
                ) {
                    repsField
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("SetAccessibilityBottomRow-\(exerciseIndex)-\(index)")
        }
    }

    private func labeledColumn<Content: View>(
        label: String,
        labelIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .accessibilityIdentifier(labelIdentifier)
            content()
        }
    }

    private var completionButton: some View {
        Button {
            completeButtonTapped()
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(set.isCompleted ? AppTheme.brandAccentFill : AppTheme.textTertiary)
                .symbolEffect(.bounce, value: set.isCompleted)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(set.isCompleted ? "Mark set incomplete" : "Mark set complete")
        .accessibilityIdentifier("SetCompletionButton-\(exerciseIndex)-\(index)")
    }

    /// Typing stages values in view-local drafts. Focus leave and row
    /// disappearance persist here; set actions consume drafts before saving
    /// their prepared values and completion/RPE together, never per keystroke.
    @discardableResult
    private func commitDraftsIfNeeded() -> ActiveWorkoutSetInput.Commit {
        let commit = input.commit(current: inputValues, weightUnit: weightUnit)
        guard commit.shouldPersist else { return commit }

        _ = try? engine.commitActiveSetDraft(
            set,
            values: commit.values,
            context: modelContext
        )
        return commit
    }

    private func previousColumn(accessibilityLabelIncludesContext: Bool = true) -> some View {
        Button {
            guard let previous, !set.isCompleted else { return }
            fillFromPrevious(previous)
        } label: {
            Text(previousText)
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(previous == nil || set.isCompleted)
        .accessibilityIdentifier("SetPreviousValue-\(exerciseIndex)-\(index)")
        .accessibilityLabel(previousAccessibilityLabel(includesContext: accessibilityLabelIncludesContext))
    }

    private func previousAccessibilityLabel(includesContext: Bool) -> String {
        if let previous {
            let value = previous.displayText(weightUnit: weightUnit)
            return includesContext ? "Previous: \(value)" : value
        }
        return includesContext ? "No previous set" : "No value"
    }

    private var previousText: String {
        guard let previous else {
            return "—"
        }

        return previous.displayText(weightUnit: weightUnit)
    }

    private var repsField: some View {
        numericField(
            placeholder: "REPS",
            text: repsBinding,
            keyboard: .numberPad,
            focusTarget: .setReps(set.id),
            isFocused: isRepsFocused,
            accessibilityIdentifier: "SetRepsField-\(exerciseIndex)-\(index)"
        )
        .overlay(alignment: .topTrailing) {
            rpeBadge
        }
    }

    @ViewBuilder
    private var rpeBadge: some View {
        if let rpe = WorkoutNumericInputPolicy.validatedRPE(set.rpe) {
            Button {
                onEditRPE(set)
            } label: {
                Text("@\(WorkoutFormatters.number(rpe))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppTheme.brandAccentMuted, in: Capsule())
                    .offset(x: -4, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("SetRPEBadge-\(exerciseIndex)-\(index)")
            .accessibilityLabel("RPE \(WorkoutFormatters.number(rpe)), tap to edit")
        }
    }

    private func numericField(
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        focusTarget: WorkoutField,
        isFocused: Bool,
        accessibilityIdentifier: String
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(AppTheme.textPrimary)
            .focused(focusedField, equals: focusTarget)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(
                RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
            )
            .onTapGesture {
                guard !isFocused else { return }
                focusedField.wrappedValue = focusTarget
            }
            .background {
                Rectangle()
                    .fill(isFocused ? AppTheme.brandAccentMuted : .clear)
                    .overlay(alignment: .bottom) {
                        if isFocused {
                            Rectangle()
                                .fill(AppTheme.brandFocus)
                                .frame(height: 2)
                        }
                    }
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .accessibilityIdentifier(accessibilityIdentifier)
            .id(focusTarget)
    }

    private var weightBinding: Binding<String> {
        Binding(
            get: { input.text(for: .weight, values: inputValues, weightUnit: weightUnit) },
            set: { value in
                guard value != input.text(
                    for: .weight,
                    values: inputValues,
                    weightUnit: weightUnit
                ) else { return }
                input.update(
                    value,
                    for: .weight,
                    isFocused: isWeightFocused
                )
            }
        )
    }

    private var repsBinding: Binding<String> {
        Binding(
            get: { input.text(for: .reps, values: inputValues, weightUnit: weightUnit) },
            set: { value in
                guard value != input.text(
                    for: .reps,
                    values: inputValues,
                    weightUnit: weightUnit
                ) else { return }
                input.update(
                    value,
                    for: .reps,
                    isFocused: isRepsFocused
                )
            }
        )
    }

    private func completeButtonTapped() {
        let preparedValues = prepareValuesForSetAction(completesSet: !set.isCompleted)
        // Preparation consumes the drafts before the later focus-change commit.
        clearFocusedFieldForThisSet()
        withAnimation(.easeInOut(duration: 0.2)) {
            try? engine.toggleSetCompletion(
                set,
                preparedValues: preparedValues,
                context: modelContext
            )
        }
    }

    private func prepareValuesForSetAction(
        completesSet: Bool
    ) -> ActiveWorkoutSetInput.Values {
        input.preparedValuesForSetAction(
            current: inputValues,
            weightUnit: weightUnit,
            completesSet: completesSet,
            isCompleted: set.isCompleted,
            previous: previous
        )
    }

    private func fillFromPrevious(_ previous: PreviousSetPerformance) {
        // Commit rather than drop drafts: fillSetFromPrevious only fills fields
        // that are still nil, so a typed-but-uncommitted value must win.
        commitDraftsIfNeeded()
        try? engine.fillSetFromPrevious(set, previous: previous, context: modelContext)
        input.clearRejectionsSatisfiedByPreviousFill(inputValues)
    }

    private var inputValues: ActiveWorkoutSetInput.Values {
        ActiveWorkoutSetInput.Values(weight: set.weight, reps: set.reps)
    }

    private var ownFields: [WorkoutField] {
        [.setWeight(set.id), .setReps(set.id)]
    }

    private func refreshSetInputRegistration() {
        guard let commitRegistrationID else { return }
        setInputRegistry.updateRegistration(
            commitRegistrationID,
            commit: { commitDraftsIfNeeded() },
            prepareForRPESelection: prepareValuesForSetAction
        )
    }

    private func clearFocusedFieldForThisSet() {
        if isWeightFocused || isRepsFocused {
            focusedField.wrappedValue = nil
        }
    }
}
