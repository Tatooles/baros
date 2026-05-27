import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    let onSelect: (Exercise) -> Void
    @State private var searchText = ""
    @State private var isCreatingExercise = false

    private var filteredExercises: [Exercise] {
        Exercise.visibleActiveExercises(from: exercises)
            .filter { exercise in
                searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)
            }
    }

    var body: some View {
        List {
            Section {
                Button {
                    isCreatingExercise = true
                } label: {
                    Label("Create Exercise", systemImage: "plus.circle")
                }
            }

            Section {
                ForEach(filteredExercises) { exercise in
                    Button {
                        onSelect(exercise)
                    } label: {
                        exerciseRow(exercise)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle("Add Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .navigationDestination(isPresented: $isCreatingExercise) {
            ExerciseEditorView { exercise in
                onSelect(exercise)
                dismiss()
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.system(size: 17, weight: .semibold))
            Text("\(exercise.category.displayName) • \(exercise.equipment.displayName) • \(exercise.primaryMuscle)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
