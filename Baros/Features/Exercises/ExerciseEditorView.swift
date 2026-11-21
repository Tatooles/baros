import BarosCore
import SwiftData
import SwiftUI

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let exercise: Exercise?
    let onSave: ((Exercise) -> Void)?
    @State private var name: String
    @State private var category: ExerciseCategory
    @State private var equipment: ExerciseEquipment
    @State private var primaryMuscleGroup: ExerciseMuscleGroup
    @State private var trackingMethod: ExerciseTrackingMethod
    @State private var notes: String
    @State private var validationMessage: String?

    init(
        exercise: Exercise? = nil,
        initialName: String = "",
        onSave: ((Exercise) -> Void)? = nil
    ) {
        self.exercise = exercise
        self.onSave = onSave
        _name = State(initialValue: exercise?.name ?? initialName)
        _category = State(initialValue: exercise?.category ?? .strength)
        _equipment = State(initialValue: exercise?.equipment ?? .barbell)
        _primaryMuscleGroup = State(initialValue: exercise?.primaryMuscleGroup ?? .chest)
        _trackingMethod = State(initialValue: exercise?.trackingMethod ?? .reps)
        _notes = State(initialValue: exercise?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("ExerciseNameField")
                Picker("Equipment", selection: $equipment) {
                    ForEach(ExerciseEquipment.allCases) { equipment in
                        Text(equipment.displayName).tag(equipment)
                    }
                }
                .accessibilityIdentifier("ExerciseEquipmentPicker")
            } footer: {
                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(AppTheme.destructiveForeground)
                }
            }

            Section {
                Picker("Log Sets By", selection: $trackingMethod) {
                    ForEach(ExerciseTrackingMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ExerciseTrackingMethodPicker")
            } header: {
                Text("Log Sets By")
            } footer: {
                Text(trackingMethodFooter)
            }

            Section {
                Picker("Target Area", selection: $primaryMuscleGroup) {
                    ForEach(ExerciseMuscleGroup.pickerSections) { section in
                        Section(section.title) {
                            ForEach(section.groups) { muscleGroup in
                                Text(muscleGroup.displayName).tag(muscleGroup)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("ExercisePrimaryMuscleGroupPicker")
                MuscleFigureView(selection: primaryMuscleGroup)
                    .padding(.vertical, 12)
            }

            Section {
                TextField("Notes (Optional)", text: $notes, axis: .vertical)
                    .accessibilityIdentifier("ExerciseNotesField")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
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

    private var trackingMethodFooter: String {
        let summary = switch trackingMethod {
        case .reps: "Each set records reps, with optional weight."
        case .duration: "Each set records a time, like a plank or a carry, with optional weight."
        }
        guard let exercise, exercise.trackingMethod != trackingMethod else { return summary }
        return summary + " Workouts you’ve already logged keep how they were recorded."
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Exercise name is required."
            return
        }

        let duplicate = Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).contains { existing in
            existing.id != exercise?.id
                && existing.hasSameActiveIdentity(name: trimmedName, equipment: equipment)
        }
        guard !duplicate else {
            validationMessage = "You already have an exercise with this name and equipment."
            return
        }

        let savedExercise: Exercise
        do {
            let service = ExerciseMutationService(syncScheduler: syncScheduler)
            if let exercise {
                try service.updateExercise(
                    exercise,
                    name: trimmedName,
                    category: category,
                    equipment: equipment,
                    primaryMuscle: primaryMuscleGroup.displayName,
                    trackingMethod: trackingMethod,
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
                    trackingMethod: trackingMethod,
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
