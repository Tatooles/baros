import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let title: String
        let completedSetCount: Int
        let totalSetCount: Int
        var restStartedAt: Date? = nil
        var restEndsAt: Date? = nil
    }

    let workoutID: UUID
    let startedAt: Date
}
