import BarosCore
import SwiftData
import SwiftUI

/// Edits the workout's exercises as a draft: reorder, remove, add and link.
/// Every edit can be undone until Save, and Cancel asks before it discards any.
struct ReorderExercisesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @Query private var sessions: [WorkoutSession]
    @State private var draft: WorkoutExerciseListDraft
    /// The draft before each edit, latest last.
    @State private var history: [WorkoutExerciseListDraft] = []
    @State private var notice: ReorderNotice?
    @State private var showsPicker = false
    @State private var confirmsDiscard = false
    @State private var alert: SaveAlert?

    private enum SaveAlert: String, Identifiable {
        case failure, conflict
        var id: Self { self }
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
                rearrange: { order, groups in
                    edit {
                        draft.orderedIDs = order
                        draft.regroup(groups)
                    }
                },
                remove: remove,
                add: { showsPicker = true },
                undo: history.isEmpty ? nil : { undo() },
                notice: $notice,
                warning: pendingLossWarning
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
                ExercisePickerView(
                    mode: .add(existingExerciseIDs: existingExerciseIDs),
                    showsCancel: false,
                    onSelectAsSuperset: { append($0, asSuperset: true) },
                    onSelect: { append($0, asSuperset: false) }
                )
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .accessibilityIdentifier("CancelReorderExercisesButton")
                        .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing", role: .cancel) {}
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Text("Save").foregroundStyle(draft.hasChanges ? AppTheme.onBrandAccent : AppTheme.textTertiary)
                    }
                        .accessibilityHint(pendingLossWarning ?? "")
                        .buttonStyle(.glassProminent)
                        .tint(AppTheme.brandAccentFill)
                        // Nothing to save until something changes.
                        .disabled(!draft.hasChanges)
                        .accessibilityIdentifier("SaveReorderExercisesButton")
                }
            }
        }
        // A swipe down would discard edits without asking; Cancel asks instead.
        .interactiveDismissDisabled(draft.hasChanges)
        .alert(item: $alert) { alert in
            switch alert {
            case .failure:
                Alert(
                    title: Text("Couldn't Save Changes"),
                    message: Text("Your workout wasn't changed. Tap Save to retry, or Cancel to discard your edits."),
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
        .presentationDragIndicator(.visible)
    }

    /// Keeps the draft from before an edit, for Undo.
    private func edit(_ change: () -> Void) {
        history.append(draft)
        change()
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        notice = nil
        withAnimation(.snappy(duration: 0.3)) { draft = previous }
    }

    private func append(_ exercises: [Exercise], asSuperset: Bool) {
        edit {
            draft.append(exercises, asSuperset: asSuperset) {
                engine.initialSetKinds(for: $0,
                    ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                    sessions: sessions)
            }
        }
        showsPicker = false
    }

    private var existingExerciseIDs: Set<UUID> {
        let remaining = Set(draft.orderedIDs)
        return Set(session.sortedLoggedExercises.filter { remaining.contains($0.id) }.compactMap { $0.exercise?.id }
            + draft.additions.filter { remaining.contains($0.id) }.map { $0.exercise.id })
    }

    /// Removes at once. The notice names it, the warning keeps any entered sets it
    /// takes in view, and Undo lasts until Save.
    private func remove(_ id: UUID) {
        guard let removed = draft.exercises.first(where: { $0.id == id }) else { return }
        edit { draft.orderedIDs.removeAll { $0 == id } }
        let title = "Removed \(removed.name)"
        // Entered sets it takes show in the lasting warning above the bar. When that
        // warning names this exercise, a notice would only repeat it, so VoiceOver hears
        // the removal and the loss together instead.
        if removed.loggedSetCount > 0, let warning = pendingLossWarning {
            if draft.pendingSetLoss.exercises == 1 {
                notice = nil
                AccessibilityNotification.Announcement("\(title). \(warning)").post()
            } else {
                notice = ReorderNotice(title: title, spoken: warning)
            }
        } else {
            notice = ReorderNotice(title: title)
        }
    }

    /// Stays above the bar while saving would delete entered sets, from every removal
    /// still in the draft, so the loss is in view right up to Save.
    private var pendingLossWarning: String? {
        let loss = draft.pendingSetLoss
        guard loss.sets > 0 else { return nil }
        let sets = loss.sets == 1 ? "1 set" : "\(loss.sets) sets"
        // One source is named, so the warning still says what it means once the notice goes.
        let source = loss.exercises == 1
            ? draft.lossyRemovedExerciseNames.first.map { " from \($0)" } ?? ""
            : " from \(loss.exercises) exercises"
        return "Save deletes \(sets) with entered values\(source)"
    }

    private func cancel() {
        if draft.hasChanges { confirmsDiscard = true } else { dismiss() }
    }

    private func save() {
        if let failure = saveChanges() { alert = failure }
    }

    private func saveChanges() -> SaveAlert? {
        guard draft.baseline == WorkoutExerciseListSnapshot(session: session) else {
            reload()
            return .conflict
        }
        do {
            try engine.applyExerciseListChanges(
                in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline,
                additions: draft.additions, supersetGroupIDs: draft.supersetGroupIDs,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                context: modelContext
            )
            dismiss()
            return nil
        } catch ActiveWorkoutEngineError.invalidExerciseReorder {
            reload()
            return .conflict
        } catch {
            return .failure
        }
    }

    /// Starts over from the saved workout, whose history no longer applies.
    private func reload() {
        draft = WorkoutExerciseListDraft(session: session)
        history = []
        notice = nil
    }
}
