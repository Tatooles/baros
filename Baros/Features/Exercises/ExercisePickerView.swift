import SwiftData
import SwiftUI

enum ExercisePickerMode {
    case add
    case swap(currentExerciseID: UUID?)

    var navigationTitle: String {
        switch self {
        case .add:
            return "Add Exercise"
        case .swap:
            return "Swap Exercise"
        }
    }

    var dismissesAfterCreatingExercise: Bool {
        switch self {
        case .add:
            return true
        case .swap:
            return false
        }
    }

    func isCurrent(_ exercise: Exercise) -> Bool {
        guard case let .swap(currentExerciseID) = self else { return false }
        return currentExerciseID == exercise.id
    }
}

struct ExercisePickerView: View {
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var sessions: [WorkoutSession]
    let mode: ExercisePickerMode
    let onSelect: (Exercise) -> Void
    private let sortPreferenceStore: ExercisePickerSortPreferenceStore

    init(
        mode: ExercisePickerMode = .add,
        sortPreferenceStore: ExercisePickerSortPreferenceStore = ExercisePickerSortPreferenceStore(),
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.mode = mode
        self.sortPreferenceStore = sortPreferenceStore
        self.onSelect = onSelect
    }

    var body: some View {
        ExercisePickerList(
            baseRows: ExercisePickerContent.makeBaseRows(
                exercises: exercises,
                sessions: sessions,
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
            ),
            mode: mode,
            sortPreferenceStore: sortPreferenceStore,
            onSelect: onSelect
        )
    }
}

private struct ExercisePickerList: View {
    @Environment(\.dismiss) private var dismiss
    let baseRows: [ExercisePickerRowContent]
    let mode: ExercisePickerMode
    let onSelect: (Exercise) -> Void
    @State private var searchText = ""
    @State private var isCreatingExercise = false
    @State private var creationName = ""
    @State private var sortOrder: ExercisePickerSortOrder
    private let sortPreferenceStore: ExercisePickerSortPreferenceStore

    init(
        baseRows: [ExercisePickerRowContent],
        mode: ExercisePickerMode,
        sortPreferenceStore: ExercisePickerSortPreferenceStore,
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.baseRows = baseRows
        self.mode = mode
        self.sortPreferenceStore = sortPreferenceStore
        self.onSelect = onSelect
        _sortOrder = State(initialValue: sortPreferenceStore.sortOrder)
    }

    private var rows: [ExercisePickerRowContent] {
        ExercisePickerContent.filterAndSort(
            rows: baseRows,
            query: searchText,
            sortOrder: sortOrder
        )
    }

    private var creationSuggestion: ExercisePickerCreationSuggestion? {
        guard case .add = mode else { return nil }
        return ExercisePickerContent.creationSuggestion(for: rows, query: searchText)
    }

    var body: some View {
        List {
            Section {
                Button {
                    creationName = ""
                    isCreatingExercise = true
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
                        onSelect(row.exercise)
                    } label: {
                        HStack(spacing: 12) {
                            exerciseRow(row)

                            if mode.isCurrent(row.exercise) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.brandAccentForeground)
                                    .accessibilityLabel("Current exercise")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(mode.isCurrent(row.exercise))
                    .accessibilityIdentifier(
                        "ExercisePickerRow-\(row.exercise.name)-\(row.exercise.equipment.displayName)"
                    )
                }

                if let creationSuggestion {
                    Button {
                        creationName = creationSuggestion.name
                        isCreatingExercise = true
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
        .contentMargins(.bottom, 24, for: .scrollContent)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle(mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
        .onChange(of: sortOrder) { _, newValue in
            sortPreferenceStore.sortOrder = newValue
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .navigationDestination(isPresented: $isCreatingExercise) {
            ExerciseEditorView(initialName: creationName) { exercise in
                onSelect(exercise)
                if mode.dismissesAfterCreatingExercise {
                    dismiss()
                }
            }
        }
    }

    private func exerciseRow(_ row: ExercisePickerRowContent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.exercise.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(row.exercise.metadataDisplayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(row.performanceSummaryText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
