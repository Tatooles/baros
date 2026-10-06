import Foundation
import Observation
import SwiftData

/// Device-local state, intentionally kept out of the synced workout graph.
struct WorkoutRest: Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let setID: UUID
    let startedAt: Date
    var endsAt: Date
    var wasSkipped: Bool

    func remainingSeconds(at date: Date) -> Int {
        max(0, Int(endsAt.timeIntervalSince(date).rounded(.up)))
    }

    func remainingFraction(at date: Date) -> Double {
        min(1, max(0, endsAt.timeIntervalSince(date) / max(1, endsAt.timeIntervalSince(startedAt))))
    }
}

@Observable
final class RestTimerPeriod {
    var rest: WorkoutRest
    var isFinished = false
    var controlsExpanded = false

    init(rest: WorkoutRest) { self.rest = rest }
}

/// Stable per-set observation seam. Only the old and new gutter slots change
/// when rest is replaced; cards and set rows never observe the global timer.
@Observable
final class RestTimerSlot {
    var period: RestTimerPeriod?
}

@MainActor
protocol RestNotificationScheduling {
    func schedule(_ rest: WorkoutRest, requestAuthorization: Bool)
    func remove()
}

@MainActor
struct SilentRestNotifications: RestNotificationScheduling {
    func schedule(_ rest: WorkoutRest, requestAuthorization: Bool) {}
    func remove() {}
}

@Observable
@MainActor
final class RestTimerCoordinator {
    private(set) var current: RestTimerPeriod?
    private(set) var inlineIsVisible: Bool?
    @ObservationIgnored private var slots: [UUID: RestTimerSlot] = [:]
    @ObservationIgnored private var savedRest: WorkoutRest?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let persist: (WorkoutRest?) -> Void
    @ObservationIgnored private let notifications: any RestNotificationScheduling
    @ObservationIgnored private let foregroundAlert: () -> Void
    @ObservationIgnored private let voiceOverRunning: () -> Bool
    @ObservationIgnored private let schedulesTasks: Bool
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var isAppActive = true

    init(
        restoredRest: WorkoutRest? = nil,
        clock: @escaping () -> Date = { .now },
        persist: @escaping (WorkoutRest?) -> Void = { _ in },
        notifications: any RestNotificationScheduling = SilentRestNotifications(),
        foregroundAlert: @escaping () -> Void = {},
        voiceOverRunning: @escaping () -> Bool = { false },
        schedulesTasks: Bool = true
    ) {
        savedRest = restoredRest
        self.clock = clock
        self.persist = persist
        self.notifications = notifications
        self.foregroundAlert = foregroundAlert
        self.voiceOverRunning = voiceOverRunning
        self.schedulesTasks = schedulesTasks
    }

    var showsHeaderFallback: Bool { current != nil && inlineIsVisible == false }

    func slot(for setID: UUID) -> RestTimerSlot {
        if let slot = slots[setID] { return slot }
        let slot = RestTimerSlot()
        slots[setID] = slot
        return slot
    }

    func start(sessionID: UUID, setID: UUID, duration: Int) {
        clearPresentation()
        let now = clock()
        let rest = WorkoutRest(
            id: UUID(), sessionID: sessionID, setID: setID,
            startedAt: now, endsAt: now.addingTimeInterval(Double(max(1, duration))), wasSkipped: false)
        install(rest)
        current?.controlsExpanded = !voiceOverRunning()
        scheduleCollapse(after: 3)
        notifications.schedule(rest, requestAuthorization: true)
        scheduleExpiry()
    }

    func adjust(by seconds: TimeInterval) {
        guard let period = current, !period.isFinished else { return }
        period.rest.endsAt = max(clock().addingTimeInterval(1), period.rest.endsAt.addingTimeInterval(seconds))
        savedRest = period.rest
        persist(savedRest)
        notifications.schedule(period.rest, requestAuthorization: false)
        scheduleCollapse(after: 6)
        scheduleExpiry()
    }

    func skip() {
        guard var rest = current?.rest else { return }
        rest.wasSkipped = true
        savedRest = rest
        persist(rest)
        clearPresentation()
        notifications.remove()
    }

    func cancel(ifStartedBy setID: UUID) {
        guard (current?.rest ?? savedRest)?.setID == setID else { return }
        cancel()
    }

    func cancel(sessionID: UUID) {
        guard (current?.rest ?? savedRest)?.sessionID == sessionID else { return }
        cancel()
    }

    func cancel() {
        clearPresentation()
        savedRest = nil
        persist(nil)
        notifications.remove()
    }

    /// Called at the shell, including while the workout is minimized. A
    /// disappearing workout sheet is not a workout ending.
    func reconcile(with session: WorkoutSession?) {
        guard let rest = current?.rest ?? savedRest else { return }
        guard let session, session.id == rest.sessionID, session.status == .active, !session.isDeleted,
            session.sortedLoggedExercises.contains(where: { exercise in
                exercise.sortedSets.contains { $0.id == rest.setID && $0.isCompleted }
            })
        else {
            cancel()
            return
        }
        guard current == nil else { return }
        guard !rest.wasSkipped, rest.endsAt > clock() else {
            cancel()
            return
        }
        install(rest)
        notifications.schedule(rest, requestAuthorization: false)
        scheduleExpiry()
    }

    func setAppActive(_ active: Bool) {
        // Reconcile elapsed background time before foregrounding, so an alert
        // that belonged to the background is never replayed on return.
        if active, !isAppActive { expireIfNeeded() }
        isAppActive = active
    }

    func expireIfNeeded() {
        guard let period = current, !period.isFinished, period.rest.endsAt <= clock() else { return }
        period.isFinished = true
        collapseControls()
        savedRest = nil
        persist(nil)
        if isAppActive {
            notifications.remove()
            foregroundAlert()
        }
        // Background delivery belongs to the OS. Leave its notification alone.
        if clock().timeIntervalSince(period.rest.endsAt) >= 4 {
            clearPresentation()
        }
    }

    func reportInlineVisibility(_ visible: Bool, restID: UUID) {
        guard current?.rest.id == restID else { return }
        if inlineIsVisible != visible { inlineIsVisible = visible }
    }

    func toggleControls() {
        guard let period = current, !period.isFinished else { return }
        period.controlsExpanded.toggle()
        scheduleCollapse(after: 6)
    }

    func collapseControls() {
        collapseTask?.cancel()
        current?.controlsExpanded = false
    }

    private func install(_ rest: WorkoutRest) {
        let period = RestTimerPeriod(rest: rest)
        current = period
        inlineIsVisible = nil
        slot(for: rest.setID).period = period
        savedRest = rest
        persist(rest)
    }

    private func clearPresentation() {
        expiryTask?.cancel()
        collapseTask?.cancel()
        if let current { slot(for: current.rest.setID).period = nil }
        current = nil
        inlineIsVisible = nil
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard schedulesTasks, let period = current else { return }
        let restID = period.rest.id
        let delay = max(0, period.rest.endsAt.timeIntervalSince(clock()))
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.current?.rest.id == restID else { return }
            self.expireIfNeeded()
            let remaining = max(0, period.rest.endsAt.addingTimeInterval(4).timeIntervalSince(self.clock()))
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard self.current?.rest.id == restID else { return }
            self.clearPresentation()
        }
    }

    private func scheduleCollapse(after seconds: Double) {
        collapseTask?.cancel()
        guard schedulesTasks, current?.controlsExpanded == true else { return }
        collapseTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.collapseControls()
        }
    }
}

enum RestDurationLookup {
    /// Exercise-aware seam for #296; today all exercises use the owner's setting.
    static func seconds(for exercise: LoggedExercise, settings: UserSettings?) -> Int {
        settings?.defaultRestTimerSeconds ?? 90
    }
}
