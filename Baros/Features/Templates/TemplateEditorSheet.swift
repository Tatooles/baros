import SwiftData
import SwiftUI

/// The Edit Workout sheet with a name field. Nothing saves until Save.
struct TemplateEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query private var exercises: [Exercise]
    /// Nil for a new template.
    let template: WorkoutTemplate?
    @State private var draft: WorkoutTemplateDraft
    @State private var showsPicker = false
    @State private var showsSaveError = false
    @FocusState private var isNameFocused: Bool

    init(template: WorkoutTemplate?) {
        self.template = template
        _draft = State(initialValue: WorkoutTemplateDraft(template: template))
    }

    private var exercisesByID: [UUID: Exercise] {
        exercises.visibleByID(to: currentOwnerCoordinator.localDataOwnerTokenIdentifier)
    }

    var body: some View {
        NavigationStack {
            ReorderExercisesList(
                exercises: TemplateExerciseItem.items(for: draft.entries, exercisesByID: exercisesByID),
                reorder: { draft.reorder($0) },
                remove: { draft.remove($0) },
                add: {
                    isNameFocused = false
                    showsPicker = true
                }
            ) {
                nameField
            }
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .navigationDestination(isPresented: $showsPicker) {
                ExercisePickerView(mode: .add(existingExerciseIDs: draft.exerciseIDs), showsCancel: false) { exercises in
                    draft.append(exercises)
                    showsPicker = false
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("CancelTemplateEditorButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(!draft.canSave)
                        .accessibilityIdentifier("SaveTemplateButton")
                }
            }
        }
        .onAppear {
            if template == nil { isNameFocused = true }
        }
        .alert("Couldn't Save Template", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your changes are still here. Tap Save to try again.")
        }
        .interactiveDismissDisabled(draft != WorkoutTemplateDraft(template: template))
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
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 14, trailing: 20))
            .accessibilityIdentifier("TemplateNameField")
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
