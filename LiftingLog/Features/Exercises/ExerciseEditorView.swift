import SwiftData
import SwiftUI

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    @Environment(SyncOutboxTransaction.self) private var syncOutboxTransaction
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let exercise: Exercise?
    let onSave: ((Exercise) -> Void)?
    @State private var name: String
    @State private var category: ExerciseCategory
    @State private var equipment: ExerciseEquipment
    @State private var primaryMuscleGroup: ExerciseMuscleGroup
    @State private var notes: String
    @State private var validationMessage: String?

    init(exercise: Exercise? = nil, onSave: ((Exercise) -> Void)? = nil) {
        self.exercise = exercise
        self.onSave = onSave
        _name = State(initialValue: exercise?.name ?? "")
        _category = State(initialValue: exercise?.category ?? .strength)
        _equipment = State(initialValue: exercise?.equipment ?? .barbell)
        _primaryMuscleGroup = State(initialValue: exercise?.primaryMuscleGroup ?? .chest)
        _notes = State(initialValue: exercise?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("ExerciseNameField")
                Picker("Category", selection: $category) {
                    ForEach(ExerciseCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .accessibilityIdentifier("ExerciseCategoryPicker")
                Picker("Equipment", selection: $equipment) {
                    ForEach(ExerciseEquipment.allCases) { equipment in
                        Text(equipment.displayName).tag(equipment)
                    }
                }
                .accessibilityIdentifier("ExerciseEquipmentPicker")
                Picker("Primary Muscle", selection: $primaryMuscleGroup) {
                    ForEach(ExerciseMuscleGroup.allCases) { muscleGroup in
                        Text(muscleGroup.displayName).tag(muscleGroup)
                    }
                }
                .accessibilityIdentifier("ExercisePrimaryMuscleGroupPicker")
                TextField("Notes", text: $notes, axis: .vertical)
                    .accessibilityIdentifier("ExerciseNotesField")
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(AppTheme.accentBright)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle(exercise == nil ? "Create Exercise" : "Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .accessibilityIdentifier("ExerciseEditorSaveButton")
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Exercise name is required."
            return
        }

        let duplicate = Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).contains { existing in
            existing.id != exercise?.id
                && existing.hasSameActiveIdentity(name: trimmedName, equipment: equipment)
        }
        guard !duplicate else {
            validationMessage = "An active exercise with that name and equipment already exists."
            return
        }

        let savedExercise: Exercise
        do {
            let service = ExerciseMutationService(syncOutboxTransaction: syncOutboxTransaction)
            if let exercise {
                try service.updateExercise(
                    exercise,
                    name: trimmedName,
                    category: category,
                    equipment: equipment,
                    primaryMuscle: primaryMuscleGroup.displayName,
                    notes: notes,
                    context: modelContext
                )
                savedExercise = exercise
            } else {
                savedExercise = try service.createExercise(
                    name: trimmedName,
                    category: category,
                    equipment: equipment,
                    primaryMuscle: primaryMuscleGroup.displayName,
                    notes: notes,
                    context: modelContext
                )
            }
            validationMessage = nil
            onSave?(savedExercise)
            dismiss()
        } catch {
            modelContext.rollback()
            validationMessage = "Couldn't save exercise. \(error.localizedDescription)"
        }
    }
}
