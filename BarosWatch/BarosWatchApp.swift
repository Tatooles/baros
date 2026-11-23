import HealthKit
import SwiftUI
import WatchKit

/// The Baros Watch companion (ADR 0005): live heart rate and elapsed time for a workout started on
/// the iPhone. Logging stays on the iPhone.
@main
struct BarosWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView(manager: .shared)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// The iPhone started a Baros workout with `startWatchApp`.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchWorkoutManager.shared.start(configuration: workoutConfiguration)
        }
    }

    /// The app relaunched while its workout session was still running.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            await WatchWorkoutManager.shared.recover()
        }
    }
}
