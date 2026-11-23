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

    /// Changes whenever any workout's revision changes, including a synced edit or tombstone for an
    /// older workout.
    private var fingerprint: Int {
        var hasher = Hasher()
        hasher.combine(activeSessionID)
        for session in sessions {
            hasher.combine(session.id)
            hasher.combine(session.updatedAt)
            hasher.combine(session.deletedAt)
            hasher.combine(session.status)
        }
        return hasher.finalize()
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
