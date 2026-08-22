import Foundation

enum AppLinks {
    static let githubRepositoryURL = URL(string: "https://github.com/Tatooles/baros")!

    static func workoutLiveActivityURL(for workoutID: UUID) -> URL {
        WorkoutActivityAttributes.deepLinkURL(for: workoutID)
    }

    static func workoutID(fromLiveActivityURL url: URL) -> UUID? {
        guard url.scheme == "baros", url.host == "active-workout" else {
            return nil
        }

        let identifier = url.pathComponents.dropFirst().first
        guard url.pathComponents.dropFirst().count == 1, let identifier else {
            return nil
        }
        return UUID(uuidString: identifier)
    }
}
