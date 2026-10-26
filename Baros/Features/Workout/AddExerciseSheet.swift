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
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    var onAddExercise: (LoggedExercise) -> Void = { _ in }
    @State private var showsAddError = false
    @State private var insertionIndex: Int

    init(session: WorkoutSession, engine: ActiveWorkoutEngine, onAddExercise: @escaping (LoggedExercise) -> Void = { _ in }) {
        self.session = session
        self.engine = engine
        self.onAddExercise = onAddExercise
        _insertionIndex = State(initialValue: defaultExerciseInsertionIndex(in: WorkoutExerciseListSnapshot(session: session).exercises))
    }

    private var placementLine: some View {
        Menu {
            Text("Add to workout")
            Picker("Add to workout", selection: $insertionIndex) {
                Text("At the start").tag(0)
                ForEach(Array(session.sortedLoggedExercises.dropLast().enumerated()), id: \.element.id) { index, exercise in
                    Text("After \(exercise.exerciseSnapshotName)").tag(index + 1)
                }
                Text("At the end").tag(session.sortedLoggedExercises.count)
            }
        } label: {
            HStack(spacing: 5) {
                if insertionIndex == 0 {
                    Text("Adds at the start")
                } else if insertionIndex >= session.sortedLoggedExercises.count {
                    Text("Adds at the end")
                } else {
                    Text("Adds after")
                    Text(session.sortedLoggedExercises[insertionIndex - 1].exerciseSnapshotName)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.groupedSurface, in: Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Add to workout")
        .accessibilityIdentifier("ExerciseInsertionMenu")
    }

    var body: some View {
        NavigationStack {
            ExercisePickerView(
                mode: .add(existingExerciseIDs: Set(session.sortedLoggedExercises.compactMap { $0.exercise?.id })),
                placementAccessory: session.sortedLoggedExercises.isEmpty ? nil : AnyView(placementLine)
            ) { exercises in
                do {
                    let loggedExercises = try engine.addExercises(
                        exercises,
                        to: session,
                        insertionIndex: insertionIndex,
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
            ) { exercises in
                pendingReplacement = exercises.first
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
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
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
