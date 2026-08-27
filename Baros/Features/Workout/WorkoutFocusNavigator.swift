import Foundation

enum WorkoutFocusNavigator {
    struct StructureInputs: Equatable {
        var collapsedExerciseIDs: Set<UUID> = []
        var revealedExerciseNoteIDs: Set<UUID> = []
        var isWorkoutNoteRevealed = false
    }

    struct StructureKey: Equatable {
        private struct ExerciseEntry: Equatable {
            let id: UUID
            let setIDs: [UUID]
            let includesNotes: Bool
        }

        private let exerciseEntries: [ExerciseEntry]
        private let collapsedExerciseIDs: Set<UUID>
        private let includesWorkoutNotes: Bool

        init(
            session: WorkoutSession,
            inputs: StructureInputs
        ) {
            exerciseEntries = session.sortedLoggedExercises.map { loggedExercise in
                ExerciseEntry(
                    id: loggedExercise.id,
                    setIDs: loggedExercise.sortedSets.map(\.id),
                    includesNotes: inputs.revealedExerciseNoteIDs.contains(loggedExercise.id)
                        || !loggedExercise.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            collapsedExerciseIDs = inputs.collapsedExerciseIDs
            includesWorkoutNotes = inputs.isWorkoutNoteRevealed
                || !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func focusOrder(
        for session: WorkoutSession,
        inputs: StructureInputs = StructureInputs()
    ) -> [WorkoutField] {
        var fields: [WorkoutField] = [.workoutTitle]
        if inputs.isWorkoutNoteRevealed
            || !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(.workoutNotes)
        }

        for loggedExercise in session.sortedLoggedExercises {
            guard !inputs.collapsedExerciseIDs.contains(loggedExercise.id) else { continue }

            for set in loggedExercise.sortedSets {
                fields.append(.setWeight(set.id))
                fields.append(.setReps(set.id))
            }
            if inputs.revealedExerciseNoteIDs.contains(loggedExercise.id)
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

@MainActor
final class WorkoutFocusOrderCache {
    private var structureKey: WorkoutFocusNavigator.StructureKey?
    private(set) var order: [WorkoutField] = []
    private(set) var rebuildCount = 0

    @discardableResult
    func update(
        for session: WorkoutSession,
        inputs: WorkoutFocusNavigator.StructureInputs
    ) -> [WorkoutField] {
        update(
            for: session,
            inputs: inputs,
            structureKey: WorkoutFocusNavigator.StructureKey(
                session: session,
                inputs: inputs
            )
        )
    }

    @discardableResult
    func update(
        for session: WorkoutSession,
        inputs: WorkoutFocusNavigator.StructureInputs,
        structureKey nextKey: WorkoutFocusNavigator.StructureKey
    ) -> [WorkoutField] {
        guard nextKey != structureKey else { return order }

        structureKey = nextKey
        order = WorkoutFocusNavigator.focusOrder(
            for: session,
            inputs: inputs
        )
        rebuildCount += 1
        return order
    }
}

@MainActor
final class WorkoutFocusTransitionCoordinator {
    private(set) var currentField: WorkoutField?
    private var focusOrder: [WorkoutField] = []
    private var revealTask: Task<Void, Never>?
    private let revealDelay: Duration

    init(revealDelay: Duration = .milliseconds(250)) {
        self.revealDelay = revealDelay
    }

    func updateFocusOrder(_ focusOrder: [WorkoutField]) {
        self.focusOrder = focusOrder
    }

    func synchronizeFocus(_ focusedField: WorkoutField?) {
        currentField = focusedField
    }

    func adjacentField(offset: Int) -> WorkoutField? {
        WorkoutFocusNavigator.adjacentField(
            from: currentField,
            in: focusOrder,
            offset: offset
        )
    }

    @discardableResult
    func move(
        offset: Int,
        commit: (WorkoutField?) -> Void,
        assign: (WorkoutField) -> Void,
        reveal: @escaping @MainActor (WorkoutField) -> Void
    ) -> WorkoutField? {
        guard let target = adjacentField(offset: offset) else { return nil }

        transition(
            to: target,
            commit: commit,
            assign: { field in
                guard let field else { return }
                assign(field)
            },
            reveal: reveal
        )
        return target
    }

    func transition(
        to target: WorkoutField?,
        delay: Duration? = nil,
        commit: (WorkoutField?) -> Void,
        assign: (WorkoutField?) -> Void,
        reveal: @escaping @MainActor (WorkoutField) -> Void
    ) {
        guard target != currentField else { return }

        commit(currentField)
        currentField = target
        if let target {
            scheduleLatestReveal(target, delay: delay, reveal: reveal)
        } else {
            cancelPendingReveal()
        }
        assign(target)
    }

    func observeFocusChange(
        from previousField: WorkoutField?,
        to newField: WorkoutField?,
        commit: (WorkoutField?) -> Void,
        reveal: @escaping @MainActor (WorkoutField) -> Void
    ) {
        // Programmatic transitions update currentField synchronously before
        // assigning FocusState. Their onChange notification is only an
        // acknowledgement and must not restart the delayed reveal.
        guard currentField != newField else { return }

        commit(previousField)
        currentField = newField
        if let newField {
            scheduleLatestReveal(newField, reveal: reveal)
        } else {
            cancelPendingReveal()
        }
    }

    func cancelPendingReveal() {
        revealTask?.cancel()
        revealTask = nil
    }

    private func scheduleLatestReveal(
        _ field: WorkoutField,
        delay: Duration? = nil,
        reveal: @escaping @MainActor (WorkoutField) -> Void
    ) {
        cancelPendingReveal()
        let delay = delay ?? revealDelay
        revealTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            reveal(field)
            self?.revealTask = nil
        }
    }
}

@MainActor
final class WorkoutFieldCommitRegistry {
    private struct Registration {
        let id: UUID
        let commit: () -> Void
    }

    private var registrations: [WorkoutField: Registration] = [:]

    @discardableResult
    func register(fields: [WorkoutField], commit: @escaping () -> Void) -> UUID {
        let id = UUID()
        let registration = Registration(id: id, commit: commit)
        for field in fields {
            registrations[field] = registration
        }
        return id
    }

    func commit(_ field: WorkoutField?) {
        guard let field else { return }
        registrations[field]?.commit()
    }

    func unregister(_ id: UUID) {
        registrations = registrations.filter { $0.value.id != id }
    }
}
