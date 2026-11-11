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
    @State private var templateAction = FinishTemplateAction.none
    @FocusState private var focusedField: FinishWorkoutFocusedField?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]
    @Query private var templates: [WorkoutTemplate]

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

            templateControl

            Button {
                focusedField = nil
                commitWorkoutTitle()
                // Read before finishing; the save refreshes the queries.
                let templateOffer = templateOffer
                do {
                    try engine.finishWorkout(
                        session,
                        ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                        syncScheduler: syncScheduler,
                        context: modelContext
                    )
                    actionError = nil
                    if templateOffer != .none, templateAction != .none { saveTemplate(templateOffer) }
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
        .presentationDetents([dynamicTypeSize.isAccessibilitySize ? .large : .height(templateOffer == .none ? 500 : 572)])
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
        // Sync can delete the source template while the sheet is open; a
        // choice made for the old control must not carry over.
        .onChange(of: templateOffer) { templateAction = .none }
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

    private var templateOffer: FinishTemplateOffer {
        FinishTemplateOffer(
            session: session,
            templates: templates,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        )
    }

    @ViewBuilder
    private var templateControl: some View {
        switch templateOffer {
        case .none:
            EmptyView()
        case .saveAsNew:
            Toggle("Save as Template", isOn: Binding(
                get: { templateAction == .saveAsNew },
                set: { templateAction = $0 ? .saveAsNew : .none }
            ))
            .tint(AppTheme.brandAccentFill)
            .modifier(TemplateRowStyle())
            .accessibilityIdentifier("SaveAsTemplateToggle")
        case .updateOrSaveAsNew(let template):
            HStack(spacing: 12) {
                Text("Template")
                    .layoutPriority(1)
                Spacer(minLength: 8)
                // A Menu around the Picker keeps the choice on one line;
                // a menu-style Picker wraps long template names.
                Menu {
                    Picker("Template", selection: $templateAction) {
                        ForEach(FinishTemplateAction.allCases, id: \.self) { action in
                            Text(action.title(templateName: template.name)).tag(action)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(templateAction.title(templateName: template.name))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(templateAction == .none ? AppTheme.textSecondary : AppTheme.brandAccentFill)
                }
                .accessibilityLabel("Template")
                .accessibilityValue(templateAction.title(templateName: template.name))
                .accessibilityIdentifier("FinishTemplatePicker")
            }
            .modifier(TemplateRowStyle())
        }
    }

    /// Runs after the workout is saved, which stands even if this fails.
    private func saveTemplate(_ offer: FinishTemplateOffer) {
        do {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--uitest-in-memory-store"), arguments.contains("--uitest-fail-template-save") {
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            let service = WorkoutTemplateMutationService(syncScheduler: syncScheduler)
            let entries = WorkoutTemplateEntry.entries(copying: session)
            let owner = currentOwnerCoordinator.localDataOwnerTokenIdentifier
            if templateAction == .update, case .updateOrSaveAsNew(let template) = offer {
                try service.updateTemplate(
                    template, name: template.name, entries: entries,
                    ownerTokenIdentifier: owner, context: modelContext
                )
            } else {
                try service.createTemplate(
                    name: session.title, entries: entries,
                    ownerTokenIdentifier: owner, context: modelContext
                )
            }
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

private enum FinishTemplateAction: Hashable, CaseIterable {
    case none
    case update
    case saveAsNew

    func title(templateName: String) -> String {
        switch self {
        case .none: "Don't Save"
        case .update: "Update \u{201C}\(templateName)\u{201D}"
        case .saveAsNew: "Save as New Template"
        }
    }
}

private struct TemplateRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
    }
}
