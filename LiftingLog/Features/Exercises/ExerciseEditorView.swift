import SwiftData
import SwiftUI

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let exercise: Exercise?
    let onSave: ((Exercise) -> Void)?
    @State private var name: String
    @State private var category: ExerciseCategory
    @State private var equipment: ExerciseEquipment
    @State private var primaryMuscle: String
    @State private var notes: String
    @State private var validationMessage: String?

    init(exercise: Exercise? = nil, onSave: ((Exercise) -> Void)? = nil) {
        self.exercise = exercise
        self.onSave = onSave
        _name = State(initialValue: exercise?.name ?? "")
        _category = State(initialValue: exercise?.category ?? .strength)
        _equipment = State(initialValue: exercise?.equipment ?? .barbell)
        _primaryMuscle = State(initialValue: exercise?.primaryMuscle ?? "")
        _notes = State(initialValue: exercise?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(ExerciseCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                Picker("Equipment", selection: $equipment) {
                    ForEach(ExerciseEquipment.allCases) { equipment in
                        Text(equipment.displayName).tag(equipment)
                    }
                }
                TextField("Primary muscle", text: $primaryMuscle)
                TextField("Notes", text: $notes, axis: .vertical)
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
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Exercise name is required."
            return
        }

        let duplicate = exercises.contains { existing in
            existing.id != exercise?.id
                && !existing.isArchived
                && existing.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
        guard !duplicate else {
            validationMessage = "An active exercise with that name already exists."
            return
        }

        let savedExercise: Exercise
        if let exercise {
            exercise.update(
                name: trimmedName,
                category: category,
                equipment: equipment,
                primaryMuscle: primaryMuscle,
                notes: notes
            )
            savedExercise = exercise
        } else {
            let exercise = Exercise(
                name: trimmedName,
                category: category,
                equipment: equipment,
                primaryMuscle: primaryMuscle,
                notes: notes
            )
            modelContext.insert(exercise)
            savedExercise = exercise
        }

        do {
            try modelContext.save()
            validationMessage = nil
            onSave?(savedExercise)
            dismiss()
        } catch {
            modelContext.rollback()
            validationMessage = "Couldn't save exercise. \(error.localizedDescription)"
        }
    }
}
