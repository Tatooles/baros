import Foundation

enum WorkoutFocusNavigator {
    static func focusOrder(
        for session: WorkoutSession,
        collapsedExerciseIDs: Set<UUID> = [],
        revealedExerciseNoteIDs: Set<UUID> = [],
        isWorkoutNoteRevealed: Bool = false
    ) -> [WorkoutField] {
        var fields: [WorkoutField] = [.workoutTitle]
        if isWorkoutNoteRevealed
            || !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(.workoutNotes)
        }

        for loggedExercise in session.sortedLoggedExercises {
            guard !collapsedExerciseIDs.contains(loggedExercise.id) else { continue }

            for set in loggedExercise.sortedSets {
                fields.append(.setWeight(set.id))
                fields.append(.setReps(set.id))
            }
            if revealedExerciseNoteIDs.contains(loggedExercise.id)
                || !loggedExercise.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields.append(.exerciseNotes(loggedExercise.id))
            }
        }

        return fields
    }

    static func adjacentField(
        from currentField: WorkoutField?,
        in focusOrder: [WorkoutField],
        offset: Int
    ) -> WorkoutField? {
        guard
            let currentField,
            let currentIndex = focusOrder.firstIndex(of: currentField)
        else { return nil }

        let targetIndex = currentIndex + offset
        guard focusOrder.indices.contains(targetIndex) else { return nil }

        return focusOrder[targetIndex]
    }
}
