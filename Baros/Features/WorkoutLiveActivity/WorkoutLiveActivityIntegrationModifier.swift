import SwiftUI

enum WorkoutLiveActivityOwnerResolutionPolicy {
    static func shouldDeferOwnerSensitiveWork(
        currentOwnerState: CurrentOwnerCoordinator.State
    ) -> Bool {
        if case .resolving(ownerTokenIdentifier: nil) = currentOwnerState {
            return true
        }
        return false
    }
}

enum WorkoutLiveActivitySynchronizationPolicy {
    static func shouldSynchronize(
        snapshot: WorkoutLiveActivitySnapshot?,
        currentOwnerState: CurrentOwnerCoordinator.State
    ) -> Bool {
        guard snapshot == nil else { return true }
        return !WorkoutLiveActivityOwnerResolutionPolicy.shouldDeferOwnerSensitiveWork(
            currentOwnerState: currentOwnerState
        )
    }
}

enum WorkoutLiveActivityPendingLink {
    case workout(UUID)
    case malformedWorkoutLink

    init?(route: WorkoutLiveActivityLink.Route) {
        switch route {
        case let .workout(workoutID):
            self = .workout(workoutID)
        case .malformedWorkoutLink:
            self = .malformedWorkoutLink
        case .unrelated:
            return nil
        }
    }

}

private struct WorkoutLiveActivityIntegrationModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let snapshot: WorkoutLiveActivitySnapshot?
    let navigationState: AppNavigationState
    let coordinator: WorkoutLiveActivityCoordinator
    let willHandleWorkoutLiveActivityLink: () -> Void
    @State private var pendingLink: WorkoutLiveActivityPendingLink?

    func body(content: Content) -> some View {
        content
            .onChange(of: snapshot, initial: true) { _, snapshot in
                synchronizeIfOwnerReady(snapshot: snapshot)
                handlePendingLinkIfReady()
            }
            .onChange(of: currentOwnerCoordinator.state) { _, _ in
                synchronizeIfOwnerReady(snapshot: snapshot)
                handlePendingLinkIfReady()
            }
            .onChange(of: scenePhase) { _, newScenePhase in
                guard newScenePhase == .active else { return }
                synchronizeIfOwnerReady(
                    snapshot: snapshot,
                    allowsRequestRetry: true
                )
            }
            .onOpenURL { url in
                guard let pendingLink = WorkoutLiveActivityPendingLink(
                    route: WorkoutLiveActivityLink.route(from: url)
                ) else { return }
                self.pendingLink = pendingLink
                handlePendingLinkIfReady()
            }
    }

    private func synchronizeIfOwnerReady(
        snapshot: WorkoutLiveActivitySnapshot?,
        allowsRequestRetry: Bool = false
    ) {
        guard WorkoutLiveActivitySynchronizationPolicy.shouldSynchronize(
            snapshot: snapshot,
            currentOwnerState: currentOwnerCoordinator.state
        ) else {
            return
        }
        coordinator.synchronize(
            snapshot: snapshot,
            allowsRequestRetry: allowsRequestRetry
        )
    }

    private func handlePendingLinkIfReady() {
        guard
            let pendingLink,
            !WorkoutLiveActivityOwnerResolutionPolicy.shouldDeferOwnerSensitiveWork(
                currentOwnerState: currentOwnerCoordinator.state
            )
        else { return }

        self.pendingLink = nil
        willHandleWorkoutLiveActivityLink()
        switch pendingLink {
        case let .workout(workoutID):
            navigationState.openWorkoutLiveActivity(
                workoutID: workoutID,
                visibleActiveWorkoutID: snapshot?.workoutID
            )
        case .malformedWorkoutLink:
            navigationState.returnHomeFromUnopenableWorkoutLiveActivityLink()
        }
    }
}

extension View {
    func workoutLiveActivityIntegration(
        snapshot: WorkoutLiveActivitySnapshot?,
        navigationState: AppNavigationState,
        coordinator: WorkoutLiveActivityCoordinator,
        willHandleWorkoutLiveActivityLink: @escaping () -> Void
    ) -> some View {
        modifier(
            WorkoutLiveActivityIntegrationModifier(
                snapshot: snapshot,
                navigationState: navigationState,
                coordinator: coordinator,
                willHandleWorkoutLiveActivityLink: willHandleWorkoutLiveActivityLink
            )
        )
    }
}
