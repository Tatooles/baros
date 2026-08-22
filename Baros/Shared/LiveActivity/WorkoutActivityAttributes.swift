import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let title: String
        let completedSetCount: Int
        let totalSetCount: Int
    }

    let workoutID: UUID
    let startedAt: Date

    static func deepLinkURL(for workoutID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "baros"
        components.host = "active-workout"
        components.path = "/\(workoutID.uuidString.lowercased())"
        return components.url!
    }
}
