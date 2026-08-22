import Foundation

struct WorkoutLiveActivityRecord: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case pending
        case active
        case ended
        case dismissed
        case stale

        var canRemainVisible: Bool {
            switch self {
            case .pending, .active:
                return true
            case .ended, .dismissed, .stale:
                return false
            }
        }
    }

    let activityID: String
    let workoutID: UUID
    let state: State
}

struct WorkoutLiveActivityReconciliationPlan: Equatable, Sendable {
    let activityIDToKeep: String?
    let activityIDsToEnd: [String]
    let shouldRequest: Bool
    let shouldSuppress: Bool
    let shouldClearStoredState: Bool
}

enum WorkoutLiveActivityReconciler {
    static func plan(
        activeWorkoutID: UUID?,
        activities: [WorkoutLiveActivityRecord],
        successfullyRequestedWorkoutID: UUID?,
        suppressedWorkoutID: UUID?
    ) -> WorkoutLiveActivityReconciliationPlan {
        guard let activeWorkoutID else {
            return WorkoutLiveActivityReconciliationPlan(
                activityIDToKeep: nil,
                activityIDsToEnd: activities.map(\.activityID),
                shouldRequest: false,
                shouldSuppress: false,
                shouldClearStoredState: true
            )
        }

        if suppressedWorkoutID == activeWorkoutID {
            return WorkoutLiveActivityReconciliationPlan(
                activityIDToKeep: nil,
                activityIDsToEnd: activities.map(\.activityID),
                shouldRequest: false,
                shouldSuppress: false,
                shouldClearStoredState: false
            )
        }

        let matchingVisibleActivities = activities.filter {
            $0.workoutID == activeWorkoutID && $0.state.canRemainVisible
        }
        let activityToKeep = matchingVisibleActivities.first
        let activityIDsToEnd = activities
            .filter { $0.activityID != activityToKeep?.activityID }
            .map(\.activityID)

        if let activityToKeep {
            return WorkoutLiveActivityReconciliationPlan(
                activityIDToKeep: activityToKeep.activityID,
                activityIDsToEnd: activityIDsToEnd,
                shouldRequest: false,
                shouldSuppress: false,
                shouldClearStoredState: false
            )
        }

        let hasTerminalMatchingActivity = activities.contains {
            $0.workoutID == activeWorkoutID && !$0.state.canRemainVisible
        }
        let shouldSuppress = hasTerminalMatchingActivity
            || successfullyRequestedWorkoutID == activeWorkoutID

        return WorkoutLiveActivityReconciliationPlan(
            activityIDToKeep: nil,
            activityIDsToEnd: activityIDsToEnd,
            shouldRequest: !shouldSuppress,
            shouldSuppress: shouldSuppress,
            shouldClearStoredState: false
        )
    }
}
