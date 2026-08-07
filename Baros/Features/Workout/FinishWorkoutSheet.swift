import SwiftData
import SwiftUI

struct FinishWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    @Environment(SyncOutboxTransaction.self) private var syncOutboxTransaction
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @State private var showsDiscardConfirmation = false
    @State private var actionError: WorkoutActionError?
    @State private var titleDraft: String?
    @State private var isDiscardingWorkout = false
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
                // Finishing saves the title too; stop here when it failed so the
                // draft survives for a retry instead of being rolled back.
                guard commitWorkoutTitle() else { return }
                do {
                    try engine.finishWorkout(
                        session,
                        ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                        syncOutboxTransaction: syncOutboxTransaction,
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
                guard commitWorkoutTitle() else { return }
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
                commitWorkoutTitle()
            }
        }
        .onDisappear {
            guard !isDiscardingWorkout else { return }
            commitWorkoutTitle()
        }
        .alert("Discard Workout?", isPresented: $showsDiscardConfirmation) {
            Button("Discard", role: .destructive) {
                do {
                    isDiscardingWorkout = true
                    try engine.discardWorkout(session, context: modelContext)
                    actionError = nil
                    dismiss()
                } catch {
                    isDiscardingWorkout = false
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

    // Keystrokes stage in a view-local draft and commit in one save on focus
    // loss or when leaving the sheet; never per keystroke.
    private var workoutTitleBinding: Binding<String> {
        Binding(
            get: { titleDraft ?? session.title },
            set: { titleDraft = $0 }
        )
    }

    private var showsDefaultTitleHint: Bool {
        (titleDraft ?? session.title).trimmingCharacters(in: .whitespacesAndNewlines) == "Workout"
    }

    /// Returns `false` when the title could not be saved. The draft is kept on
    /// failure so the user's typing is still on screen and still retryable, and
    /// the real error is surfaced rather than the `unexpectedUnsavedDomainChanges`
    /// the finish transaction would otherwise report.
    @discardableResult
    private func commitWorkoutTitle() -> Bool {
        // The commit-then-clear-focus buttons also retrigger this through the
        // focus onChange; the guard makes the second pass (and untouched
        // dismissals) a no-op instead of a redundant save.
        guard let titleDraft else { return true }
        do {
            try engine.commitWorkoutTitle(titleDraft, session: session, context: modelContext)
        } catch {
            actionError = WorkoutActionError(
                title: "Couldn't Save Workout Name",
                message: error.localizedDescription
            )
            return false
        }
        self.titleDraft = nil
        return true
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
