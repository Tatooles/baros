import BarosCore
import SwiftUI

/// Asks the Apple Health recorder for a pass whenever committed workout state may have changed:
/// a workout starts, finishes, or is discarded or edited, the Current Owner changes, or the app
/// returns to the foreground. The recorder reads saved records itself (ADR 0005).
private struct AppleHealthIntegrationModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let controller: AppleHealthController
    let sessions: [WorkoutSession]
    let activeSessionID: UUID?

    private struct Fingerprint: Equatable {
        let activeSessionID: UUID?
        let count: Int
        let latestUpdate: Date?
    }

    private var fingerprint: Fingerprint {
        Fingerprint(
            activeSessionID: activeSessionID,
            count: sessions.count,
            latestUpdate: sessions.lazy.map(\.updatedAt).max()
        )
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: fingerprint, initial: true) { _, _ in
                controller.requestReconciliation()
            }
            .onChange(of: currentOwnerCoordinator.state) { _, _ in
                controller.requestReconciliation()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                controller.requestReconciliation()
            }
            .task(id: activeSessionID) {
                // One pass when a live session would pass its age limit, even if nothing else changes.
                guard activeSessionID != nil else { return }
                try? await Task.sleep(for: .seconds(AppleHealthEnvironment.maximumSessionAge + 60))
                guard !Task.isCancelled else { return }
                controller.requestReconciliation()
            }
    }
}

extension View {
    func appleHealthIntegration(
        controller: AppleHealthController,
        sessions: [WorkoutSession],
        activeSessionID: UUID?
    ) -> some View {
        modifier(AppleHealthIntegrationModifier(
            controller: controller,
            sessions: sessions,
            activeSessionID: activeSessionID
        ))
    }
}
