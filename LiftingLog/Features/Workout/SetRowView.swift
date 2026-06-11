import SwiftData
import SwiftUI

struct SetRowView: View {
    @Environment(\.modelContext) private var modelContext
    let set: LoggedSet
    let exerciseIndex: Int
    let index: Int
    @Bindable var engine: ActiveWorkoutEngine
    var focusedField: FocusState<WorkoutField?>.Binding
    let weightUnit: MeasurementUnit
    @State private var weightInputText = WorkoutNumberInputText()
    @State private var rpeInputText = WorkoutNumberInputText()
    @State private var suppressedCompletionClearField: WorkoutField?

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

            numericField(
                placeholder: weightPlaceholder,
                text: weightBinding,
                keyboard: .decimalPad,
                focusTarget: .setWeight(set.id),
                accessibilityIdentifier: "SetWeightField-\(exerciseIndex)-\(index)"
            )

            numericField(
                placeholder: repsPlaceholder,
                text: repsBinding,
                keyboard: .numberPad,
                focusTarget: .setReps(set.id),
                accessibilityIdentifier: "SetRepsField-\(exerciseIndex)-\(index)"
            )

            numericField(
                placeholder: rpePlaceholder,
                text: rpeBinding,
                keyboard: .decimalPad,
                focusTarget: .setRPE(set.id),
                accessibilityIdentifier: "SetRPEField-\(exerciseIndex)-\(index)"
            )

            Button {
                suppressNextCompletionClearIfNeeded()
                clearFocusedFieldForThisSet()
                withAnimation(.easeInOut(duration: 0.2)) {
                    try? engine.toggleSetCompletion(set, context: modelContext)
                }
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
        .onChange(of: focusedField.wrappedValue) { previousField, newField in
            if previousField == .setWeight(set.id), newField != .setWeight(set.id) {
                weightInputText.endEditing()
            }
            if previousField == .setRPE(set.id), newField != .setRPE(set.id) {
                rpeInputText.endEditing()
            }
        }
    }

    private func numericField(
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        focusTarget: WorkoutField,
        accessibilityIdentifier: String
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(AppTheme.textPrimary)
            .focused(focusedField, equals: focusTarget)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                AppTheme.surfaceMuted,
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
            .accessibilityIdentifier(accessibilityIdentifier)
            .id(focusTarget)
    }

    private var weightBinding: Binding<String> {
        Binding(
            get: { weightInputText.displayText(for: set.weight) },
            set: { value in
                if shouldSuppressDecimalClear(value, field: .setWeight(set.id)) {
                    weightInputText.endEditing()
                    return
                }

                weightInputText.updateDraft(value)
                try? engine.updateSet(set, weight: WorkoutFormatters.parseNumber(value), reps: set.reps, rpe: set.rpe, context: modelContext)
            }
        )
    }

    private var weightPlaceholder: String {
        return set.placeholderWeight.map(WorkoutFormatters.number) ?? weightUnit.fieldPlaceholder
    }

    private var repsBinding: Binding<String> {
        Binding(
            get: { set.reps.map(String.init) ?? "" },
            set: { value in
                try? engine.updateSet(set, weight: set.weight, reps: Int(value), rpe: set.rpe, context: modelContext)
            }
        )
    }

    private var repsPlaceholder: String {
        return set.placeholderReps.map(String.init) ?? "REPS"
    }

    private var rpeBinding: Binding<String> {
        Binding(
            get: { rpeInputText.displayText(for: set.rpe) },
            set: { value in
                if shouldSuppressDecimalClear(value, field: .setRPE(set.id)) {
                    rpeInputText.endEditing()
                    return
                }

                rpeInputText.updateDraft(value)
                try? engine.updateSet(set, weight: set.weight, reps: set.reps, rpe: WorkoutFormatters.parseNumber(value), context: modelContext)
            }
        )
    }

    private var rpePlaceholder: String {
        return set.placeholderRPE.map(WorkoutFormatters.number) ?? "RPE"
    }

    private func clearFocusedFieldForThisSet() {
        if focusedField.wrappedValue == .setWeight(set.id)
            || focusedField.wrappedValue == .setReps(set.id)
            || focusedField.wrappedValue == .setRPE(set.id) {
            focusedField.wrappedValue = nil
        }
    }

    private func suppressNextCompletionClearIfNeeded() {
        let fieldToSuppress: WorkoutField?
        if focusedField.wrappedValue == .setWeight(set.id), !set.isCompleted, set.weight == nil, set.placeholderWeight != nil {
            fieldToSuppress = .setWeight(set.id)
        } else if focusedField.wrappedValue == .setRPE(set.id), !set.isCompleted, set.rpe == nil, set.placeholderRPE != nil {
            fieldToSuppress = .setRPE(set.id)
        } else {
            fieldToSuppress = nil
        }

        guard let fieldToSuppress else { return }
        suppressedCompletionClearField = fieldToSuppress
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if suppressedCompletionClearField == fieldToSuppress {
                suppressedCompletionClearField = nil
            }
        }
    }

    private func shouldSuppressDecimalClear(_ value: String, field: WorkoutField) -> Bool {
        guard value.isEmpty, suppressedCompletionClearField == field else { return false }
        suppressedCompletionClearField = nil
        return true
    }
}

struct WorkoutNumberInputText {
    private var draft: String?

    mutating func updateDraft(_ value: String) {
        draft = value
    }

    mutating func endEditing() {
        draft = nil
    }

    func displayText(for value: Double?) -> String {
        draft ?? value.map(WorkoutFormatters.number) ?? ""
    }
}
