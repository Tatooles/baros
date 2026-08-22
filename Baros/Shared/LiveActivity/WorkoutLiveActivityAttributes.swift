import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let title: String
        let completedSetCount: Int
        let totalSetCount: Int
    }

    let workoutID: UUID
    let startedAt: Date
}
