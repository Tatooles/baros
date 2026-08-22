import SwiftUI

enum WorkoutLiveActivitySynchronizationPolicy {
    static func shouldSynchronize(
        snapshot: WorkoutLiveActivitySnapshot?,
        currentOwnerState: CurrentOwnerCoordinator.State
    ) -> Bool {
        guard snapshot == nil else { return true }
        if case .resolving(ownerTokenIdentifier: nil) = currentOwnerState {
            return false
        }
        return true
    }
}

private struct WorkoutLiveActivityIntegrationModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let snapshot: WorkoutLiveActivitySnapshot?
    let navigationState: AppNavigationState
    let coordinator: WorkoutLiveActivityCoordinator
    let willHandleWorkoutLiveActivityLink: () -> Void
    @State private var pendingWorkoutID: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: snapshot, initial: true) { _, snapshot in
                synchronizeIfOwnerReady(snapshot: snapshot)
                openPendingWorkoutIfReady()
            }
            .onChange(of: currentOwnerCoordinator.state) { _, _ in
                synchronizeIfOwnerReady(snapshot: snapshot)
                openPendingWorkoutIfReady()
            }
            .onChange(of: scenePhase) { _, newScenePhase in
                guard newScenePhase == .active else { return }
                synchronizeIfOwnerReady(
                    snapshot: snapshot,
                    allowsRequestRetry: true
                )
            }
            .onOpenURL { url in
                switch WorkoutLiveActivityLink.route(from: url) {
                case let .workout(workoutID):
                    pendingWorkoutID = workoutID
                    openPendingWorkoutIfReady()
                case .malformedWorkoutLink:
                    pendingWorkoutID = nil
                    willHandleWorkoutLiveActivityLink()
                    navigationState.returnHomeFromUnopenableWorkoutLiveActivityLink()
                case .unrelated:
                    break
                }
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

    private func openPendingWorkoutIfReady() {
        guard let workoutID = pendingWorkoutID else { return }
        if case .resolving(ownerTokenIdentifier: nil) = currentOwnerCoordinator.state {
            return
        }

        pendingWorkoutID = nil
        willHandleWorkoutLiveActivityLink()
        navigationState.openWorkoutLiveActivity(
            workoutID: workoutID,
            visibleActiveWorkoutID: snapshot?.workoutID
        )
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
