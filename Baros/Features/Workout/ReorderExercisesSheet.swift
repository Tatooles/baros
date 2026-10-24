import SwiftData
import SwiftUI

struct ReorderExercisesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @State private var draft: WorkoutExerciseListDraft
    @State private var editMode: EditMode = .active
    @State private var revealedExerciseID: UUID?
    @State private var alert: SaveAlert?

    private enum SaveAlert: String, Identifiable {
        case removal, failure, conflict
        var id: Self { self }
    }

    init(session: WorkoutSession, engine: ActiveWorkoutEngine) {
        self.session = session
        self.engine = engine
        _draft = State(initialValue: WorkoutExerciseListDraft(session: session))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(draft.exercises) { exercise in
                    ReorderExerciseRow(
                        exercise: exercise,
                        isRevealed: revealedExerciseID == exercise.id,
                        reveal: { animate { revealedExerciseID = exercise.id } },
                        collapse: { animate { revealedExerciseID = nil } },
                        remove: {
                            animate {
                                draft.orderedIDs.removeAll { $0 == exercise.id }
                                revealedExerciseID = nil
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 6))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    revealedExerciseID = nil
                    draft.orderedIDs.move(fromOffsets: source, toOffset: destination)
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .onTapGesture { animate { revealedExerciseID = nil } }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { animate { revealedExerciseID = nil } }
            }
            .accessibilityIdentifier("ReorderExercisesList")
            .environment(\.editMode, $editMode)
            .overlay {
                if draft.orderedIDs.isEmpty {
                    Text("No exercises")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("ReorderExercisesEmptyState")
                }
            }
            .navigationTitle("Reorder Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("CancelReorderExercisesButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: prepareToSave)
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityIdentifier("DoneReorderExercisesButton")
                }
            }
        }
        .alert(item: $alert) { alert in
            switch alert {
            case .removal:
                Alert(
                    title: Text("Remove Exercises?"),
                    message: Text(draft.removalMessage),
                    primaryButton: .destructive(Text("Remove and Save"), action: saveChanges),
                    secondaryButton: .cancel(Text("Keep Editing"))
                )
            case .failure:
                Alert(
                    title: Text("Couldn't Save Changes"),
                    message: Text("Your workout wasn't changed. Tap Done to retry, or Cancel to discard your edits."),
                    dismissButton: .cancel(Text("OK"))
                )
            case .conflict:
                Alert(
                    title: Text("Workout Changed"),
                    message: Text("The current exercises have been reloaded. Review them before making your changes again."),
                    dismissButton: .cancel(Text("OK"))
                )
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func animate(_ changes: () -> Void) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25), changes)
    }

    private func prepareToSave() {
        revealedExerciseID = nil
        guard validateBaseline() else { return }
        if draft.needsRemovalConfirmation {
            alert = .removal
        } else {
            saveChanges()
        }
    }

    private func validateBaseline() -> Bool {
        guard draft.baseline == WorkoutExerciseListSnapshot(session: session) else {
            draft = WorkoutExerciseListDraft(session: session)
            alert = .conflict
            return false
        }
        return true
    }

    private func saveChanges() {
        // Revalidate after the confirmation as sync can arrive while it is open.
        guard validateBaseline() else { return }
        do {
            try engine.applyExerciseListChanges(
                in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline,
                context: modelContext
            )
            dismiss()
        } catch {
            alert = .failure
        }
    }
}
