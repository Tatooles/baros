import Foundation

struct RetryableWorkoutFieldDraft<Value> {
    var value: Value? = nil

    mutating func commit(_ save: (Value) throws -> Void) throws {
        guard let value else { return }
        try save(value)
        self.value = nil
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
        guard weightInput.draftText != nil || repsInput.draftText != nil else {
            return Commit(
                values: Values(
                    weight: WorkoutNumericInputPolicy.validatedWeight(current.weight),
                    reps: WorkoutNumericInputPolicy.validatedReps(current.reps)
                ),
                shouldPersist: false
            )
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

        return Commit(
            values: Values(weight: weight, reps: reps),
            shouldPersist: true
        )
    }

    mutating func acceptCommit() {
        weightInput.endEditing()
        repsInput.endEditing()
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
