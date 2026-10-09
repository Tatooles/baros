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

/// Scene state that matters to rest alerts. A system overlay or permission
/// prompt makes the scene inactive, but the app still owns the alert there.
enum RestTimerScenePhase {
    case foreground
    case background
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
    /// Visible dividers keep their slots alive; the coordinator keeps only the
    /// slot it is presenting. Slots for sets nobody shows are released.
    @ObservationIgnored private var slots: [UUID: WeakSlot] = [:]
    @ObservationIgnored private var presentedSlot: RestTimerSlot?
    @ObservationIgnored private var savedRest: WorkoutRest?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let persist: (WorkoutRest?) -> Void
    @ObservationIgnored private let notifications: any RestNotificationScheduling
    @ObservationIgnored private let foregroundAlert: () -> Void
    @ObservationIgnored private let voiceOverRunning: () -> Bool
    @ObservationIgnored private let schedulesTasks: Bool
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var scenePhase = RestTimerScenePhase.foreground
    @ObservationIgnored private var expiredInBackground = false

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
        if let slot = slots[setID]?.slot { return slot }
        let slot = RestTimerSlot()
        slots[setID] = WeakSlot(slot: slot)
        return slot
    }

    var retainedSlotCount: Int { slots.count }

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
    var restForReconciliation: WorkoutRest? { current?.rest ?? savedRest }

    func reconcile(with session: WorkoutSession?, ownerState: CurrentOwnerCoordinator.State = .localOnly) {
        // Initial ownership recovery is asynchronous. Absence in that temporary
        // scope is not proof that a persisted workout belongs to another owner.
        if current == nil, case .resolving(ownerTokenIdentifier: nil) = ownerState { return }
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

    func setScenePhase(_ phase: RestTimerScenePhase) {
        // Reconcile elapsed background time before foregrounding, so an alert
        // that belonged to the background is never replayed on return.
        if phase == .foreground, scenePhase == .background {
            expireIfNeeded()
            // Back in the app, the delivered "Rest over" is stale. Relaunch
            // reconciliation clears it the same way.
            if expiredInBackground { notifications.remove() }
            expiredInBackground = false
        }
        scenePhase = phase
    }

    func expireIfNeeded() {
        guard let period = current, !period.isFinished, period.rest.endsAt <= clock() else { return }
        period.isFinished = true
        collapseControls()
        savedRest = nil
        persist(nil)
        if scenePhase == .foreground {
            notifications.remove()
            foregroundAlert()
        } else {
            // Background delivery belongs to the OS until the user returns.
            expiredInBackground = true
        }
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
        slots = slots.filter { $0.value.slot != nil }
        presentedSlot = slot(for: rest.setID)
        presentedSlot?.period = period
        savedRest = rest
        persist(rest)
    }

    private func clearPresentation() {
        expiryTask?.cancel()
        collapseTask?.cancel()
        presentedSlot?.period = nil
        presentedSlot = nil
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

private struct WeakSlot {
    weak var slot: RestTimerSlot?
}

enum RestDurationLookup {
    /// Exercise-aware seam for #296; today all exercises use the owner's setting.
    static func seconds(for exercise: LoggedExercise, settings: UserSettings?) -> Int {
        settings?.defaultRestTimerSeconds ?? 90
    }
}
