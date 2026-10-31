import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var isCreatingExercise = false
    @State private var creationName = ""
    @State private var removalErrorMessage: String?

    private var filteredExercises: [Exercise] {
        let search = ExerciseSearch(query: searchText)
        return Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        )
        .compactMap { exercise in
            search.rank(for: exercise).map { (exercise: exercise, rank: $0) }
        }
        .sorted { $0.rank < $1.rank }
        .map(\.exercise)
    }

    var body: some View {
        let matches = filteredExercises
        List {
            if matches.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Matching Exercises")
                        .font(.headline)
                    Button {
                        creationName = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        isCreatingExercise = true
                    } label: {
                        Label("Create Exercise", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("ExerciseLibraryCreateExerciseFromSearchButton")
                }
                .padding(.vertical, 8)
            }
            ForEach(matches) { exercise in
                NavigationLink {
                    ExerciseEditorView(exercise: exercise)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.body.weight(.semibold))
                        Text(exercise.metadataDisplayText)
                            .font(.footnote.weight(.medium))
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
                    .tint(AppTheme.destructive)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("Exercises")
        .searchable(text: $searchText)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creationName = ""
                    isCreatingExercise = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("CreateExerciseButton")
            }
        }
        .navigationDestination(isPresented: $isCreatingExercise) {
            ExerciseEditorView(initialName: creationName)
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
