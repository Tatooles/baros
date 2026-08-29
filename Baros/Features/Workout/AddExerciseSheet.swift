import SwiftData
import SwiftUI

struct SwapExerciseConfirmationContent {
    let title: String
    let message: String

    init(original: LoggedExercise, replacement: Exercise) {
        let originalName = original.exerciseSnapshotName
        let replacementName = replacement.name
        let hasMatchingNames = originalName.localizedCaseInsensitiveCompare(replacementName) == .orderedSame
        let originalDescription = hasMatchingNames
            ? "\(originalName) (\(original.snapshotEquipment?.displayName ?? "Other"))"
            : originalName
        let replacementDescription = hasMatchingNames
            ? "\(replacementName) (\(replacement.equipment.displayName))"
            : replacementName

        title = "Swap \(originalDescription) for \(replacementDescription)?"
        message = "This removes \(originalName), its sets, and its exercise note from this workout."
    }
}

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
    @State private var pendingReplacement: Exercise?
    @State private var swapErrorMessage: String?

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
            ExercisePickerView(
                mode: .swap(currentExerciseID: loggedExercise.exercise?.id)
            ) { exercise in
                pendingReplacement = exercise
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
            Text(confirmationContent?.message ?? "The original exercise will be removed.")
        }
        .presentationDetents([.large])
    }

    private var confirmationContent: SwapExerciseConfirmationContent? {
        pendingReplacement.map {
            SwapExerciseConfirmationContent(original: loggedExercise, replacement: $0)
        }
    }

    private var confirmationTitle: String {
        confirmationContent?.title ?? "Swap Exercise?"
    }

    private func confirmSwap(with exercise: Exercise) {
        do {
            try engine.swapLoggedExercise(
                loggedExercise,
                with: exercise,
                context: modelContext
            )
            dismiss()
        } catch {
            pendingReplacement = nil
            let message = error.localizedDescription
            engine.lastErrorMessage = message
            swapErrorMessage = message
        }
    }
}
