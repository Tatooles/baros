import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    let onSelect: (Exercise) -> Void
    @State private var searchText = ""
    @State private var isCreatingExercise = false

    private var filteredExercises: [Exercise] {
        Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        )
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accentBright)
                }
                .listRowBackground(AppTheme.surface)
                .listRowSeparatorTint(AppTheme.border)
            }

            Section {
                ForEach(filteredExercises) { exercise in
                    Button {
                        onSelect(exercise)
                    } label: {
                        exerciseRow(exercise)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ExercisePickerRow-\(exercise.name)-\(exercise.equipment.displayName)")
                    .listRowBackground(AppTheme.surface)
                    .listRowSeparatorTint(AppTheme.border)
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
                .foregroundStyle(AppTheme.textPrimary)
            Text(exercise.metadataDisplayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
