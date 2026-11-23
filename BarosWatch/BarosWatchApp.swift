import SwiftUI

/// The Baros Watch companion (ADR 0005). For now it only proves the target builds, signs, and
/// installs with the iPhone app; #464 adds the workout session, heart rate, and elapsed time.
@main
struct BarosWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 6) {
                Text("Baros")
                    .font(.headline)
                Text("Start a workout on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityIdentifier("BarosWatchPlaceholder")
        }
    }
}
