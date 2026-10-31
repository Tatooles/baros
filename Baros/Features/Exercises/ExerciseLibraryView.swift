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

    @State private var showArchived = false
    @State private var pendingRemoval: Exercise?

    private var filteredExercises: [Exercise] {
        let search = ExerciseSearch(query: searchText)
        return exercises.filter {
            !$0.isDeleted && $0.isArchived == showArchived
                && $0.isVisible(to: currentOwnerCoordinator.localDataOwnerTokenIdentifier)
        }
        .compactMap { exercise in
            search.rank(for: exercise).map { (exercise: exercise, rank: $0) }
        }
        .sorted { $0.rank < $1.rank }
        .map(\.exercise)
    }

    var body: some View {
        let matches = filteredExercises
        List {
            Picker("Library", selection: $showArchived) {
                Text("Active").tag(false)
                Text("Archived").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ExerciseLibraryFilter")
            if matches.isEmpty && showArchived && searchText.isEmpty {
                Text("No Archived Exercises").foregroundStyle(.secondary)
            }
            if matches.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Matching Exercises")
                        .font(.headline)
                    if !showArchived {
                        Button {
                            creationName = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            isCreatingExercise = true
                        } label: {
                            Label("Create Exercise", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("ExerciseLibraryCreateExerciseFromSearchButton")
                    }
                }
                .padding(.vertical, 8)
            }
            ForEach(matches) { exercise in
                if showArchived {
                    VStack(alignment: .leading, spacing: 8) {
                        exerciseLabel(exercise)
                        Button("Restore") { mutate(exercise, restoring: true) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Restore \(exercise.name)")
                    }
                } else {
                    NavigationLink {
                        ExerciseEditorView(exercise: exercise)
                    } label: {
                        exerciseLabel(exercise)
                    }
                    .accessibilityIdentifier("ExerciseLibraryRow-\(exercise.name)-\(exercise.equipment.displayName)")
                    .swipeActions(allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingRemoval = exercise } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .tint(AppTheme.destructive)
                    }
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
        .confirmationDialog("Remove Exercise?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let exercise = pendingRemoval { mutate(exercise, restoring: false) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Remove this exercise from the workout picker? Past workouts stay unchanged. Seeded exercises and exercises used in workouts can be restored from Archived. Unused custom exercises are permanently removed.")
        }
        .alert(
            "Couldn't Change Exercise",
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
            Text(removalErrorMessage ?? "Try the action again.")
        }
    }
    private func exerciseLabel(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name).font(.body.weight(.semibold))
            Text(exercise.metadataDisplayText)
                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func mutate(_ exercise: Exercise, restoring: Bool) {
        do {
            let service = ExerciseMutationService(syncScheduler: syncScheduler)
            let owner = currentOwnerCoordinator.localDataOwnerTokenIdentifier
            if restoring {
                try service.restoreExercise(exercise, ownerTokenIdentifier: owner, context: modelContext)
            } else {
                try service.removeExercise(exercise, ownerTokenIdentifier: owner, context: modelContext)
            }
            removalErrorMessage = nil
        } catch {
            removalErrorMessage = error.localizedDescription
        }
    }

}
