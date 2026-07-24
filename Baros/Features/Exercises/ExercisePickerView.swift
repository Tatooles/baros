import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    let onSelect: (Exercise) -> Void
    @State private var searchText = ""
    @State private var isCreatingExercise = false
    @State private var sortOrder: ExercisePickerSortOrder
    private let sortPreferenceStore: ExercisePickerSortPreferenceStore

    init(
        sortPreferenceStore: ExercisePickerSortPreferenceStore = ExercisePickerSortPreferenceStore(),
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.sortPreferenceStore = sortPreferenceStore
        self.onSelect = onSelect
        _sortOrder = State(initialValue: sortPreferenceStore.sortOrder)
    }

    private var rows: [ExercisePickerRowContent] {
        ExercisePickerContent.makeRows(
            exercises: exercises,
            sessions: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            query: searchText,
            sortOrder: sortOrder
        )
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
                ForEach(rows) { row in
                    Button {
                        onSelect(row.exercise)
                    } label: {
                        exerciseRow(row)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "ExercisePickerRow-\(row.exercise.name)-\(row.exercise.equipment.displayName)"
                    )
                    .listRowBackground(AppTheme.surface)
                    .listRowSeparatorTint(AppTheme.border)
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
                        .foregroundStyle(AppTheme.accentBright)
                    }
                    .accessibilityLabel("Sort: \(sortOrder.displayName)")
                    .accessibilityIdentifier("ExercisePickerSortMenu")
                }
                .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle("Add Exercise")
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
            ExerciseEditorView { exercise in
                onSelect(exercise)
                dismiss()
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
                .accessibilityIdentifier(
                    "ExercisePickerPerformance-\(row.exercise.name)-\(row.exercise.equipment.displayName)"
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
