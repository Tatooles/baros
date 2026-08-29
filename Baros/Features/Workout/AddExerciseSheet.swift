import SwiftData
import SwiftUI

struct AddExerciseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    var onAddExercise: (LoggedExercise) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            ExercisePickerView { exercise in
                do {
                    let loggedExercise = try engine.addExercise(exercise, to: session, context: modelContext)
                    onAddExercise(loggedExercise)
                    dismiss()
                } catch {
                    engine.lastErrorMessage = error.localizedDescription
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct SwapExerciseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let loggedExercise: LoggedExercise
    @Bindable var engine: ActiveWorkoutEngine
    var onSwapExercise: (LoggedExercise) -> Void = { _ in }
    @State private var pendingReplacement: Exercise?

    private var isConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingReplacement != nil },
            set: { isPresented in
                if !isPresented {
                    pendingReplacement = nil
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ExercisePickerView(
                mode: .swap(currentExerciseID: loggedExercise.exercise?.id)
            ) { exercise in
                pendingReplacement = exercise
            }
        }
        .alert(confirmationTitle, isPresented: isConfirmationPresented) {
            if let pendingReplacement {
                Button("Swap Exercise", role: .destructive) {
                    confirmSwap(with: pendingReplacement)
                }
                .accessibilityIdentifier("ConfirmSwapExerciseButton")
            }
            Button("Cancel", role: .cancel) {
                pendingReplacement = nil
            }
            .accessibilityIdentifier("CancelSwapExerciseButton")
        } message: {
            Text(
                "This removes \(loggedExercise.exerciseSnapshotName), its sets, "
                    + "and its exercise note from this workout."
            )
        }
        .presentationDetents([.large])
    }

    private var confirmationTitle: String {
        guard let pendingReplacement else { return "Swap Exercise?" }
        return "Swap \(loggedExercise.exerciseSnapshotName) for \(pendingReplacement.name)?"
    }

    private func confirmSwap(with exercise: Exercise) {
        do {
            let replacement = try engine.swapLoggedExercise(
                loggedExercise,
                with: exercise,
                context: modelContext
            )
            onSwapExercise(replacement)
            dismiss()
        } catch {
            pendingReplacement = nil
            engine.lastErrorMessage = error.localizedDescription
        }
    }
}
