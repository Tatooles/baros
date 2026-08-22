import Foundation

enum WorkoutLiveActivityLink {
    enum Route: Equatable {
        case workout(UUID)
        case malformedWorkoutLink
        case unrelated
    }

    private static let scheme = "baros"
    private static let host = "active-workout"

    static func url(for workoutID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(workoutID.uuidString.lowercased())"
        return components.url!
    }

    static func route(from url: URL) -> Route {
        guard url.scheme == scheme, url.host == host else {
            return .unrelated
        }

        let pathComponents = url.pathComponents.dropFirst()
        guard
            pathComponents.count == 1,
            let identifier = pathComponents.first,
            let workoutID = UUID(uuidString: identifier)
        else {
            return .malformedWorkoutLink
        }
        return .workout(workoutID)
    }
}
