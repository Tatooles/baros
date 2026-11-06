import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage(RPEPreference.storageKey) private var rpeEnabled = false
    @Environment(\.modelContext) private var modelContext
    @Environment(AppAppearancePreferenceStore.self) private var appAppearanceStore
    @Environment(RestTimerCoordinator.self) private var restTimer
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    let settings: UserSettings
    @State private var alert: SettingsAlert?
    @State private var copyFeedbackResetTask: Task<Void, Never>?
    @State private var copyFeedbackState = CopyAppInfoFeedbackState.idle
    @State private var sheetPresentation: SettingsSheetPresentation?

    var body: some View {
        Form {
            SettingsAccountSection()

            Section("Workouts") {
                NavigationLink(value: SettingsRoute.exerciseLibrary) {
                    Label("Exercise Library", systemImage: "dumbbell")
                }
                .accessibilityIdentifier("SettingsExerciseLibraryLink")

                NavigationLink(value: SettingsRoute.templates) {
                    Label("Templates", systemImage: "list.bullet.clipboard")
                }
                .accessibilityIdentifier("SettingsTemplatesLink")
            }

            // Logging preferences are controls, not destinations, so they sit
            // apart from the icon-led navigation rows above.
            Section("Logging") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Weight Unit")
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityHidden(true)
                    Picker("Weight Unit", selection: weightUnitBinding) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("WeightUnitPicker")
                }
                .padding(.vertical, 4)

                Toggle("Rest Timer", isOn: restTimerEnabledBinding)
                    .accessibilityIdentifier("SettingsRestTimerToggle")

                if restTimer.isEnabled {
                    Stepper(value: restTimerBinding, in: 30...300, step: 15) {
                        LabeledContent("Rest Duration", value: "\(settings.defaultRestTimerSeconds) seconds")
                            .padding(.trailing, 12)
                    }
                    .accessibilityIdentifier("SettingsRestTimerStepper")
                }

                Toggle(isOn: $rpeEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RPE")
                        Text("Rate how hard each set felt.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .accessibilityIdentifier("SettingsRPEToggle")
            }

            Section {
                // An HStack, not LabeledContent, so the menu keeps its own
                // accessibility element and only the trailing control opens it.
                HStack(spacing: 12) {
                    Label("App Appearance", systemImage: appAppearanceStore.appearance.systemImage)

                    Spacer(minLength: 12)

                    Menu {
                        Picker("App Appearance", selection: appearanceBinding) {
                            ForEach(AppAppearance.allCases, id: \.self) { appearance in
                                Text(appearance.displayName)
                                    .tag(appearance)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack(alignment: .trailing) {
                                ForEach(AppAppearance.allCases, id: \.self) { appearance in
                                    Text(appearance.displayName)
                                        .opacity(appearance == appAppearanceStore.appearance ? 1 : 0)
                                }
                            }
                            .accessibilityHidden(true)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                    .accessibilityIdentifier("AppAppearancePicker")
                    .accessibilityLabel("App Appearance")
                    .accessibilityValue(appAppearanceStore.appearance.displayName)
                }
            }

            PrivacyDataSection(
                exportWorkoutHistory: exportWorkoutHistory,
                links: .release
            )

            appInfoSection
        }
        .labelStyle(SettingsRowLabelStyle())
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
        .onChange(of: isWhatsNewPresented, initial: true) { _, isPresented in
            UIHangContextObservability.shared.settingsWhatsNewChanged(isPresented: isPresented)
        }
        .sheet(item: $sheetPresentation) { presentation in
            switch presentation {
            case .export(let exportFile):
                ActivityView(activityItems: [exportFile.url])
            case .appInfo(let launchPresentation):
                LaunchExperienceSheet(presentation: launchPresentation) {
                    sheetPresentation = nil
                }
            }
        }
        .onDisappear {
            UIHangContextObservability.shared.settingsWhatsNewChanged(isPresented: false)
            copyFeedbackResetTask?.cancel()
            copyFeedbackResetTask = nil
            copyFeedbackState = .idle
        }
    }

    private var isWhatsNewPresented: Bool {
        if case .appInfo(.whatsNew)? = sheetPresentation { return true }
        return false
    }

    private var appInfoSection: some View {
        Section("App") {
            LabeledContent {
                // The row title already says "Version".
                Text(AppBuildInfo.current.versionAndBuild)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("SettingsAppVersionValue")
            } label: {
                Label("Version", systemImage: "info.circle")
            }

            if let whatsNew = AppReleaseCatalog.latestWhatsNew(upTo: AppBuildInfo.current.version) {
                Button {
                    sheetPresentation = .appInfo(.whatsNew(whatsNew))
                } label: {
                    Label("What's New", systemImage: "sparkles")
                }
                .accessibilityIdentifier("SettingsWhatsNewButton")
            }

            Link(destination: AppLinks.githubRepositoryURL) {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .accessibilityIdentifier("SettingsGitHubLink")

            Button {
                copyAppInfo()
            } label: {
                Label(copyFeedbackState.title, systemImage: copyFeedbackState.systemImage)
            }
            .accessibilityIdentifier("SettingsCopyAppInfoButton")
            .animation(.easeInOut(duration: 0.15), value: copyFeedbackState)
        }
    }

    private func exportWorkoutHistory() {
        let completedSessions = WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        )

        guard !completedSessions.isEmpty else {
            alert = .noWorkoutHistory
            return
        }

        do {
            let csv = WorkoutDataExportService().csv(
                for: completedSessions,
                unit: settings.weightUnit,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
            )
            let url = try WorkoutExportFileWriter().write(csv: csv)
            sheetPresentation = .export(ExportFile(url: url))
        } catch {
            alert = .exportFailure(error.localizedDescription)
        }
    }

    private func copyAppInfo() {
        UIPasteboard.general.string = AppBuildInfo.current.supportSummary(device: .current)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showCopyConfirmation()
    }

    private func showCopyConfirmation() {
        copyFeedbackResetTask?.cancel()
        copyFeedbackState = .copied
        copyFeedbackResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copyFeedbackState = .idle
            copyFeedbackResetTask = nil
        }
    }

    private func showSaveFailure(_ error: Error) {
        alert = .saveFailure(error.localizedDescription)
    }

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private enum SettingsSheetPresentation: Identifiable {
        case export(ExportFile)
        case appInfo(LaunchExperiencePresentation)

        var id: String {
            switch self {
            case .export(let exportFile):
                "export-\(exportFile.id.uuidString)"
            case .appInfo(let presentation):
                "app-info-\(presentation.id)"
            }
        }
    }

    private struct SettingsAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String

        static let noWorkoutHistory = SettingsAlert(
            title: "No Workout History",
            message: "Complete a workout before exporting your history."
        )

        static func exportFailure(_ message: String) -> SettingsAlert {
            SettingsAlert(
                title: "Couldn't Export Workouts",
                message: message
            )
        }

        static func saveFailure(_ message: String) -> SettingsAlert {
            SettingsAlert(
                title: "Couldn't Save Settings",
                message: message
            )
        }
    }

    private var weightUnitBinding: Binding<MeasurementUnit> {
        Binding(
            get: { settings.weightUnit },
            set: { unit in
                do {
                    try SettingsMutationService(syncScheduler: syncScheduler).updateWeightUnit(unit, settings: settings, context: modelContext)
                    alert = nil
                } catch {
                    modelContext.rollback()
                    showSaveFailure(error)
                }
            }
        )
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { appAppearanceStore.appearance },
            set: { appAppearanceStore.appearance = $0 }
        )
    }

    private var restTimerEnabledBinding: Binding<Bool> {
        Binding(
            get: { restTimer.isEnabled },
            set: { enabled in
                withAnimation { restTimer.setEnabled(enabled) }
            }
        )
    }

    private var restTimerBinding: Binding<Int> {
        Binding(
            get: { settings.defaultRestTimerSeconds },
            set: { seconds in
                do {
                    try SettingsMutationService(syncScheduler: syncScheduler).updateDefaultRestTimerSeconds(
                        seconds,
                        settings: settings,
                        context: modelContext
                    )
                    alert = nil
                } catch {
                    modelContext.rollback()
                    showSaveFailure(error)
                }
            }
        )
    }
}

enum CopyAppInfoFeedbackState: Equatable {
    case idle
    case copied

    var title: String {
        switch self {
        case .idle:
            "Copy App Info"
        case .copied:
            "Copied"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "doc.on.doc"
        case .copied:
            "checkmark"
        }
    }
}


/// Settings rows read as rows rather than links: the title uses the primary
/// label color and the tinted icon carries the interaction cue. Titles that set
/// their own color, such as destructive rows, keep it.
struct SettingsRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
                .foregroundStyle(AppTheme.textPrimary)
        } icon: {
            configuration.icon
                .foregroundStyle(AppTheme.brandAccentForeground)
        }
    }
}
