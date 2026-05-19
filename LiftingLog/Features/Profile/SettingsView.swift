import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: UserSettings

    var body: some View {
        Form {
            Section("Units") {
                Picker("Weight Unit", selection: weightUnitBinding) {
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Rest Timer") {
                Stepper(value: restTimerBinding, in: 30...300, step: 15) {
                    Text("\(settings.defaultRestTimerSeconds) seconds")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weightUnitBinding: Binding<MeasurementUnit> {
        Binding(
            get: { settings.weightUnit },
            set: { unit in
                try? settings.updateWeightUnit(unit, context: modelContext)
            }
        )
    }

    private var restTimerBinding: Binding<Int> {
        Binding(
            get: { settings.defaultRestTimerSeconds },
            set: { seconds in
                settings.defaultRestTimerSeconds = seconds
                settings.touch()
                try? modelContext.save()
            }
        )
    }
}
