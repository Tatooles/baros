import SwiftUI

/// The **Save Workouts to Apple Health** setting (ADR 0005). Hidden when Health isn't available.
struct AppleHealthSettingsSection: View {
    @Bindable var controller: AppleHealthController

    var body: some View {
        if controller.settingState != .unavailable {
            Section {
                Toggle(isOn: enabledBinding) {
                    Label("Save Workouts to Apple Health", systemImage: "heart.text.square")
                }
                .disabled(controller.isRequestingAccess)
                .accessibilityIdentifier("SettingsAppleHealthToggle")
            } header: {
                Text("Apple Health")
            } footer: {
                Text(footer)
                    .accessibilityIdentifier("SettingsAppleHealthFooter")
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.isEnabled },
            set: { isOn in
                Task { await controller.setEnabled(isOn) }
            }
        )
    }

    private var footer: String {
        switch controller.settingState {
        case .accessDenied:
            "Health access is off, so workouts aren't saved. In the Health app, tap your profile picture, then Apps, then Baros, and turn on Workouts."
        case .on, .off, .unavailable:
            "Each workout you start on this iPhone is recorded as a strength workout in Apple Health and Fitness. Baros never uploads your Health data."
        }
    }
}
