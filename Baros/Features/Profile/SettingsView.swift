import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppAppearancePreferenceStore.self) private var appAppearanceStore
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    let settings: UserSettings
    let onDataDeletionCompleted: () -> Void
    @State private var alert: SettingsAlert?
    @State private var copyFeedbackResetTask: Task<Void, Never>?
    @State private var copyFeedbackState = CopyAppInfoFeedbackState.idle
    @State private var sheetPresentation: SettingsSheetPresentation?

    var body: some View {
        Form {
            Section("Appearance") {
                Menu {
                    Picker("App Appearance", selection: appearanceBinding) {
                        ForEach(AppAppearance.allCases, id: \.self) { appearance in
                            Label(appearance.displayName, systemImage: appearance.systemImage)
                                .tag(appearance)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: appAppearanceStore.appearance.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.onBrandAccent)
                            .frame(width: 30, height: 30)
                            .background(
                                AppTheme.brandAccentFill,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .accessibilityHidden(true)

                        Text("App Appearance")
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer(minLength: 12)

                        Text(appAppearanceStore.appearance.displayName)
                            .foregroundStyle(AppTheme.textSecondary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("AppAppearancePicker")
                .accessibilityLabel("App Appearance")
                .accessibilityValue(appAppearanceStore.appearance.displayName)
            }

            Section("Units") {
                Picker("Weight Unit", selection: weightUnitBinding) {
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("WeightUnitPicker")
            }

            Section("Rest Timer") {
                Stepper(value: restTimerBinding, in: 30...300, step: 15) {
                    Text("\(settings.defaultRestTimerSeconds) seconds")
                }
            }

            SettingsAccountSection()

            PrivacyDataSection(
                exportWorkoutHistory: exportWorkoutHistory,
                links: .release,
                onDeletionCompleted: onDataDeletionCompleted
            )

            appInfoSection
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text("OK"))
            )
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
            copyFeedbackResetTask?.cancel()
            copyFeedbackResetTask = nil
            copyFeedbackState = .idle
        }
    }

    private var appInfoSection: some View {
        Section("App") {
            HStack(alignment: .firstTextBaseline) {
                Text("Version")
                Spacer(minLength: 16)
                Text(AppBuildInfo.current.settingsVersionText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("SettingsAppVersionValue")
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
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        )

        guard !completedSessions.isEmpty else {
            alert = .noWorkoutHistory
            return
        }

        do {
            let csv = WorkoutDataExportService().csv(
                for: completedSessions,
                unit: settings.weightUnit,
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
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
