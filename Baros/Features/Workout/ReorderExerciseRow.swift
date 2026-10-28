import SwiftUI

/// A stock edit-mode List, so the system owns the minus, Delete, and reorder
/// grip along with their motion and accessibility.
struct ReorderExercisesList: View {
    let exercises: [WorkoutExerciseListSnapshot.ExerciseState]
    let reorder: ([UUID]) -> Void
    let remove: (Set<UUID>) -> Void
    var add: () -> Void = {}

    var body: some View {
        List {
            ForEach(exercises) { exercise in
                ReorderExerciseRow(exercise: exercise)
                    // Lifts only the card while dragging, not the whole row rectangle.
                    .contentShape(
                        .dragPreview,
                        RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                var ids = exercises.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                reorder(ids)
            }
            .onDelete { offsets in
                remove(Set(offsets.map { exercises[$0].id }))
            }
            Button(action: add) {
                Label("Add Exercises", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppTheme.brandAccentMuted, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("EditWorkoutAddExercisesButton")
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .moveDisabled(true)
            .deleteDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .environment(\.editMode, .constant(.active))
        .accessibilityIdentifier("ReorderExercisesList")
    }
}

struct ReorderExerciseRow: View {
    static let cornerRadius: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize = 13
    let exercise: WorkoutExerciseListSnapshot.ExerciseState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            // The progress shares the detail line so names keep the card's full width.
            if dynamicTypeSize.isAccessibilitySize {
                if let metadata = exercise.metadata { detail(metadata) }
                progress
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let metadata = exercise.metadata { detail(metadata).lineLimit(1) }
                    Spacer(minLength: 0)
                    progress
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(exercise.isNew ? AppTheme.brandAccentMuted : AppTheme.groupedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).stroke(exercise.isNew ? AppTheme.brandAccentForeground : AppTheme.subtleBorder)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.name)
        .accessibilityValue(exercise.accessibilityValue)
        .accessibilityIdentifier("ReorderExerciseRow-\(exercise.id.uuidString)")
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
    }

    private var progress: some View {
        detail(exercise.isNew ? "New · \(exercise.progressText)" : exercise.progressText)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }
}
