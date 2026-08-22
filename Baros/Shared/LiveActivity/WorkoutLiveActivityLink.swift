import Foundation

enum WorkoutLiveActivityLink {
    private static let scheme = "baros"
    private static let host = "active-workout"

    static func url(for workoutID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(workoutID.uuidString.lowercased())"
        return components.url!
    }

    static func workoutID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == host else {
            return nil
        }

        let pathComponents = url.pathComponents.dropFirst()
        guard pathComponents.count == 1, let identifier = pathComponents.first else {
            return nil
        }
        return UUID(uuidString: identifier)
    }
}
