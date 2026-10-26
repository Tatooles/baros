import SwiftData
import SwiftUI

enum ExercisePickerMode {
    case add(existingExerciseIDs: Set<UUID>)
    case swap(currentExerciseID: UUID?)

    var navigationTitle: String {
        switch self {
        case .add:
            return "Add Exercises"
        case .swap:
            return "Swap Exercise"
        }
    }

    func isCurrent(_ exercise: Exercise) -> Bool {
        guard case let .swap(currentExerciseID) = self else { return false }
        return currentExerciseID == exercise.id
    }
}

struct ExercisePickerView: View {
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var sessions: [WorkoutSession]
    let mode: ExercisePickerMode
    let onSelect: ([Exercise]) -> Void
    private let sortPreferenceStore: ExercisePickerSortPreferenceStore

    init(
        mode: ExercisePickerMode,
        sortPreferenceStore: ExercisePickerSortPreferenceStore = ExercisePickerSortPreferenceStore(),
        onSelect: @escaping ([Exercise]) -> Void
    ) {
        self.mode = mode
        self.sortPreferenceStore = sortPreferenceStore
        self.onSelect = onSelect
    }

    var body: some View {
        SearchableExercisePicker(
            baseRows: ExercisePickerContent.makeBaseRows(
                exercises: exercises,
                sessions: sessions,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
            ),
            mode: mode,
            sortPreferenceStore: sortPreferenceStore,
            onSelect: onSelect
        )
    }
}

// Search actions must be read below the searchable modifier.
private struct SearchableExercisePicker: View {
    let baseRows: [ExercisePickerRowContent]
    let mode: ExercisePickerMode
    let sortPreferenceStore: ExercisePickerSortPreferenceStore
    let onSelect: ([Exercise]) -> Void
    @State private var searchText = ""

    var body: some View {
        ExercisePickerList(
            baseRows: baseRows,
            mode: mode,
            sortPreferenceStore: sortPreferenceStore,
            searchText: $searchText,
            onSelect: onSelect
        )
        .searchable(
            text: $searchText,
            placement: mode.isAddExercise ? .navigationBarDrawer(displayMode: .always) : .automatic,
            prompt: "Search exercises"
        )
    }
}

private struct ExercisePickerList: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.isSearching) private var isSearching
    let baseRows: [ExercisePickerRowContent]
    let mode: ExercisePickerMode
    let onSelect: ([Exercise]) -> Void
    @State private var selectedExerciseIDs: [UUID] = []
    @Binding private var searchText: String
    @State private var creationRequest: ExerciseCreationRequest?
    @State private var createdSwapExercise: Exercise?
    @State private var sortOrder: ExercisePickerSortOrder
    private let sortPreferenceStore: ExercisePickerSortPreferenceStore

    init(
        baseRows: [ExercisePickerRowContent],
        mode: ExercisePickerMode,
        sortPreferenceStore: ExercisePickerSortPreferenceStore,
        searchText: Binding<String>,
        onSelect: @escaping ([Exercise]) -> Void
    ) {
        self.baseRows = baseRows
        self.mode = mode
        self.sortPreferenceStore = sortPreferenceStore
        _searchText = searchText
        self.onSelect = onSelect
        _sortOrder = State(initialValue: sortPreferenceStore.sortOrder)
    }

    private var selectedExercises: [Exercise] {
        selectedExerciseIDs.compactMap { id in
            baseRows.first { $0.id == id && !mode.isAlreadyAdded($0.exercise) }?.exercise
        }
    }

    private var addButtonTitle: String {
        switch selectedExercises.count {
        case 0: "Add Exercises"
        case 1: "Add 1 Exercise"
        case let count: "Add \(count) Exercises"
        }
    }

    private var rows: [ExercisePickerRowContent] {
        ExercisePickerContent.filterAndSort(
            rows: baseRows,
            query: searchText,
            sortOrder: sortOrder
        )
    }

    private var creationSuggestion: ExercisePickerCreationSuggestion? {
        return ExercisePickerContent.creationSuggestion(for: rows, query: searchText)
    }

    var body: some View {
        List {
            Section {
                Button {
                    beginCreation(name: "")
                } label: {
                    Label("Create Exercise", systemImage: "plus.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                }
                .accessibilityIdentifier("ExercisePickerCreateExerciseButton")
            }

            Section {
                ForEach(rows) { row in
                    Button {
                        if mode.isAddExercise {
                            toggleSelection(row.exercise)
                        } else {
                            onSelect([row.exercise])
                        }
                    } label: {
                        HStack(spacing: 12) {
                            exerciseRow(row)

                            if mode.isAddExercise {
                                Image(systemName: selectionSymbol(for: row.exercise))
                                    .font(.system(size: 24))
                                    .foregroundStyle(
                                        isSelected(row.exercise)
                                            ? AppTheme.brandAccentForeground
                                            : AppTheme.textTertiary
                                    )
                                    .accessibilityHidden(true)
                            } else if mode.isCurrent(row.exercise) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.brandAccentForeground)
                                    .accessibilityLabel("Current exercise")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(mode.isCurrent(row.exercise) || mode.isAlreadyAdded(row.exercise))
                    .accessibilityAddTraits(isSelected(row.exercise) ? .isSelected : [])
                    .accessibilityIdentifier(
                        "ExercisePickerRow-\(row.exercise.name)-\(row.exercise.equipment.displayName)"
                    )
                }

                if let creationSuggestion {
                    Button {
                        beginCreation(name: creationSuggestion.name)
                    } label: {
                        Label(creationSuggestion.title, systemImage: "plus.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.brandAccentForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ExercisePickerCreateExerciseFromSearchButton")
                    .accessibilityLabel(creationSuggestion.title)
                }
            } header: {
                HStack {
                    Text("Exercises")

                    Spacer()

                    Menu {
                        Picker("Sort exercises", selection: $sortOrder) {
                            ForEach(ExercisePickerSortOrder.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    } label: {
                        Label(
                            "Sort: \(sortOrder.displayName)",
                            systemImage: "arrow.up.arrow.down"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                    }
                    .accessibilityLabel("Sort: \(sortOrder.displayName)")
                    .accessibilityIdentifier("ExercisePickerSortMenu")
                }
                .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, mode.isAddExercise ? 8 : nil, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle(mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isSearching) { _, isSearching in
            guard mode.isAddExercise else { return }
            UIHangContextObservability.shared.exerciseSearchEditingChanged(isEditing: isSearching)
        }
        .onDisappear {
            guard mode.isAddExercise else { return }
            UIHangContextObservability.shared.exerciseSearchEditingChanged(isEditing: false)
        }
        .onChange(of: sortOrder) { _, newValue in
            sortPreferenceStore.sortOrder = newValue
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if mode.isAddExercise {
                Button {
                    onSelect(selectedExercises)
                } label: {
                    Text(addButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(AppTheme.brandAccentFill)
                .disabled(selectedExercises.isEmpty)
                .accessibilityIdentifier("ExercisePickerAddSelectedButton")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .toolbar {
            if mode.isAddExercise {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .accessibilityIdentifier("ExercisePickerCancelButton")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $creationRequest, onDismiss: completeCreatedSwap) { request in
            ExerciseCreationSheet(initialName: request.name) { exercise in
                if mode.isAddExercise {
                    selectedExerciseIDs.append(exercise.id)
                } else {
                    createdSwapExercise = exercise
                }
            }
        }
    }

    private func beginCreation(name: String) {
        let request = ExerciseCreationRequest(name: name)
        dismissSearch()
        creationRequest = request
    }

    private func completeCreatedSwap() {
        // Present confirmation after the creation sheet has finished dismissing.
        guard let exercise = createdSwapExercise else { return }
        createdSwapExercise = nil
        onSelect([exercise])
    }

    private func isSelected(_ exercise: Exercise) -> Bool {
        selectedExerciseIDs.contains(exercise.id) && !mode.isAlreadyAdded(exercise)
    }

    private func toggleSelection(_ exercise: Exercise) {
        if isSelected(exercise) {
            selectedExerciseIDs.removeAll { $0 == exercise.id }
        } else {
            selectedExerciseIDs.append(exercise.id)
        }
    }

    private func selectionSymbol(for exercise: Exercise) -> String {
        if mode.isAlreadyAdded(exercise) { return "checkmark" }
        return isSelected(exercise) ? "checkmark.circle.fill" : "circle"
    }

    private func exerciseRow(_ row: ExercisePickerRowContent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.exercise.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(row.exercise.metadataDisplayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(mode.isAlreadyAdded(row.exercise) ? "Already added" : row.performanceSummaryText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ExerciseCreationRequest: Identifiable {
    let id = UUID()
    let name: String
}

private struct ExerciseCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialName: String
    let onSave: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            ExerciseEditorView(initialName: initialName, onSave: onSave)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                            .accessibilityIdentifier("ExerciseCreationCancelButton")
                    }
                }
        }
        .presentationDetents([.large])
    }
}

private extension ExercisePickerMode {
    func isAlreadyAdded(_ exercise: Exercise) -> Bool {
        guard case let .add(existingExerciseIDs) = self else { return false }
        return existingExerciseIDs.contains(exercise.id)
    }

    var isAddExercise: Bool {
        if case .add = self { return true }
        return false
    }
}
