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

        let activeWorkoutID = snapshot?.workoutID
        if let activeWorkoutID {
            requestRetryState.prepare(for: activeWorkoutID)
        }

        let successfulRequestWorkoutIDsToClear =
            WorkoutLiveActivityRequestHistoryPolicy.workoutIDsToClear(
            activeWorkoutID: activeWorkoutID,
            successfullyRequestedWorkoutIDs: stateStore.successfullyRequestedWorkoutIDs,
            activities: records
        )
        for workoutID in successfulRequestWorkoutIDsToClear {
            stateStore.clearSuccessfulRequest(workoutID: workoutID)
        }

        let plan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: activeWorkoutID,
            activities: records,
            successfullyRequestedWorkoutID: activeWorkoutID.flatMap {
                stateStore.hasSuccessfullyRequested(workoutID: $0) ? $0 : nil
            },
            suppressedWorkoutID: activeWorkoutID.flatMap {
                stateStore.isSuppressed(workoutID: $0) ? $0 : nil
            }
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
        static let successfullyRequestedWorkoutIDs = "workoutLiveActivity.successfullyRequestedWorkoutID"
        static let suppressedWorkoutIDs = "workoutLiveActivity.suppressedWorkoutID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var successfullyRequestedWorkoutIDs: Set<UUID> {
        uuidSet(forKey: Key.successfullyRequestedWorkoutIDs)
    }

    var suppressedWorkoutIDs: Set<UUID> {
        uuidSet(forKey: Key.suppressedWorkoutIDs)
    }

    func hasSuccessfullyRequested(workoutID: UUID) -> Bool {
        successfullyRequestedWorkoutIDs.contains(workoutID)
    }

    func isSuppressed(workoutID: UUID) -> Bool {
        suppressedWorkoutIDs.contains(workoutID)
    }

    func recordSuccessfulRequest(workoutID: UUID) {
        var successfullyRequestedWorkoutIDs = successfullyRequestedWorkoutIDs
        successfullyRequestedWorkoutIDs.insert(workoutID)
        persist(successfullyRequestedWorkoutIDs, forKey: Key.successfullyRequestedWorkoutIDs)

        var suppressedWorkoutIDs = suppressedWorkoutIDs
        suppressedWorkoutIDs.remove(workoutID)
        persist(suppressedWorkoutIDs, forKey: Key.suppressedWorkoutIDs)
    }

    func suppress(workoutID: UUID) {
        var successfullyRequestedWorkoutIDs = successfullyRequestedWorkoutIDs
        successfullyRequestedWorkoutIDs.insert(workoutID)
        persist(successfullyRequestedWorkoutIDs, forKey: Key.successfullyRequestedWorkoutIDs)

        var suppressedWorkoutIDs = suppressedWorkoutIDs
        suppressedWorkoutIDs.insert(workoutID)
        persist(suppressedWorkoutIDs, forKey: Key.suppressedWorkoutIDs)
    }

    func clearSuccessfulRequest(workoutID: UUID) {
        var successfullyRequestedWorkoutIDs = successfullyRequestedWorkoutIDs
        successfullyRequestedWorkoutIDs.remove(workoutID)
        persist(successfullyRequestedWorkoutIDs, forKey: Key.successfullyRequestedWorkoutIDs)
    }

    private func uuidSet(forKey key: String) -> Set<UUID> {
        if let values = defaults.stringArray(forKey: key) {
            return Set(values.compactMap(UUID.init(uuidString:)))
        }
        if let value = defaults.string(forKey: key),
           let workoutID = UUID(uuidString: value) {
            return [workoutID]
        }
        return []
    }

    private func persist(_ workoutIDs: Set<UUID>, forKey key: String) {
        guard !workoutIDs.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(workoutIDs.map(\.uuidString).sorted(), forKey: key)
    }
}

private extension WorkoutLiveActivityRecord {
    init(activity: Activity<WorkoutLiveActivityAttributes>) {
        activityID = activity.id
        workoutID = activity.attributes.workoutID
        state = State(activityState: activity.activityState)
    }
}
