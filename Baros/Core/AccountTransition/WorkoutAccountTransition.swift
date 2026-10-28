import Foundation
import Observation
import SwiftData

/// Owns the finish/discard-before-account-action contract. Clerk lifecycle and
/// local-data visibility remain exclusively owned by CurrentOwnerCoordinator.
@MainActor
@Observable
final class WorkoutAccountTransition {
    enum Resolution { case finish, discard }
    enum Destination {
        case signOut, manageAccount, deleteAccount
        var title: String {
            switch self {
            case .signOut: "Sign Out"
            case .manageAccount: "Manage Account"
            case .deleteAccount: "Delete Account"
            }
        }
    }

    private(set) var needsResolution = false
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    private let context: ModelContext
    private let save: (ModelContext) throws -> Void
    private let engine: ActiveWorkoutEngine
    private let owner: () -> String?
    private let syncScheduler: SyncScheduler?
    private var expectedOwner: String?
    private var sessionIDs: [UUID] = []
    private var action: (() async throws -> Void)?

    init(context: ModelContext, engine: ActiveWorkoutEngine,
         syncScheduler: SyncScheduler? = nil,
         save: @escaping (ModelContext) throws -> Void = { context in
             #if DEBUG
             if ProcessInfo.processInfo.arguments.contains("--uitest-fail-account-workout-save") {
                 throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
             }
             #endif
             try context.save()
         }, owner: @escaping () -> String?) {
        self.save = save
        self.context = context
        self.engine = engine
        self.syncScheduler = syncScheduler
        self.owner = owner
    }

    func request(_ action: @escaping () async throws -> Void) async {
        guard !isRunning, !engine.isAccountTransitionInProgress else { return }
        cancel()
        expectedOwner = owner()
        self.action = action
        do {
            let sessions = try activeSessions()
            guard sessions.allSatisfy({ $0.allowsHistoryMutation(ownerTokenIdentifier: expectedOwner) }) else {
                throw TransitionError.hiddenWorkout
            }
            sessionIDs = sessions.map(\.id)
            if sessions.isEmpty {
                isRunning = true
                await performAction()
                isRunning = false
            }
            else { needsResolution = true }
        } catch { fail(error) }
    }

    func resolve(_ resolution: Resolution) async {
        guard needsResolution, !isRunning, !engine.isAccountTransitionInProgress else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            guard owner() == expectedOwner else { throw TransitionError.ownerChanged }
            let sessions = try activeSessions()
            guard sessions.map(\.id) == sessionIDs,
                  sessions.allSatisfy({ $0.allowsHistoryMutation(ownerTokenIdentifier: expectedOwner) }) else {
                throw TransitionError.workoutsChanged
            }
            guard !engine.hasPendingSetSave else { throw TransitionError.pendingSetSave }
            for session in sessions {
                switch resolution {
                case .finish:
                    try engine.finishWorkout(session, ownerTokenIdentifier: expectedOwner,
                        syncScheduler: syncScheduler, context: context, save: save)
                case .discard:
                    try engine.discardWorkout(session, context: context, save: save)
                }
            }
            needsResolution = false
            await performAction()
        } catch {
            fail(error)
            if !(error is TransitionError) {
                errorMessage = "The workout could not be saved. Your account has not changed. Review the unfinished workout and try again. " + error.localizedDescription
            }
        }
    }

    func cancel() {
        guard !isRunning else { return }
        needsResolution = false
        action = nil
        sessionIDs = []
        errorMessage = nil
    }

    private func performAction() async {
        do {
            guard owner() == expectedOwner else { throw TransitionError.ownerChanged }
            guard try activeSessions().isEmpty else { throw TransitionError.workoutsChanged }
            guard let action else { return }
            self.action = nil
            engine.isAccountTransitionInProgress = true
            defer { engine.isAccountTransitionInProgress = false }
            try await action()
        } catch { fail(error) }
    }

    private func activeSessions() throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.status == .active && !$0.isDeleted }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func fail(_ error: Error) {
        needsResolution = false
        action = nil
        errorMessage = error.localizedDescription
    }

    private enum TransitionError: LocalizedError {
        case hiddenWorkout, ownerChanged, workoutsChanged, pendingSetSave
        var errorDescription: String? {
            switch self {
            case .hiddenWorkout:
                "An unfinished workout from another account is saved on this iPhone. Sign into its account or discard it in Settings before continuing."
            case .ownerChanged:
                "The signed-in account changed. Review the current account and try again."
            case .workoutsChanged:
                "The unfinished workouts changed. Review them and try again."
            case .pendingSetSave:
                "A set could not be saved. Return to the workout to retry or discard that edit before continuing."
            }
        }
    }
}
