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

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 15, weight: .semibold))
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    try? engine.toggleSetCompletion(set, context: modelContext)
                }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(set.isCompleted ? AppTheme.accentBright : AppTheme.borderStrong)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Mark set incomplete" : "Mark set complete")
            .accessibilityIdentifier("SetCompleteButton-\(exerciseIndex)-\(index)")

            Button(role: .destructive) {
                try? engine.removeSet(set, context: modelContext)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove set")
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
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.textPrimary)
            .focused(focusedField, equals: focusTarget)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(AppTheme.surfaceStrong)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.borderStrong)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var weightBinding: Binding<String> {
        Binding(
            get: { weightInputText.displayText(for: set.weight) },
            set: { value in
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
                rpeInputText.updateDraft(value)
                try? engine.updateSet(set, weight: set.weight, reps: set.reps, rpe: WorkoutFormatters.parseNumber(value), context: modelContext)
            }
        )
    }

    private var rpePlaceholder: String {
        return set.placeholderRPE.map(WorkoutFormatters.number) ?? "RPE"
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
