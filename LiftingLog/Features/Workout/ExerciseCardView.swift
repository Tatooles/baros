import SwiftData
import SwiftUI

struct ExerciseCardView: View {
    @Environment(\.modelContext) private var modelContext
    let loggedExercise: LoggedExercise
    let exerciseIndex: Int
    @Bindable var engine: ActiveWorkoutEngine
    @Binding var isCollapsed: Bool
    var focusedField: FocusState<WorkoutField?>.Binding
    let viewHistory: () -> Void
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(from: settingsRecords).first?.weightUnit ?? .pounds
    }

    var body: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .rotationEffect(.degrees(isCollapsed ? -90 : 0))

                            Text(loggedExercise.exerciseSnapshotName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Spacer()

                            let progress = Self.setProgress(for: loggedExercise)
                            Text("\(progress.completed)/\(progress.total)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(progress.isComplete ? AppTheme.accentBright : AppTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.surfaceMuted)
                                .clipShape(Capsule())
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ExerciseHeader-\(exerciseIndex)")

                    Button(action: viewHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View \(loggedExercise.exerciseSnapshotName) history")
                    .accessibilityIdentifier("ExerciseHistoryButton-\(exerciseIndex)")

                    Button(role: .destructive) {
                        try? engine.removeLoggedExercise(loggedExercise, context: modelContext)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                if !isCollapsed {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Color.clear.frame(width: 18)
                            columnHeader(weightUnit.fieldLabel)
                            columnHeader("REPS")
                            columnHeader("RPE")
                            Color.clear.frame(width: 54)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(AppTheme.border)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }

                        VStack(spacing: 12) {
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
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppTheme.accentBright)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(style: StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                                        .foregroundStyle(AppTheme.borderStrong)
                                )
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
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textPrimary)
                        .focused(focusedField, equals: .exerciseNotes(loggedExercise.id))
                        .padding(14)
                        .frame(minHeight: 92, alignment: .topLeading)
                        .background(AppTheme.surfaceMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(AppTheme.border)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("ExerciseNotesField-\(exerciseIndex)")
                        .id(WorkoutField.exerciseNotes(loggedExercise.id))

                        if let referenceNotes {
                            VStack(alignment: .leading, spacing: 6) {
                                Divider()
                                    .overlay(AppTheme.border)
                                    .padding(.bottom, 4)

                                Text("LAST TIME")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.4)
                                    .foregroundStyle(AppTheme.textTertiary)
                                Text(referenceNotes)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity)
    }
}
