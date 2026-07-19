import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var isCreatingExercise = false
    @State private var removalErrorMessage: String?

    private var filteredExercises: [Exercise] {
        Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        )
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            ForEach(filteredExercises) { exercise in
                NavigationLink {
                    ExerciseEditorView(exercise: exercise)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.system(size: 17, weight: .semibold))
                        Text(exercise.metadataDisplayText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("ExerciseLibraryRow-\(exercise.name)-\(exercise.equipment.displayName)")
                .swipeActions {
                    Button(role: .destructive) {
                        do {
                            try ExerciseMutationService(syncScheduler: syncScheduler).removeExercise(exercise, context: modelContext)
                            removalErrorMessage = nil
                        } catch {
                            modelContext.rollback()
                            removalErrorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle("Exercises")
        .searchable(text: $searchText)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingExercise = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("CreateExerciseButton")
            }
        }
        .navigationDestination(isPresented: $isCreatingExercise) {
            ExerciseEditorView()
        }
        .alert(
            "Couldn't Remove Exercise",
            isPresented: Binding(
                get: { removalErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        removalErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalErrorMessage ?? "Try removing the exercise again.")
        }
    }
}
