import BarosCore
import SwiftData
import SwiftUI

struct TemplateEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query private var exercises: [Exercise]
    let template: WorkoutTemplate?
    private let original: WorkoutTemplateDraft
    @State private var draft: WorkoutTemplateDraft
    @State private var showsPicker = false
    @State private var showsSaveError = false
    /// The exercises before each edit, latest last. Undo leaves the name as typed.
    @State private var history: [[WorkoutTemplateEntry]] = []
    @State private var notice: ReorderNotice?
    @State private var confirmsDiscard = false
    @FocusState private var isNameFocused: Bool

    init(template: WorkoutTemplate?) {
        self.init(template: template, draft: WorkoutTemplateDraft(template: template))
    }

    init(newDraft: WorkoutTemplateDraft) {
        self.init(template: nil, draft: newDraft)
    }

    private init(template: WorkoutTemplate?, draft: WorkoutTemplateDraft) {
        self.template = template
        original = draft
        _draft = State(initialValue: draft)
    }

    private var exercisesByID: [UUID: Exercise] {
        exercises.visibleByID(to: currentOwnerCoordinator.localDataOwnerTokenIdentifier)
    }

    var body: some View {
        NavigationStack {
            let items = TemplateExerciseItem.items(for: draft.entries, exercisesByID: exercisesByID)
            ReorderExercisesList(
                exercises: items,
                rearrange: { order, groups in
                    edit {
                        draft.reorder(order)
                        draft.regroup(groups)
                    }
                },
                remove: { id in
                    guard let removed = items.first(where: { $0.id == id }) else { return }
                    edit { draft.remove([id]) }
                    notice = ReorderNotice(title: "Removed \(removed.name)")
                },
                add: {
                    isNameFocused = false
                    showsPicker = true
                },
                undo: history.isEmpty ? nil : { undo() },
                notice: $notice
            ) {
                nameField
            }
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .navigationDestination(isPresented: $showsPicker) {
                ExercisePickerView(
                    mode: .add(existingExerciseIDs: draft.exerciseIDs),
                    showsCancel: false
                ) { exercises, asSuperset in
                    edit { draft.append(exercises, asSuperset: asSuperset) }
                    showsPicker = false
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .accessibilityIdentifier("CancelTemplateEditorButton")
                        .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing", role: .cancel) {}
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Text("Save").foregroundStyle(AppTheme.onBrandAccent)
                    }
                        .buttonStyle(.glassProminent)
                        .tint(AppTheme.brandAccentFill)
                        .disabled(!draft.canSave)
                        .accessibilityIdentifier("SaveTemplateButton")
                }
            }
        }
        .onAppear {
            if draft.name.isEmpty { isNameFocused = true }
        }
        .alert("Couldn't Save Template", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your changes are still here. Tap Save to try again.")
        }
        .interactiveDismissDisabled(draft != original)
        .presentationDragIndicator(.visible)
    }

    private var nameField: some View {
        TextField("Template Name", text: $draft.name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($isNameFocused)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
                    .fill(AppTheme.groupedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
                    .stroke(AppTheme.subtleBorder)
            )
            .accessibilityIdentifier("TemplateNameField")
    }

    private func edit(_ change: () -> Void) {
        history.append(draft.entries)
        change()
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        notice = nil
        withAnimation(.snappy(duration: 0.3)) { draft.entries = previous }
    }

    private func cancel() {
        if draft != original { confirmsDiscard = true } else { dismiss() }
    }

    private func save() {
        let service = WorkoutTemplateMutationService(syncScheduler: syncScheduler)
        let owner = currentOwnerCoordinator.localDataOwnerTokenIdentifier
        let entries = draft.refreshedEntries(exercisesByID: exercisesByID)
        do {
            if let template {
                try service.updateTemplate(
                    template, name: draft.trimmedName, entries: entries,
                    ownerTokenIdentifier: owner, context: modelContext
                )
            } else {
                try service.createTemplate(
                    name: draft.trimmedName, entries: entries,
                    ownerTokenIdentifier: owner, context: modelContext
                )
            }
            dismiss()
        } catch {
            modelContext.rollback()
            showsSaveError = true
        }
    }
}
