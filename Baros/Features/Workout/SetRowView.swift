import SwiftData
import SwiftUI

struct SetRowView: View {
    @Environment(\.modelContext) private var modelContext
    let set: LoggedSet
    let exerciseIndex: Int
    let index: Int
    @Bindable var engine: ActiveWorkoutEngine
    let fieldCommitRegistry: WorkoutFieldCommitRegistry
    var focusedField: FocusState<WorkoutField?>.Binding
    let weightUnit: MeasurementUnit
    let previous: PreviousSetPerformance?
    let onEditRPE: (LoggedSet) -> Void
    @State private var input = ActiveWorkoutSetInput()
    @State private var commitRegistrationID: UUID?

    var body: some View {
        SwipeToDeleteRow(
            deleteAccessibilityLabel: "Remove set",
            deleteAccessibilityIdentifier: "DeleteSetButton-\(exerciseIndex)-\(index)"
        ) {
            try? engine.removeSet(set, context: modelContext)
        } content: {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 18)

            previousColumn

            numericField(
                placeholder: weightUnit.fieldPlaceholder,
                text: weightBinding,
                keyboard: .decimalPad,
                focusTarget: .setWeight(set.id),
                accessibilityIdentifier: "SetWeightField-\(exerciseIndex)-\(index)"
            )

            repsField

            Button {
                completeButtonTapped()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? AppTheme.accentBright : AppTheme.textTertiary)
                    .symbolEffect(.bounce, value: set.isCompleted)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Mark set incomplete" : "Mark set complete")
            .accessibilityIdentifier("SetCompletionButton-\(exerciseIndex)-\(index)")
        }
        .onAppear {
            guard commitRegistrationID == nil else { return }
            commitRegistrationID = fieldCommitRegistry.register(fields: ownFields) {
                commitDraftsIfNeeded()
            }
        }
        .onDisappear {
            // Rows can leave the tree mid-edit (collapse, delete, finish); the
            // central focus transition no longer reaches them, so flush here.
            commitDraftsIfNeeded()
            if let commitRegistrationID {
                fieldCommitRegistry.unregister(commitRegistrationID)
                self.commitRegistrationID = nil
            }
        }
    }

    /// Typing stages values in view-local drafts; this is the single point that
    /// writes them to the model and saves. Runs on focus leave, completion, and
    /// row disappearance — never per keystroke.
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

    private var previousColumn: some View {
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
        .accessibilityLabel(previous == nil ? "No previous set" : "Previous: \(previousText)")
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
                    .foregroundStyle(AppTheme.accentBright)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppTheme.accentMuted, in: Capsule())
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
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    private var weightBinding: Binding<String> {
        Binding(
            get: { input.text(for: .weight, values: inputValues, weightUnit: weightUnit) },
            set: { value in
                input.update(
                    value,
                    for: .weight,
                    isFocused: focusedField.wrappedValue == .setWeight(set.id)
                )
            }
        )
    }

    private var repsBinding: Binding<String> {
        Binding(
            get: { input.text(for: .reps, values: inputValues, weightUnit: weightUnit) },
            set: { value in
                input.update(
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
        if let previousFill = input.previousFillBeforeCompletion(
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
        input.clearRejectionsSatisfiedByPreviousFill(inputValues)
    }

    private var inputValues: ActiveWorkoutSetInput.Values {
        ActiveWorkoutSetInput.Values(weight: set.weight, reps: set.reps)
    }

    private var ownFields: [WorkoutField] {
        [.setWeight(set.id), .setReps(set.id)]
    }

    private func clearFocusedFieldForThisSet() {
        if focusedField.wrappedValue == .setWeight(set.id)
            || focusedField.wrappedValue == .setReps(set.id) {
            focusedField.wrappedValue = nil
        }
    }
}
