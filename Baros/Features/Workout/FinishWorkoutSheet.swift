import SwiftData
import SwiftUI

struct FinishWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @State private var showsDiscardConfirmation = false
    @State private var actionError: WorkoutActionError?
    @State private var titleDraft: String?
    @State private var isDiscardingWorkout = false
    @State private var savesAsTemplate = false
    @FocusState private var focusedField: FinishWorkoutFocusedField?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    private var sheetContent: some View {
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

            // One aligned row of figures; the sheet already bounds them, so
            // they need no wells of their own. Accessibility sizes stack them
            // so long values keep their full width.
            metricsLayout {
                MetricSummaryColumn(title: "Duration", value: AppTheme.formatDuration(metrics.durationSeconds))
                metricDivider
                MetricSummaryColumn(title: "Sets Done", value: "\(metrics.completedSetCount)/\(metrics.totalSetCount)")
                metricDivider
                MetricSummaryColumn(
                    title: "Volume (\(weightUnit.fieldLabel.lowercased()))",
                    value: WorkoutFormatters.volume(canonicalPounds: metrics.completedVolume, unit: weightUnit)
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            if offersSaveAsTemplate {
                Toggle("Save as Template", isOn: $savesAsTemplate)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .tint(AppTheme.brandAccentFill)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("SaveAsTemplateToggle")
            }

            Button {
                focusedField = nil
                commitWorkoutTitle()
                do {
                    try engine.finishWorkout(
                        session,
                        ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                        syncScheduler: syncScheduler,
                        context: modelContext
                    )
                    actionError = nil
                    if offersSaveAsTemplate, savesAsTemplate { saveTemplate() }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } catch {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    actionError = WorkoutActionError(title: "Couldn't Save Workout", message: error.localizedDescription)
                }
            } label: {
                Text("Save Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(AppTheme.brandAccentFill)
            .accessibilityIdentifier("SaveWorkoutButton")

            Button {
                commitWorkoutTitle()
                dismiss()
            } label: {
                // A neutral fill keeps the secondary action's full-width
                // shape visible on the sheet in both appearances.
                Text("Keep Going")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppTheme.fieldSurface, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("KeepGoingButton")

            Button(role: .destructive) {
                showsDiscardConfirmation = true
            } label: {
                Text("Discard Workout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.destructiveForeground)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    private var metricsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))
    }

    @ViewBuilder
    private var metricDivider: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Rectangle()
                .fill(AppTheme.subtleBorder)
                .frame(height: 1)
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
        } else {
            Rectangle()
                .fill(AppTheme.subtleBorder)
                .frame(width: 1)
                .padding(.vertical, 6)
                .accessibilityHidden(true)
        }
    }

    var body: some View {
        // Accessibility text sizes outgrow the fixed height.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { sheetContent }
            } else {
                sheetContent
            }
        }
        .presentationDetents([dynamicTypeSize.isAccessibilitySize ? .large : .height(offersSaveAsTemplate ? 572 : 500)])
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

    /// Hidden for a workout started from a template, so finishing "Upper
    /// Day" can't make a second "Upper Day".
    private var offersSaveAsTemplate: Bool {
        session.source != .template && session.visibleExerciseCount > 0
    }

    /// Runs after the workout is saved, which stands even if this fails.
    private func saveTemplate() {
        do {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--uitest-in-memory-store"), arguments.contains("--uitest-fail-template-save") {
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            try WorkoutTemplateMutationService(syncScheduler: syncScheduler).createTemplate(
                name: session.title,
                entries: WorkoutTemplateEntry.entries(copying: session),
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                context: modelContext
            )
        } catch {
            modelContext.rollback()
            engine.failedToSaveTemplate = true
        }
    }

    private var showsDefaultTitleHint: Bool {
        (titleDraft ?? session.title).trimmingCharacters(in: .whitespacesAndNewlines) == WorkoutSession.defaultTitle
    }

    private func commitWorkoutTitle() {
        // The commit-then-clear-focus buttons also retrigger this through the
        // focus onChange; the guard makes the second pass (and untouched
        // dismissals) a no-op instead of a redundant save.
        guard let titleDraft else { return }
        try? engine.commitWorkoutTitle(titleDraft, session: session, context: modelContext)
        self.titleDraft = nil
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
