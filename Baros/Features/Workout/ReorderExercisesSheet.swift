import SwiftData
import SwiftUI

private struct ReorderExerciseDraft: Identifiable, Equatable {
    let id: UUID
    let name: String
    let metadata: String?
    let completedSets: Int
    let totalSets: Int

    init(loggedExercise: LoggedExercise) {
        let visibleSets = loggedExercise.sortedSets
        id = loggedExercise.id
        name = loggedExercise.exerciseSnapshotName
        metadata = loggedExercise.metadataDisplayText
        completedSets = visibleSets.filter(\.isCompleted).count
        totalSets = visibleSets.count
    }

    var progressText: String {
        "\(completedSets)/\(totalSets) sets"
    }

    var accessibilityValue: String {
        if let metadata {
            return "\(metadata), \(progressText)"
        }

        return progressText
    }
}

struct ReorderExercisesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @State private var draftExercises: [ReorderExerciseDraft] = []
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                ForEach(draftExercises) { exercise in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                            if let metadata = exercise.metadata {
                                Text(metadata)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 12)

                        Text(exercise.progressText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 68)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppTheme.border)
                    )
                    .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(exercise.name)
                    .accessibilityValue(exercise.accessibilityValue)
                    .accessibilityIdentifier("ReorderExerciseRow-\(exercise.id.uuidString)")
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 6))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove(perform: moveExercises)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.subtleBackground.ignoresSafeArea())
            .accessibilityIdentifier("ReorderExercisesList")
            .environment(\.editMode, $editMode)
            .navigationTitle("Reorder Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("CancelReorderExercisesButton")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveOrder()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(draftExercises.count < 2)
                    .accessibilityIdentifier("DoneReorderExercisesButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            draftExercises = session.sortedLoggedExercises.map(ReorderExerciseDraft.init)
        }
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        draftExercises.move(fromOffsets: source, toOffset: destination)
    }

    private func saveOrder() {
        do {
            try engine.reorderLoggedExercises(
                in: session,
                orderedIDs: draftExercises.map(\.id),
                context: modelContext
            )
            dismiss()
        } catch {
            engine.lastErrorMessage = error.localizedDescription
        }
    }
}
