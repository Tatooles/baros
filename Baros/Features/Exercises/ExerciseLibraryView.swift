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
    @State private var pendingRemoval: RemovalConfirmation?
    @State private var removalTitle = ""
    @State private var removalErrorTitle = "Couldn't Remove Exercise"

    private struct RemovalConfirmation {
        let exercise: Exercise
        let outcome: ExerciseRemovalOutcome
    }

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
        let noMatchesSuggestion = ExercisePickerCreationSuggestion.noMatches(
            query: searchText,
            hasMatches: !matches.isEmpty
        )
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
            if let noMatchesSuggestion {
                if showArchived {
                    Section {} header: {
                        Text("No Matching Exercises").textCase(nil)
                    }
                } else {
                    ExerciseNoMatchesSection(
                        suggestion: noMatchesSuggestion,
                        accessibilityIdentifier: "ExerciseLibraryCreateExerciseFromSearchButton"
                    ) { name in
                        creationName = name
                        isCreatingExercise = true
                    }
                }
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
                        Button(role: .destructive) { confirmRemoval(exercise) } label: {
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
        .alert(removalTitle, isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { confirmation in
            if confirmation.outcome == .archived {
                Button("Archive") { mutate(confirmation.exercise, restoring: false) }
            } else {
                Button("Delete", role: .destructive) { mutate(confirmation.exercise, restoring: false) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { confirmation in
            if confirmation.outcome == .archived {
                Text("It won't appear when you add exercises. Past workouts stay the same, and you can restore it from Archived.")
            } else {
                Text("You haven't used it in a workout, so no history is lost. This can't be undone.")
            }
        }
        .alert(
            removalErrorTitle,
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

    private func confirmRemoval(_ exercise: Exercise) {
        do {
            let outcome = try exercise.removalOutcome(context: modelContext)
            removalTitle = "\(outcome == .archived ? "Archive" : "Delete") \(exercise.name)?"
            pendingRemoval = RemovalConfirmation(exercise: exercise, outcome: outcome)
        } catch {
            removalErrorTitle = "Couldn't Remove Exercise"
            removalErrorMessage = error.localizedDescription
        }
    }

    private func mutate(_ exercise: Exercise, restoring: Bool) {
        pendingRemoval = nil
        removalErrorTitle = restoring ? "Couldn't Restore Exercise" : "Couldn't Remove Exercise"
        do {
            let service = ExerciseMutationService(syncScheduler: syncScheduler)
            let owner = currentOwnerCoordinator.localDataOwnerTokenIdentifier
            if restoring {
                try service.restoreExercise(exercise, ownerTokenIdentifier: owner, context: modelContext)
            } else {
                // History can arrive while the alert is open. Recheck before mutation;
                // archiveOrDelete also checks so new history is never deleted.
                let outcome = try exercise.removalOutcome(context: modelContext)
                removalErrorTitle = outcome == .archived ? "Couldn't Archive Exercise" : "Couldn't Delete Exercise"
                try service.removeExercise(exercise, ownerTokenIdentifier: owner, context: modelContext)
            }
            removalErrorMessage = nil
        } catch {
            removalErrorMessage = error.localizedDescription
        }
    }

}
