import BarosCore
import SwiftData
import SwiftUI

struct AddExerciseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    var onAddExercise: (LoggedExercise) -> Void = { _ in }
    @State private var showsAddError = false

    var body: some View {
        NavigationStack {
            ExercisePickerView(
                mode: .add(existingExerciseIDs: Set(session.sortedLoggedExercises.compactMap { $0.exercise?.id }))
            ) { exercises in
                do {
                    let loggedExercises = try engine.addExercises(
                        exercises,
                        to: session,
                        ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                        context: modelContext
                    )
                    if let firstExercise = loggedExercises.first {
                        onAddExercise(firstExercise)
                    }
                    dismiss()
                } catch {
                    showsAddError = true
                }
            }
            .alert("Couldn't Add Exercises", isPresented: $showsAddError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The exercises weren't added. Your selection is still here. Try adding them again, or cancel to return to your workout.")
            }
        }
        .presentationDetents([.large])
    }
}

struct SwapExerciseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let loggedExercise: LoggedExercise
    @Bindable var engine: ActiveWorkoutEngine
    @State private var swapErrorMessage: String?
    @State private var isSwapping = false
    /// Taken when the sheet opens: a committed swap deletes the sets, and the bar must not change while the sheet closes.
    @State private var impact: SwapExerciseImpact

    init(loggedExercise: LoggedExercise, engine: ActiveWorkoutEngine) {
        self.loggedExercise = loggedExercise
        self.engine = engine
        _impact = State(initialValue: SwapExerciseImpact(original: loggedExercise))
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { swapErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    swapErrorMessage = nil
                    engine.lastErrorMessage = nil
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            // The picker's confirm bar states what the swap removes, so it commits without another prompt.
            ExercisePickerView(mode: .swap(impact)) { exercises in
                if let replacement = exercises.first {
                    swap(with: replacement)
                }
            }
            .alert("Unable to Swap Exercise", isPresented: isErrorPresented) {
                Button("OK", role: .cancel) {
                    swapErrorMessage = nil
                    engine.lastErrorMessage = nil
                }
            } message: {
                Text(swapErrorMessage ?? "The exercise could not be swapped.")
            }
        }
        .presentationDetents([.large])
    }

    private func swap(with exercise: Exercise) {
        // A second tap while the sheet closes would swap an exercise that is already gone.
        guard !isSwapping else { return }
        isSwapping = true
        do {
            try engine.swapLoggedExercise(
                loggedExercise,
                with: exercise,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                context: modelContext
            )
            dismiss()
        } catch {
            isSwapping = false
            let message = error.localizedDescription
            engine.lastErrorMessage = message
            swapErrorMessage = message
        }
    }
}
