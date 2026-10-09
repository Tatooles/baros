import AudioToolbox
import UIKit
import UserNotifications

@MainActor
final class RestTimerNotifications: RestNotificationScheduling {
    private let center: UNUserNotificationCenter
    private var pendingOperation: Task<Void, Never>?
    private var revision = 0
    private static let identifier = "baros.workout-rest"

    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    func schedule(_ rest: WorkoutRest, requestAuthorization: Bool) {
        revision += 1
        let revision = revision
        let previous = pendingOperation
        // Serialize adds and removals, including work suspended on the permission
        // prompt. Skipping/replacing during that prompt must not leave a stale alert.
        pendingOperation = Task { [self] in
            await previous?.value
            guard self.revision == revision else { return }
            var settings = await center.notificationSettings()
            if requestAuthorization, settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            }
            guard self.revision == revision else { return }
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
            let delay = rest.endsAt.timeIntervalSinceNow
            guard delay > 0,
                settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest over"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: Self.identifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false))
            try? await center.add(request)
        }
    }

    func remove() {
        revision += 1
        let previous = pendingOperation
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        pendingOperation = Task { [center] in
            await previous?.value
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        }
    }
}

extension RestTimerCoordinator {
    static func live(
        defaults: UserDefaults = .standard,
        notifications: (any RestNotificationScheduling)? = nil
    ) -> RestTimerCoordinator {
        let key = "active-workout-rest-v1"
        let restored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WorkoutRest.self, from: $0) }
        #if DEBUG
            let isUITest = ProcessInfo.processInfo.arguments.contains("--uitest-in-memory-store")
        #else
            let isUITest = false
        #endif
        return RestTimerCoordinator(
            restoredRest: isUITest ? nil : restored,
            persist: { rest in
                guard !isUITest else { return }
                if let rest, let data = try? JSONEncoder().encode(rest) {
                    defaults.set(data, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            },
            notifications: notifications
                ?? (isUITest && !ProcessInfo.processInfo.arguments.contains("--uitest-enable-rest-notifications")
                    ? SilentRestNotifications() : RestTimerNotifications()),
            foregroundAlert: {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                AudioServicesPlaySystemSound(1007)
            },
            voiceOverRunning: { UIAccessibility.isVoiceOverRunning }
        )
    }
}
