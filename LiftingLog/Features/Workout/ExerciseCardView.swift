import SwiftData
import SwiftUI

struct ExerciseCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    let loggedExercise: LoggedExercise
    let exerciseIndex: Int
    @Bindable var engine: ActiveWorkoutEngine
    @Binding var isCollapsed: Bool
    var focusedField: FocusState<WorkoutField?>.Binding
    let viewHistory: () -> Void
    @State private var showsRemoveConfirmation = false
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    var body: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .rotationEffect(.degrees(isCollapsed ? -90 : 0))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loggedExercise.exerciseSnapshotName)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                if let metadataDisplayText = loggedExercise.metadataDisplayText {
                                    Text(metadataDisplayText)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            let progress = Self.setProgress(for: loggedExercise)
                            Text("\(progress.completed)/\(progress.total)")
                                .font(.footnote.weight(.bold).monospacedDigit())
                                .foregroundStyle(progress.isComplete ? AppTheme.accentBright : AppTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    progress.isComplete ? AnyShapeStyle(AppTheme.accentMuted) : AnyShapeStyle(AppTheme.surfaceMuted),
                                    in: Capsule()
                                )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ExerciseHeader-\(exerciseIndex)")

                    Menu {
                        Button(action: viewHistory) {
                            Label("View History", systemImage: "clock.arrow.circlepath")
                        }
                        .accessibilityIdentifier("ExerciseHistoryButton-\(exerciseIndex)")

                        Button(role: .destructive) {
                            showsRemoveConfirmation = true
                        } label: {
                            Label("Remove Exercise", systemImage: "trash")
                        }
                        .accessibilityIdentifier("RemoveExerciseButton-\(exerciseIndex)")
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(loggedExercise.exerciseSnapshotName) options")
                    .accessibilityIdentifier("ExerciseMenuButton-\(exerciseIndex)")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .confirmationDialog(
                    "Remove \(loggedExercise.exerciseSnapshotName)?",
                    isPresented: $showsRemoveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove Exercise", role: .destructive) {
                        try? engine.removeLoggedExercise(loggedExercise, context: modelContext)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the exercise and its sets from this workout.")
                }

                if !isCollapsed {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Color.clear.frame(width: 18)
                            columnHeader(weightUnit.fieldLabel)
                            columnHeader("REPS")
                            columnHeader("RPE")
                            Color.clear.frame(width: 44)
                        }
                        .padding(.horizontal, 16)

                        VStack(spacing: 10) {
                            ForEach(Array(loggedExercise.sortedSets.enumerated()), id: \.element.id) { index, set in
                                SetRowView(
                                    set: set,
                                    exerciseIndex: exerciseIndex,
                                    index: index,
                                    engine: engine,
                                    focusedField: focusedField,
                                    weightUnit: weightUnit
                                )
                                    .padding(.horizontal, 16)
                            }
                        }

                        Button {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                                if let set = try? engine.addSet(to: loggedExercise, context: modelContext) {
                                    focusedField.wrappedValue = set.weight == nil ? .setWeight(set.id) : nil
                                }
                            }
                        } label: {
                            Label("Add Set", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accentBright)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("AddSetButton-\(exerciseIndex)")
                        .padding(.horizontal, 16)

                        TextField(
                            "Exercise notes...",
                            text: Binding(
                                get: { loggedExercise.notes },
                                set: { try? engine.updateExerciseNotes($0, loggedExercise: loggedExercise, context: modelContext) }
                            ),
                            axis: .vertical
                        )
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .focused(focusedField, equals: .exerciseNotes(loggedExercise.id))
                        .padding(14)
                        .frame(minHeight: 88, alignment: .topLeading)
                        .background(
                            AppTheme.fieldFill,
                            in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                                .strokeBorder(
                                    focusedField.wrappedValue == .exerciseNotes(loggedExercise.id)
                                        ? AppTheme.accentBright.opacity(0.7)
                                        : .clear,
                                    lineWidth: 1.5
                                )
                        )
                        .animation(.easeOut(duration: 0.15), value: focusedField.wrappedValue == .exerciseNotes(loggedExercise.id))
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("ExerciseNotesField-\(exerciseIndex)")
                        .id(WorkoutField.exerciseNotes(loggedExercise.id))

                        if let referenceNotes {
                            VStack(alignment: .leading, spacing: 6) {
                                Divider()
                                    .overlay(AppTheme.border)
                                    .padding(.bottom, 4)

                                Text("LAST TIME")
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.4)
                                    .foregroundStyle(AppTheme.textTertiary)
                                Text(referenceNotes)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    // Content stays put and fades while the clipped card edge
                    // swallows it; a .move transition here reads as jank.
                    .transition(.opacity)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var referenceNotes: String? {
        let trimmed = loggedExercise.referenceNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setProgress(for loggedExercise: LoggedExercise) -> (completed: Int, total: Int, isComplete: Bool) {
        let visibleSets = loggedExercise.sortedSets
        let completed = visibleSets.filter(\.isCompleted).count
        return (completed, visibleSets.count, completed == visibleSets.count && !visibleSets.isEmpty)
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity)
    }
}
