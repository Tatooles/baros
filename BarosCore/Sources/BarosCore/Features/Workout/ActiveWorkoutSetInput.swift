import Foundation

public enum ActiveWorkoutSetSuggestions {
    public static func resolve(
        for orderedValues: [ActiveWorkoutSetInput.Values]
    ) -> [ActiveWorkoutSetInput.Values] {
        var preceding = ActiveWorkoutSetInput.Values()
        return orderedValues.map { values in
            let suggestion = preceding
            preceding.weight = WorkoutNumericInputPolicy.validatedWeight(values.weight) ?? preceding.weight
            preceding.reps = WorkoutNumericInputPolicy.validatedReps(values.reps) ?? preceding.reps
            preceding.durationSeconds = WorkoutNumericInputPolicy.validatedDuration(values.durationSeconds)
                ?? preceding.durationSeconds
            return suggestion
        }
    }
}

public struct ActiveWorkoutSetInput {
    public enum Field {
        case weight
        case reps
        case duration
    }

    public struct Values: Equatable {
        var weight: Double?
        var reps: Int?
        var durationSeconds: Int?

        public init(weight: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil) {
            self.weight = weight
            self.reps = reps
            self.durationSeconds = durationSeconds
        }

        public init(_ set: LoggedSet) {
            self.init(weight: set.weight, reps: set.reps, durationSeconds: set.durationSeconds)
        }

        public func settingDuration(_ seconds: Int?) -> Values {
            var values = validated
            values.durationSeconds = WorkoutNumericInputPolicy.validatedDuration(seconds)
            return values
        }

        public func timePickerStart(suggestions: Values, previous: PreviousSetPerformance?) -> Int {
            WorkoutNumericInputPolicy.validatedDuration(durationSeconds)
                ?? WorkoutNumericInputPolicy.validatedDuration(suggestions.durationSeconds)
                ?? WorkoutNumericInputPolicy.validatedDuration(previous?.durationSeconds)
                ?? 0
        }

        var validated: Values {
            Values(
                weight: WorkoutNumericInputPolicy.validatedWeight(weight),
                reps: WorkoutNumericInputPolicy.validatedReps(reps),
                durationSeconds: WorkoutNumericInputPolicy.validatedDuration(durationSeconds)
            )
        }

        func write(to set: LoggedSet) {
            set.weight = weight
            set.reps = reps
            if durationSeconds != nil, set.durationSeconds != durationSeconds { set.knowsDuration = true }
            set.durationSeconds = durationSeconds
        }
    }

    public struct Commit: Equatable {
        public let values: Values
        public let shouldPersist: Bool
    }

    private var weightInput = WorkoutNumberInputText()
    private var repsInput = WorkoutNumberInputText()
    private var rejectedWeight = false
    private var rejectedReps = false

    public init() {}

    public mutating func update(_ text: String, for field: Field, isFocused: Bool) {
        switch field {
        case .weight:
            weightInput.updateDraft(text, isFocused: isFocused)
        case .reps:
            repsInput.updateDraft(text, isFocused: isFocused)
        case .duration:
            break
        }
    }

    public func text(for field: Field, values: Values, weightUnit: MeasurementUnit) -> String {
        switch field {
        case .weight:
            let validWeight = WorkoutNumericInputPolicy.validatedWeight(values.weight)
            let displayWeight = weightUnit.displayWeight(fromCanonicalPounds: validWeight)
            return weightInput.displayText(for: displayWeight)
        case .reps:
            let validReps = WorkoutNumericInputPolicy.validatedReps(values.reps)
            return repsInput.displayText(fallback: validReps.map(String.init) ?? "")
        case .duration:
            let validDuration = WorkoutNumericInputPolicy.validatedDuration(values.durationSeconds)
            return validDuration.map(WorkoutFormatters.setDuration) ?? ""
        }
    }

    public func suggestionText(
        for field: Field,
        current: Values,
        suggestions: Values,
        weightUnit: MeasurementUnit
    ) -> String? {
        switch field {
        case .weight:
            guard weightInput.draftText == nil, !rejectedWeight,
                  WorkoutNumericInputPolicy.validatedWeight(current.weight) == nil
            else { return nil }
            let weight = WorkoutNumericInputPolicy.validatedWeight(suggestions.weight)
            return weightUnit.displayWeight(fromCanonicalPounds: weight).map(WorkoutFormatters.number)
        case .reps:
            guard repsInput.draftText == nil, !rejectedReps,
                  WorkoutNumericInputPolicy.validatedReps(current.reps) == nil
            else { return nil }
            return WorkoutNumericInputPolicy.validatedReps(suggestions.reps).map(String.init)
        case .duration:
            guard WorkoutNumericInputPolicy.validatedDuration(current.durationSeconds) == nil
            else { return nil }
            return WorkoutNumericInputPolicy.validatedDuration(suggestions.durationSeconds)
                .map(WorkoutFormatters.setDuration)
        }
    }

    public func previewValues(current: Values, weightUnit: MeasurementUnit) -> Values? {
        guard hasDraft else { return nil }
        var preview = self
        return preview.commit(current: current, weightUnit: weightUnit).values
    }

    private var hasDraft: Bool {
        weightInput.draftText != nil || repsInput.draftText != nil
    }

    public mutating func commit(current: Values, weightUnit: MeasurementUnit) -> Commit {
        let storedValues = current.validated

        guard hasDraft else {
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

        let values = Values(weight: weight, reps: reps, durationSeconds: storedValues.durationSeconds)
        return Commit(values: values, shouldPersist: values != storedValues)
    }

    func preparedLinkedValues(current: Values, previous: PreviousSetPerformance?, suggestions: Values) -> Values {
        var input = self
        return input.preparedValuesForSetAction(current: current, weightUnit: .pounds,
            completesSet: true, isCompleted: false, previous: previous, suggestions: suggestions)
    }

    public mutating func preparedValuesForSetAction(
        current: Values,
        weightUnit: MeasurementUnit,
        completesSet: Bool,
        isCompleted: Bool,
        previous: PreviousSetPerformance?,
        suggestions: Values = .init()
    ) -> Values {
        let committedValues = commit(current: current, weightUnit: weightUnit).values
        let fallback = PreviousSetPerformance(
            weight: WorkoutNumericInputPolicy.validatedWeight(suggestions.weight)
                ?? WorkoutNumericInputPolicy.validatedWeight(previous?.weight),
            reps: WorkoutNumericInputPolicy.validatedReps(suggestions.reps)
                ?? WorkoutNumericInputPolicy.validatedReps(previous?.reps),
            durationSeconds: WorkoutNumericInputPolicy.validatedDuration(suggestions.durationSeconds)
                ?? WorkoutNumericInputPolicy.validatedDuration(previous?.durationSeconds)
        )
        guard completesSet,
              let previousFill = previousFillBeforeCompletion(
                isCompleted: isCompleted,
                values: committedValues,
                previous: fallback
              )
        else { return committedValues }

        let preparedValues = Values(
            weight: committedValues.weight ?? previousFill.weight,
            reps: committedValues.reps ?? previousFill.reps,
            durationSeconds: committedValues.durationSeconds ?? previousFill.durationSeconds
        )
        clearRejectionsSatisfiedByPreviousFill(preparedValues)
        return preparedValues
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
        let duration = WorkoutNumericInputPolicy.validatedDuration(values.durationSeconds) == nil
            ? WorkoutNumericInputPolicy.validatedDuration(previous.durationSeconds)
            : nil

        guard weight != nil || reps != nil || duration != nil else { return nil }
        return PreviousSetPerformance(weight: weight, reps: reps, durationSeconds: duration)
    }

    public mutating func clearRejectionsSatisfiedByPreviousFill(_ values: Values) {
        if WorkoutNumericInputPolicy.validatedWeight(values.weight) != nil {
            rejectedWeight = false
        }
        if WorkoutNumericInputPolicy.validatedReps(values.reps) != nil {
            rejectedReps = false
        }
    }
}

@MainActor
public final class ActiveSetInputRegistry {
    public init() {}

    public typealias LinkedPreparation = (ActiveWorkoutSetInput.Values, PreviousSetPerformance?, ActiveWorkoutSetInput.Values) -> ActiveWorkoutSetInput.Values

    private struct Registration {
        var prepareLinked: LinkedPreparation?
        var fields: Set<WorkoutField>
        var commit: () -> Void
        var prepareForRPESelection: ((Bool) -> ActiveWorkoutSetInput.Values)?
    }

    private var registrations: [UUID: Registration] = [:]
    private var registrationIDs: [WorkoutField: UUID] = [:]

    @discardableResult
    public func register(
        fields: [WorkoutField],
        commit: @escaping () -> Void,
        prepareForRPESelection: ((Bool) -> ActiveWorkoutSetInput.Values)? = nil,
        prepareLinked: LinkedPreparation? = nil
    ) -> UUID {
        let id = UUID()
        guard !fields.isEmpty else { return id }
        for field in fields {
            if let previousID = registrationIDs[field] {
                registrations[previousID]?.fields.remove(field)
                if registrations[previousID]?.fields.isEmpty == true {
                    registrations.removeValue(forKey: previousID)
                }
            }
            registrationIDs[field] = id
        }
        registrations[id] = Registration(
            prepareLinked: prepareLinked,
            fields: Set(fields),
            commit: commit,
            prepareForRPESelection: prepareForRPESelection
        )
        return id
    }

    public func commit(_ field: WorkoutField?) {
        guard let field, let id = registrationIDs[field] else { return }
        registrations[id]?.commit()
    }

    public func prepareSetValues(
        for field: WorkoutField?,
        completesSet: Bool
    ) -> ActiveWorkoutSetInput.Values? {
        guard let field, let id = registrationIDs[field] else { return nil }
        return registrations[id]?.prepareForRPESelection?(completesSet)
    }

    func prepareLinkedSet(id: UUID, current: ActiveWorkoutSetInput.Values,
                          previous: PreviousSetPerformance?, suggestions: ActiveWorkoutSetInput.Values) -> ActiveWorkoutSetInput.Values? {
        guard let registration = registrationIDs[.setReps(id)] else { return nil }
        return registrations[registration]?.prepareLinked?(current, previous, suggestions)
    }

    public func updateRegistration(
        _ id: UUID,
        commit: @escaping () -> Void,
        prepareForRPESelection: ((Bool) -> ActiveWorkoutSetInput.Values)?,
        prepareLinked: LinkedPreparation? = nil
    ) {
        guard var registration = registrations[id] else { return }
        registration.prepareLinked = prepareLinked
        registration.commit = commit
        registration.prepareForRPESelection = prepareForRPESelection
        registrations[id] = registration
    }

    public func unregister(_ id: UUID) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        for field in registration.fields {
            registrationIDs.removeValue(forKey: field)
        }
    }
}
