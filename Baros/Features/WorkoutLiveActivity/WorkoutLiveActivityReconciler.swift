@preconcurrency import ActivityKit
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

        init(activityState: ActivityState) {
            switch activityState {
            case .pending:
                self = .pending
            case .active:
                self = .active
            case .ended:
                self = .ended
            case .dismissed:
                self = .dismissed
            case .stale:
                self = .stale
            @unknown default:
                self = .ended
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
                shouldSuppress: false
            )
        }

        if suppressedWorkoutID == activeWorkoutID {
            return WorkoutLiveActivityReconciliationPlan(
                activityIDToKeep: nil,
                activityIDsToEnd: activities.map(\.activityID),
                shouldRequest: false,
                shouldSuppress: false
            )
        }

        let matchingVisibleActivities = activities.filter {
            $0.workoutID == activeWorkoutID && $0.state.canRemainVisible
        }
        let activityToKeep = matchingVisibleActivities.first { $0.state == .active }
            ?? matchingVisibleActivities.first
        let activityIDsToEnd = activities
            .filter { $0.activityID != activityToKeep?.activityID }
            .map(\.activityID)

        if let activityToKeep {
            return WorkoutLiveActivityReconciliationPlan(
                activityIDToKeep: activityToKeep.activityID,
                activityIDsToEnd: activityIDsToEnd,
                shouldRequest: false,
                shouldSuppress: false
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
            shouldSuppress: shouldSuppress
        )
    }
}

enum WorkoutLiveActivityRequestHistoryPolicy {
    static func shouldClearSuccessfulRequest(
        successfullyRequestedWorkoutID: UUID?,
        activities: [WorkoutLiveActivityRecord]
    ) -> Bool {
        guard let successfullyRequestedWorkoutID else { return false }
        return activities.contains {
            $0.workoutID == successfullyRequestedWorkoutID && $0.state.canRemainVisible
        }
    }
}

struct WorkoutLiveActivityRequestRetryState: Equatable {
    private(set) var failedWorkoutID: UUID?
    private(set) var retriedWorkoutID: UUID?

    var blocksRequest: Bool {
        failedWorkoutID != nil
    }

    mutating func prepare(for workoutID: UUID) {
        if failedWorkoutID != workoutID {
            failedWorkoutID = nil
        }
        if retriedWorkoutID != workoutID {
            retriedWorkoutID = nil
        }
    }

    mutating func recordFailure(for workoutID: UUID) {
        failedWorkoutID = workoutID
    }

    mutating func beginRetryIfAvailable(for workoutID: UUID) -> Bool {
        guard failedWorkoutID == workoutID, retriedWorkoutID != workoutID else {
            return false
        }

        failedWorkoutID = nil
        retriedWorkoutID = workoutID
        return true
    }

    mutating func recordSuccess(for workoutID: UUID) {
        if failedWorkoutID == workoutID {
            failedWorkoutID = nil
        }
    }
}
