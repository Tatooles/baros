import SwiftData
import SwiftUI

struct ReorderExercisesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @State private var draft: WorkoutExerciseListDraft
    @State private var showsPicker = false
    @State private var detent: PresentationDetent = .large
    @State private var alert: SaveAlert?
    @State private var removalConfirmation: RemovalConfirmation?
    /// Shown once the removal confirmation has finished dismissing.
    @State private var alertAfterConfirmation: SaveAlert?

    private enum SaveAlert: String, Identifiable {
        case failure, conflict
        var id: Self { self }
    }

    /// Carries its exercises so a reloaded draft cannot change it while it dismisses.
    private struct RemovalConfirmation: Identifiable {
        let id = UUID()
        let exercises: [WorkoutExerciseListSnapshot.ExerciseState]
    }

    init(session: WorkoutSession, engine: ActiveWorkoutEngine) {
        self.session = session
        self.engine = engine
        _draft = State(initialValue: WorkoutExerciseListDraft(session: session))
    }

    var body: some View {
        NavigationStack {
            ReorderExercisesList(
                exercises: draft.exercises,
                reorder: { draft.orderedIDs = $0 },
                remove: { ids in draft.orderedIDs.removeAll(where: ids.contains) },
                add: {
                    detent = .large
                    showsPicker = true
                }
            )
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .overlay {
                if draft.orderedIDs.isEmpty {
                    Text("No exercises")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("ReorderExercisesEmptyState")
                }
            }
            .navigationDestination(isPresented: $showsPicker) {
                ExercisePickerView(mode: .add(existingExerciseIDs: existingExerciseIDs), showsCancel: false) { exercises in
                    draft.append(exercises)
                    showsPicker = false
                }
            }
            .navigationTitle("Edit Workout")
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
        .sheet(item: $removalConfirmation, onDismiss: {
            alert = alertAfterConfirmation
            alertAfterConfirmation = nil
        }) { confirmation in
            ReorderRemovalConfirmation(
                exercises: confirmation.exercises,
                confirm: confirmRemoval,
                keepEditing: { removalConfirmation = nil }
            )
        }
        .alert(item: $alert) { alert in
            switch alert {
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
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private var existingExerciseIDs: Set<UUID> {
        let remaining = Set(draft.orderedIDs)
        return Set(session.sortedLoggedExercises.filter { remaining.contains($0.id) }.compactMap { $0.exercise?.id }
            + draft.additions.filter { remaining.contains($0.id) }.map { $0.exercise.id })
    }

    private func prepareToSave() {
        if draft.needsRemovalConfirmation, draft.baseline == WorkoutExerciseListSnapshot(session: session) {
            removalConfirmation = RemovalConfirmation(exercises: draft.removedExercises)
        } else if let failure = saveChanges() {
            alert = failure
        }
    }

    private func confirmRemoval() {
        // Success dismisses this sheet with its confirmation; otherwise the alert follows it.
        alertAfterConfirmation = saveChanges()
        if alertAfterConfirmation != nil { removalConfirmation = nil }
    }

    /// Returns the alert to show when the draft could not be saved.
    private func saveChanges() -> SaveAlert? {
        // Revalidate after the confirmation as sync can arrive while it is open.
        guard draft.baseline == WorkoutExerciseListSnapshot(session: session) else {
            draft = WorkoutExerciseListDraft(session: session)
            return .conflict
        }
        do {
            try engine.applyExerciseListChanges(
                in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline,
                additions: draft.additions,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                context: modelContext
            )
            dismiss()
            return nil
        } catch {
            return .failure
        }
    }
}

/// Lists each removed exercise on its own row so long names stay readable.
private struct ReorderRemovalConfirmation: View {
    let exercises: [WorkoutExerciseListSnapshot.ExerciseState]
    let confirm: () -> Void
    let keepEditing: () -> Void
    @State private var contentHeight: CGFloat = 420

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                let isSingle = exercises.count == 1
                VStack(spacing: 6) {
                    Text(isSingle ? "Remove Exercise?" : "Remove \(exercises.count) Exercises?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(isSingle ? "Its sets will be removed from this workout." : "Their sets will be removed from this workout.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 28)

                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        if index > 0 { Divider().padding(.leading, 16) }
                        row(exercise)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
                        .fill(AppTheme.groupedSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
                        .stroke(AppTheme.subtleBorder)
                )

                VStack(spacing: 14) {
                    Button(action: confirm) {
                        Text("Remove and Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AppTheme.destructiveFill)

                    Button("Keep Editing", action: keepEditing)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .presentationDetents([.height(contentHeight)])
        .presentationCornerRadius(36)
        .presentationDragIndicator(.visible)
    }

    private func row(_ exercise: WorkoutExerciseListSnapshot.ExerciseState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(exercise.loggedSetsText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ReorderRemovalSummaryRow")
    }
}
