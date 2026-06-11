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
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
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

                    Button(action: viewHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View \(loggedExercise.exerciseSnapshotName) history")
                    .accessibilityIdentifier("ExerciseHistoryButton-\(exerciseIndex)")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .contextMenu {
                    Button(action: viewHistory) {
                        Label("View History", systemImage: "clock.arrow.circlepath")
                    }

                    Button(role: .destructive) {
                        try? engine.removeLoggedExercise(loggedExercise, context: modelContext)
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
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
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("AddSetButton-\(exerciseIndex)")
                        .padding(.horizontal, 16)
                        .padding(.top, 2)

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
                            AppTheme.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                        )
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
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity)
    }
}
