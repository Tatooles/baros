@preconcurrency import ActivityKit
import Foundation

@MainActor
final class WorkoutLiveActivityCoordinator {
    private let stateStore: WorkoutLiveActivityStateStore
    private var requestRetryState = WorkoutLiveActivityRequestRetryState()
    private var latestSnapshot: WorkoutLiveActivitySnapshot?
    private var pendingSnapshot: WorkoutLiveActivitySnapshot?
    private var hasPendingSynchronization = false
    private var reconcileTask: Task<Void, Never>?
    private var activityStateTasks: [String: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard) {
        stateStore = WorkoutLiveActivityStateStore(defaults: defaults)
    }

    func synchronize(
        snapshot: WorkoutLiveActivitySnapshot?,
        allowsRequestRetry: Bool = false
    ) {
        latestSnapshot = snapshot
        pendingSnapshot = snapshot
        hasPendingSynchronization = true
        if let workoutID = snapshot?.workoutID {
            requestRetryState.prepare(for: workoutID)
            if allowsRequestRetry {
                _ = requestRetryState.beginRetryIfAvailable(for: workoutID)
            }
        }

        guard reconcileTask == nil else { return }
        reconcileTask = Task { [weak self] in
            await self?.drainPendingSnapshots()
        }
    }

    private func drainPendingSnapshots() async {
        while hasPendingSynchronization {
            hasPendingSynchronization = false
            let snapshot = pendingSnapshot
            pendingSnapshot = nil
            await reconcile(snapshot: snapshot)
        }

        reconcileTask = nil
    }

    private func reconcile(snapshot: WorkoutLiveActivitySnapshot?) async {
        let activities = Activity<WorkoutLiveActivityAttributes>.activities
        let records = activities.map(WorkoutLiveActivityRecord.init(activity:))

        if let workoutID = snapshot?.workoutID {
            stateStore.clearState(forWorkoutsOtherThan: workoutID)
            requestRetryState.prepare(for: workoutID)
        }

        let plan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: snapshot?.workoutID,
            activities: records,
            successfullyRequestedWorkoutID: stateStore.successfullyRequestedWorkoutID,
            suppressedWorkoutID: stateStore.suppressedWorkoutID
        )

        if plan.shouldSuppress, let workoutID = snapshot?.workoutID {
            stateStore.suppress(workoutID: workoutID)
        }

        for activityID in plan.activityIDsToEnd {
            guard let activity = activities.first(where: { $0.id == activityID }) else {
                continue
            }
            stopObserving(activityID: activityID)
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard let snapshot else { return }

        if let activityID = plan.activityIDToKeep,
           let activity = activities.first(where: { $0.id == activityID }) {
            observeState(of: activity)
            let contentState = snapshot.contentState
            if activity.content.state != contentState {
                await activity.update(
                    ActivityContent(state: contentState, staleDate: nil)
                )
            }
            return
        }

        guard plan.shouldRequest,
              !requestRetryState.blocksRequest,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        do {
            let activity = try Activity.request(
                attributes: snapshot.attributes,
                content: ActivityContent(state: snapshot.contentState, staleDate: nil),
                pushType: nil
            )
            stateStore.recordSuccessfulRequest(workoutID: snapshot.workoutID)
            requestRetryState.recordSuccess(for: snapshot.workoutID)
            observeState(of: activity)
        } catch {
            requestRetryState.recordFailure(for: snapshot.workoutID)
        }
    }

    private func observeState(of activity: Activity<WorkoutLiveActivityAttributes>) {
        guard activityStateTasks[activity.id] == nil else { return }

        activityStateTasks[activity.id] = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                self?.handleStateChange(
                    state,
                    activityID: activity.id,
                    workoutID: activity.attributes.workoutID
                )
            }
        }
    }

    private func handleStateChange(
        _ state: ActivityState,
        activityID: String,
        workoutID: UUID
    ) {
        guard !WorkoutLiveActivityRecord.State(activityState: state).canRemainVisible else {
            return
        }
        stopObserving(activityID: activityID)

        guard latestSnapshot?.workoutID == workoutID else { return }
        stateStore.suppress(workoutID: workoutID)
        synchronize(snapshot: latestSnapshot)
    }

    private func stopObserving(activityID: String) {
        activityStateTasks.removeValue(forKey: activityID)?.cancel()
    }
}

final class WorkoutLiveActivityStateStore {
    private enum Key {
        static let successfullyRequestedWorkoutID = "workoutLiveActivity.successfullyRequestedWorkoutID"
        static let suppressedWorkoutID = "workoutLiveActivity.suppressedWorkoutID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var successfullyRequestedWorkoutID: UUID? {
        uuid(forKey: Key.successfullyRequestedWorkoutID)
    }

    var suppressedWorkoutID: UUID? {
        uuid(forKey: Key.suppressedWorkoutID)
    }

    func recordSuccessfulRequest(workoutID: UUID) {
        defaults.set(workoutID.uuidString, forKey: Key.successfullyRequestedWorkoutID)
        defaults.removeObject(forKey: Key.suppressedWorkoutID)
    }

    func suppress(workoutID: UUID) {
        defaults.set(workoutID.uuidString, forKey: Key.successfullyRequestedWorkoutID)
        defaults.set(workoutID.uuidString, forKey: Key.suppressedWorkoutID)
    }

    func clearState(forWorkoutsOtherThan workoutID: UUID) {
        if successfullyRequestedWorkoutID != workoutID {
            defaults.removeObject(forKey: Key.successfullyRequestedWorkoutID)
        }
        if suppressedWorkoutID != workoutID {
            defaults.removeObject(forKey: Key.suppressedWorkoutID)
        }
    }

    private func uuid(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }
}

private extension WorkoutLiveActivityRecord {
    init(activity: Activity<WorkoutLiveActivityAttributes>) {
        activityID = activity.id
        workoutID = activity.attributes.workoutID
        state = State(activityState: activity.activityState)
    }
}
