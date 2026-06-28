import SwiftData
import SwiftUI

struct FinishWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @State private var showsDiscardConfirmation = false
    @State private var actionError: WorkoutActionError?
    @FocusState private var focusedField: FinishWorkoutFocusedField?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Finish Workout?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Review your session summary")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 6) {
                LabeledWorkoutTitleField(
                    label: "WORKOUT NAME",
                    placeholder: "Workout Name",
                    text: workoutTitleBinding,
                    focusTarget: .title,
                    focusedField: $focusedField,
                    accessibilityIdentifier: "FinishWorkoutTitleField",
                    labelIdentifier: "FinishWorkoutTitleLabel",
                    editAffordanceIdentifier: "FinishWorkoutTitleEditAffordance",
                    titleFont: .title3.weight(.bold)
                )

                if showsDefaultTitleHint {
                    Text("Name it now so it is easier to find in history.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .accessibilityIdentifier("FinishWorkoutTitleDefaultHint")
                }
            }

            HStack(spacing: 10) {
                MetricSummaryCard(title: "Duration", value: AppTheme.formatDuration(metrics.durationSeconds))
                MetricSummaryCard(title: "Sets Done", value: "\(metrics.completedSetCount)/\(metrics.totalSetCount)")
                MetricSummaryCard(
                    title: "Volume (\(weightUnit.fieldLabel))",
                    value: WorkoutFormatters.volume(canonicalPounds: metrics.completedVolume, unit: weightUnit)
                )
            }

            Button {
                focusedField = nil
                do {
                    try engine.finishWorkout(
                        session,
                        ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                        syncScheduler: syncScheduler,
                        context: modelContext
                    )
                    actionError = nil
                    dismiss()
                } catch {
                    actionError = WorkoutActionError(title: "Couldn't Save Workout", message: error.localizedDescription)
                }
            } label: {
                Text("Save Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(AppTheme.accentBright)
            .accessibilityIdentifier("SaveWorkoutButton")

            Button("Keep Going") {
                finalizeWorkoutTitle()
                dismiss()
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .accessibilityIdentifier("KeepGoingButton")

            Button(role: .destructive) {
                showsDiscardConfirmation = true
            } label: {
                Text("Discard Workout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentBright)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(500)])
        .presentationCornerRadius(36)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .accessibilityIdentifier("DismissKeyboardButton")
            }
        }
        .onChange(of: focusedField) { previousField, newField in
            if previousField == .title, newField != .title {
                finalizeWorkoutTitle()
            }
        }
        .alert("Discard Workout?", isPresented: $showsDiscardConfirmation) {
            Button("Discard", role: .destructive) {
                do {
                    try engine.discardWorkout(session, context: modelContext)
                    actionError = nil
                    dismiss()
                } catch {
                    actionError = WorkoutActionError(title: "Couldn't Discard Workout", message: error.localizedDescription)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will hide the active workout from history.")
        }
        .alert(item: $actionError) { actionError in
            Alert(
                title: Text(actionError.title),
                message: Text(actionError.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
    }

    private var workoutTitleBinding: Binding<String> {
        Binding(
            get: { session.title },
            set: { newValue in
                try? engine.updateWorkoutTitle(newValue, session: session, context: modelContext)
            }
        )
    }

    private var showsDefaultTitleHint: Bool {
        session.title.trimmingCharacters(in: .whitespacesAndNewlines) == "Workout"
    }

    private func finalizeWorkoutTitle() {
        try? engine.finalizeWorkoutTitle(session, context: modelContext)
    }

    private struct WorkoutActionError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
}

private enum FinishWorkoutFocusedField: Hashable {
    case title
}
