import Foundation
import Observation

@MainActor
final class ActiveWorkoutSetDraftStore {
    private var drafts: [UUID: ActiveWorkoutSetDraft] = [:]

    func draft(for setID: UUID) -> ActiveWorkoutSetDraft {
        if let draft = drafts[setID] {
            return draft
        }

        let draft = ActiveWorkoutSetDraft()
        drafts[setID] = draft
        return draft
    }

    func existingDraft(for setID: UUID) -> ActiveWorkoutSetDraft? {
        drafts[setID]
    }

    func existingDrafts() -> [(setID: UUID, draft: ActiveWorkoutSetDraft)] {
        drafts.map { (setID: $0.key, draft: $0.value) }
    }
}

@Observable
@MainActor
final class ActiveWorkoutSetDraft {
    private var input = ActiveWorkoutSetInput()

    func update(_ text: String, for field: ActiveWorkoutSetInput.Field, isFocused: Bool) {
        input.update(text, for: field, isFocused: isFocused)
    }

    func text(
        for field: ActiveWorkoutSetInput.Field,
        values: ActiveWorkoutSetInput.Values,
        weightUnit: MeasurementUnit
    ) -> String {
        input.text(for: field, values: values, weightUnit: weightUnit)
    }

    func commit(
        current: ActiveWorkoutSetInput.Values,
        weightUnit: MeasurementUnit
    ) -> ActiveWorkoutSetInput.Commit {
        input.commit(current: current, weightUnit: weightUnit)
    }

    func previousFillBeforeCompletion(
        isCompleted: Bool,
        values: ActiveWorkoutSetInput.Values,
        previous: PreviousSetPerformance?
    ) -> PreviousSetPerformance? {
        input.previousFillBeforeCompletion(
            isCompleted: isCompleted,
            values: values,
            previous: previous
        )
    }

    func clearRejectionsSatisfiedByPreviousFill(_ values: ActiveWorkoutSetInput.Values) {
        input.clearRejectionsSatisfiedByPreviousFill(values)
    }
}

struct ActiveWorkoutSetInput {
    enum Field {
        case weight
        case reps
    }

    struct Values: Equatable {
        var weight: Double?
        var reps: Int?
    }

    struct Commit: Equatable {
        let values: Values
        let shouldPersist: Bool
    }

    private var weightInput = WorkoutNumberInputText()
    private var repsInput = WorkoutNumberInputText()
    private var rejectedWeight = false
    private var rejectedReps = false

    mutating func update(_ text: String, for field: Field, isFocused: Bool) {
        switch field {
        case .weight:
            weightInput.updateDraft(text, isFocused: isFocused)
        case .reps:
            repsInput.updateDraft(text, isFocused: isFocused)
        }
    }

    func text(for field: Field, values: Values, weightUnit: MeasurementUnit) -> String {
        switch field {
        case .weight:
            let validWeight = WorkoutNumericInputPolicy.validatedWeight(values.weight)
            let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: validWeight)
            return weightInput.displayText(for: displayWeight)
        case .reps:
            let validReps = WorkoutNumericInputPolicy.validatedReps(values.reps)
            return repsInput.displayText(fallback: validReps.map(String.init) ?? "")
        }
    }

    mutating func commit(current: Values, weightUnit: MeasurementUnit) -> Commit {
        let storedValues = Values(
            weight: WorkoutNumericInputPolicy.validatedWeight(current.weight),
            reps: WorkoutNumericInputPolicy.validatedReps(current.reps)
        )

        guard weightInput.draftText != nil || repsInput.draftText != nil else {
            return Commit(values: storedValues, shouldPersist: false)
        }

        let weight: Double?
        if let weightDraft = weightInput.draftText {
            weight = WorkoutNumericInputPolicy.parseWeight(weightDraft, unit: weightUnit)
            rejectedWeight = !weightDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && weight == nil
        } else {
            weight = WorkoutNumericInputPolicy.validatedWeight(current.weight)
        }

        let reps: Int?
        if let repsDraft = repsInput.draftText {
            reps = WorkoutNumericInputPolicy.parseReps(repsDraft)
            rejectedReps = !repsDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && reps == nil
        } else {
            reps = WorkoutNumericInputPolicy.validatedReps(current.reps)
        }

        weightInput.endEditing()
        repsInput.endEditing()

        let values = Values(weight: weight, reps: reps)
        return Commit(values: values, shouldPersist: values != storedValues)
    }

    func previousFillBeforeCompletion(
        isCompleted: Bool,
        values: Values,
        previous: PreviousSetPerformance?
    ) -> PreviousSetPerformance? {
        guard !isCompleted, let previous else { return nil }

        let weight = !rejectedWeight
            && WorkoutNumericInputPolicy.validatedWeight(values.weight) == nil
            ? WorkoutNumericInputPolicy.validatedWeight(previous.weight)
            : nil
        let reps = !rejectedReps
            && WorkoutNumericInputPolicy.validatedReps(values.reps) == nil
            ? WorkoutNumericInputPolicy.validatedReps(previous.reps)
            : nil

        guard weight != nil || reps != nil else { return nil }
        return PreviousSetPerformance(weight: weight, reps: reps)
    }

    mutating func clearRejectionsSatisfiedByPreviousFill(_ values: Values) {
        if WorkoutNumericInputPolicy.validatedWeight(values.weight) != nil {
            rejectedWeight = false
        }
        if WorkoutNumericInputPolicy.validatedReps(values.reps) != nil {
            rejectedReps = false
        }
    }
}
