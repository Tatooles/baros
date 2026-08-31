import SwiftData
import SwiftUI

struct SetRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let set: LoggedSet
    let exerciseIndex: Int
    let index: Int
    @Bindable var engine: ActiveWorkoutEngine
    @Bindable var draft: ActiveWorkoutSetDraft
    let commitDraft: (LoggedSet, ActiveWorkoutSetDraft) -> ActiveWorkoutSetInput.Commit
    var focusedField: FocusState<WorkoutField?>.Binding
    let weightUnit: MeasurementUnit
    let previous: PreviousSetPerformance?
    let onEditRPE: (LoggedSet) -> Void

    var body: some View {
        SwipeToDeleteRow(
            deleteAccessibilityLabel: "Remove set",
            deleteAccessibilityIdentifier: "DeleteSetButton-\(exerciseIndex)-\(index)"
        ) {
            clearFocusedFieldForThisSet()
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

    /// Typing stages values in a session-owned draft that survives lazy exercise
    /// card recycling. Row actions call this only at explicit commit boundaries;
    /// the shared closure owns the actual model write and save.
    @discardableResult
    private func commitDraftsIfNeeded() -> ActiveWorkoutSetInput.Commit {
        commitDraft(set, draft)
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
        accessibilityIdentifier: String
    ) -> some View {
        WorkoutNumericTextField(
            placeholder: placeholder,
            text: text,
            keyboard: keyboard,
            focusTarget: focusTarget,
            focusedField: focusedField,
            accessibilityIdentifier: accessibilityIdentifier,
            verticalPadding: 8,
            presentation: .grid
        )
    }

    private var weightBinding: Binding<String> {
        Binding(
            get: { draft.text(for: .weight, values: inputValues, weightUnit: weightUnit) },
            set: { value in
                draft.update(
                    value,
                    for: .weight,
                    isFocused: focusedField.wrappedValue == .setWeight(set.id)
                )
            }
        )
    }

    private var repsBinding: Binding<String> {
        Binding(
            get: { draft.text(for: .reps, values: inputValues, weightUnit: weightUnit) },
            set: { value in
                draft.update(
                    value,
                    for: .reps,
                    isFocused: focusedField.wrappedValue == .setReps(set.id)
                )
            }
        )
    }

    private func completeButtonTapped() {
        // The fill policy below reads committed model values, so pending drafts
        // must land first (the focus-change commit only fires on a later update).
        let commit = commitDraftsIfNeeded()
        clearFocusedFieldForThisSet()
        if let previousFill = draft.previousFillBeforeCompletion(
            isCompleted: set.isCompleted,
            values: commit.values,
            previous: previous
        ) {
            fillFromPrevious(previousFill)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            try? engine.toggleSetCompletion(set, context: modelContext)
        }
    }

    private func fillFromPrevious(_ previous: PreviousSetPerformance) {
        // Commit rather than drop drafts: fillSetFromPrevious only fills fields
        // that are still nil, so a typed-but-uncommitted value must win.
        commitDraftsIfNeeded()
        try? engine.fillSetFromPrevious(set, previous: previous, context: modelContext)
        draft.clearRejectionsSatisfiedByPreviousFill(inputValues)
    }

    private var inputValues: ActiveWorkoutSetInput.Values {
        ActiveWorkoutSetInput.Values(weight: set.weight, reps: set.reps)
    }

    private func clearFocusedFieldForThisSet() {
        if focusedField.wrappedValue == .setWeight(set.id)
            || focusedField.wrappedValue == .setReps(set.id) {
            focusedField.wrappedValue = nil
        }
    }
}
