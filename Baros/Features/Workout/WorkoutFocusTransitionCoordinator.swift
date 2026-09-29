import Foundation

/// Tracks the focused Active Workout field so the departing field commits its
/// draft once, whether focus moves programmatically or from a tap.
@MainActor
final class WorkoutFocusTransitionCoordinator {
    private(set) var currentField: WorkoutField?
    private var revealTask: Task<Void, Never>?

    func synchronizeFocus(_ focusedField: WorkoutField?) {
        currentField = focusedField
    }

    func transition(
        to target: WorkoutField?,
        commit: (WorkoutField?) -> Void,
        assign: (WorkoutField?) -> Void
    ) {
        guard target != currentField else { return }

        commit(currentField)
        currentField = target
        cancelPendingReveal()
        assign(target)
    }

    func observeFocusChange(
        from previousField: WorkoutField?,
        to newField: WorkoutField?,
        commit: (WorkoutField?) -> Void
    ) {
        // Programmatic transitions update currentField synchronously before
        // assigning FocusState. Their onChange notification is only an
        // acknowledgement and must not cancel a reveal they scheduled.
        guard currentField != newField else { return }

        commit(previousField)
        currentField = newField
        cancelPendingReveal()
    }

    /// Runs `reveal` after `delay` unless focus changes first.
    func scheduleReveal(
        after delay: Duration,
        _ reveal: @escaping @MainActor () -> Void
    ) {
        cancelPendingReveal()
        revealTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            reveal()
            self?.revealTask = nil
        }
    }

    func cancelPendingReveal() {
        revealTask?.cancel()
        revealTask = nil
    }
}
