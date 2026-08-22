import SwiftUI

private struct WorkoutLiveActivityIntegrationModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let snapshot: WorkoutLiveActivitySnapshot?
    let navigationState: AppNavigationState
    let coordinator: WorkoutLiveActivityCoordinator
    let willOpenWorkout: () -> Void
    @State private var pendingWorkoutID: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: snapshot, initial: true) { _, snapshot in
                coordinator.synchronize(snapshot: snapshot)
                openPendingWorkoutIfReady()
            }
            .onChange(of: currentOwnerCoordinator.state, initial: true) { _, _ in
                openPendingWorkoutIfReady()
            }
            .onChange(of: scenePhase) { _, newScenePhase in
                guard newScenePhase == .active else { return }
                coordinator.synchronize(
                    snapshot: snapshot,
                    allowsRequestRetry: true
                )
            }
            .onOpenURL { url in
                guard let workoutID = WorkoutLiveActivityLink.workoutID(from: url) else {
                    return
                }
                pendingWorkoutID = workoutID
                openPendingWorkoutIfReady()
            }
    }

    private func openPendingWorkoutIfReady() {
        guard let workoutID = pendingWorkoutID else { return }
        if case .resolving(ownerTokenIdentifier: nil) = currentOwnerCoordinator.state {
            return
        }

        pendingWorkoutID = nil
        willOpenWorkout()
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
        willOpenWorkout: @escaping () -> Void
    ) -> some View {
        modifier(
            WorkoutLiveActivityIntegrationModifier(
                snapshot: snapshot,
                navigationState: navigationState,
                coordinator: coordinator,
                willOpenWorkout: willOpenWorkout
            )
        )
    }
}
