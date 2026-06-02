import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    let settings: UserSettings
    @State private var alert: SettingsAlert?
    @State private var exportFile: ExportFile?

    var body: some View {
        Form {
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

            Section("Data") {
                Button(action: exportWorkoutHistory) {
                    Label("Export Workout History", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("ExportWorkoutHistoryButton")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
        .sheet(item: $exportFile) { exportFile in
            ActivityView(activityItems: [exportFile.url])
        }
    }

    private func exportWorkoutHistory() {
        let completedSessions = WorkoutSession.visibleCompletedSessions(from: sessions)

        guard !completedSessions.isEmpty else {
            alert = .noWorkoutHistory
            return
        }

        do {
            let csv = WorkoutDataExportService().csv(for: completedSessions, unit: settings.weightUnit)
            let url = try WorkoutExportFileWriter().write(csv: csv)
            exportFile = ExportFile(url: url)
        } catch {
            alert = .exportFailure(error.localizedDescription)
        }
    }

    private func showSaveFailure(_ error: Error) {
        alert = .saveFailure(error.localizedDescription)
    }

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
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
                    try settings.updateWeightUnit(unit, context: modelContext)
                    alert = nil
                } catch {
                    modelContext.rollback()
                    showSaveFailure(error)
                }
            }
        )
    }

    private var restTimerBinding: Binding<Int> {
        Binding(
            get: { settings.defaultRestTimerSeconds },
            set: { seconds in
                settings.defaultRestTimerSeconds = seconds
                settings.touch()
                do {
                    try modelContext.save()
                    alert = nil
                } catch {
                    modelContext.rollback()
                    showSaveFailure(error)
                }
            }
        )
    }
}
