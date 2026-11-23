import Foundation

/// Keeps Apple Health in step with committed Baros workouts (ADR 0005).
///
/// It reads snapshots, compares them with the ledger, and drives the recorder. It never writes Baros
/// records, and nothing in Baros waits on it, so a HealthKit failure can't change or block a workout.
@MainActor
public final class AppleHealthWorkoutReconciler {
    private let recorder: any AppleHealthWorkoutRecording
    private let ledger: AppleHealthLedgerStore
    private let snapshotSource: any AppleHealthWorkoutSnapshotSource
    private let isSettingEnabled: () -> Bool
    private let now: () -> Date

    private var isPaused = false
    /// Bumped on every local-data reset, so a pass that started before the reset can't write the ledger.
    private var generation = 0
    private var isReconciliationPending = false
    private var drainTask: Task<Void, Never>?

    public init(
        recorder: any AppleHealthWorkoutRecording,
        ledger: AppleHealthLedgerStore,
        snapshotSource: any AppleHealthWorkoutSnapshotSource,
        isSettingEnabled: @escaping () -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.ledger = ledger
        self.snapshotSource = snapshotSource
        self.isSettingEnabled = isSettingEnabled
        self.now = now
    }

    /// Asks for a pass. Requests made while a pass runs are coalesced into one more pass.
    @discardableResult
    public func requestReconciliation() -> Task<Void, Never> {
        isReconciliationPending = true
        if let drainTask { return drainTask }
        let task = Task { [weak self] in
            guard let self else { return }
            await drain()
        }
        drainTask = task
        return task
    }

    /// Called by local-data reset before it deletes rows. It never throws or waits: it stops further
    /// passes, discards live sessions, and clears the ledger. Saved Health copies stay (ADR 0005).
    public func prepareForLocalDataReset() {
        isPaused = true
        generation += 1
        let liveIDs = recorder.liveSessionWorkoutIDs()
        ledger.removeAll()
        let recorder = recorder
        Task {
            for id in liveIDs {
                await recorder.discardSession(workoutID: id)
            }
        }
    }

    /// Called after local-data reset finishes, whether it succeeded or rolled back.
    public func resumeAfterLocalDataReset() {
        isPaused = false
        requestReconciliation()
    }

    private func drain() async {
        while isReconciliationPending {
            isReconciliationPending = false
            await runPass()
        }
        drainTask = nil
    }

    private func runPass() async {
        guard !isPaused else { return }
        let passGeneration = generation
        let liveIDs = recorder.liveSessionWorkoutIDs()
        let trackedIDs = Set(ledger.entries.keys).union(liveIDs)

        let snapshots: [AppleHealthWorkoutSnapshot]
        do {
            snapshots = try snapshotSource.snapshots(includingWorkoutIDs: trackedIDs)
        } catch {
            // Unknown state isn't "missing": leave every session and entry as it is.
            return
        }
        let snapshotsByID = Dictionary(snapshots.map { ($0.workoutID, $0) }, uniquingKeysWith: { first, _ in first })
        let environment = AppleHealthEnvironment(
            isSettingEnabled: isSettingEnabled(),
            authorization: recorder.authorization(),
            now: now()
        )

        for workoutID in trackedIDs.union(snapshotsByID.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
            guard isCurrent(passGeneration) else { return }
            let decision = AppleHealthWorkoutPolicy.decide(
                workoutID: workoutID,
                snapshot: snapshotsByID[workoutID],
                entry: ledger.entry(for: workoutID),
                hasLiveSession: liveIDs.contains(workoutID),
                environment: environment
            )
            if let entry = decision.entry {
                ledger.save(entry)
            }
            guard let action = decision.action else { continue }
            await perform(action, snapshot: snapshotsByID[workoutID], passGeneration: passGeneration)
        }
    }

    private func perform(
        _ action: AppleHealthWorkoutAction,
        snapshot: AppleHealthWorkoutSnapshot?,
        passGeneration: Int
    ) async {
        switch action {
        case let .startSession(workoutID, startedAt, syncVersion):
            do {
                try await recorder.startSession(workoutID: workoutID, startedAt: startedAt, syncVersion: syncVersion)
            } catch {
                update(workoutID, passGeneration) { entry in
                    if error == .terminal {
                        entry.writer = .none
                        entry.phase = .abandoned
                    } else {
                        entry.phase = .sessionLost
                    }
                }
            }

        case let .finishSession(workoutID, endedAt):
            do {
                try await recorder.finishSession(workoutID: workoutID, endedAt: endedAt)
                update(workoutID, passGeneration) { entry in
                    entry.phase = .saved
                    entry.isSaveConfirmed = true
                    entry.lastWrittenStart = snapshot?.startedAt
                    entry.lastWrittenEnd = endedAt
                }
            } catch {
                update(workoutID, passGeneration) { entry in
                    if error == .terminal {
                        entry.writer = .none
                        entry.phase = .abandoned
                    } else {
                        // The session has ended. The next pass checks Health, then saves with the fallback.
                        entry.phase = .sessionLost
                    }
                }
            }

        case let .discardSession(workoutID):
            await recorder.discardSession(workoutID: workoutID)

        case let .saveWorkout(workoutID, startedAt, endedAt, syncVersion):
            do {
                let alreadySaved = try await recorder.savedWorkoutExists(workoutID: workoutID)
                if !alreadySaved {
                    try await recorder.saveWorkout(
                        workoutID: workoutID,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        syncVersion: syncVersion
                    )
                }
                update(workoutID, passGeneration) { entry in
                    entry.phase = .saved
                    entry.isSaveConfirmed = true
                    entry.lastWrittenVersion = syncVersion
                    entry.lastWrittenStart = startedAt
                    entry.lastWrittenEnd = endedAt
                }
            } catch {
                guard error == .terminal else { return } // Retried on the next pass.
                update(workoutID, passGeneration) { entry in
                    entry.writer = .none
                    entry.phase = .abandoned
                }
            }
        }
    }

    private func update(
        _ workoutID: UUID,
        _ passGeneration: Int,
        _ change: (inout AppleHealthLedgerEntry) -> Void
    ) {
        guard isCurrent(passGeneration), var entry = ledger.entry(for: workoutID) else { return }
        change(&entry)
        ledger.save(entry)
    }

    private func isCurrent(_ passGeneration: Int) -> Bool {
        !isPaused && generation == passGeneration
    }
}
