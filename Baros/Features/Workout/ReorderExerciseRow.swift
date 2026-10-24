import SwiftUI

/// The native List still owns dragging/reorder handles. Only the two-step
/// removal affordance is custom, keeping its wording scoped to this workout.
struct ReorderExerciseRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize = 13
    let exercise: WorkoutExerciseListSnapshot.ExerciseState
    let isRevealed: Bool
    let reveal: () -> Void
    let collapse: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if !isRevealed {
                Button(action: reveal) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppTheme.destructive)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(exercise.name)")
                .accessibilityHint("Reveals the Remove button. Changes are saved when you tap Done.")
                .accessibilityIdentifier("RevealRemoveExercise-\(exercise.id.uuidString)")
            }

            card
                .onTapGesture(perform: collapse)
                .accessibilityAction(named: "Remove \(exercise.name)", reveal)

            if isRevealed {
                Button(role: .destructive, action: remove) {
                    Text("Remove")
                        .font(.system(size: detailSize, weight: .semibold))
                        .foregroundStyle(AppTheme.onDestructive)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 60)
                        .background(AppTheme.destructiveFill, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(exercise.name) from this workout")
                .accessibilityIdentifier("ConfirmRemoveExercise-\(exercise.id.uuidString)")
            }
        }
    }

    private var card: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if let metadata = exercise.metadata {
                    Text(metadata)
                        .font(.system(size: detailSize, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                if dynamicTypeSize.isAccessibilitySize || isRevealed { progress }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize && !isRevealed { progress }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(AppTheme.groupedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.subtleBorder)
        )
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.name)
        .accessibilityValue(exercise.accessibilityValue)
        .accessibilityIdentifier("ReorderExerciseRow-\(exercise.id.uuidString)")
    }

    private var progress: some View {
        Text(exercise.progressText)
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }
}
