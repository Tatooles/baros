import Foundation

/// Keeps Apple Health in step with committed Baros workouts (ADR 0005).
///
/// It reads snapshots, compares them with the ledger, and drives the recorder. It never writes Baros
/// records, and nothing in Baros waits on it, so a HealthKit failure can't change or block a workout.
@MainActor
public final class AppleHealthWorkoutReconciler {
    private let recorder: any AppleHealthWorkoutRecording
    private let watchLink: (any AppleHealthWatchLinking)?
    private let ledger: AppleHealthLedgerStore
    private let snapshotSource: any AppleHealthWorkoutSnapshotSource
    private let isSettingEnabled: () -> Bool
    private let now: () -> Date

    private var isPaused = false
    /// Bumped on every local-data reset, so a pass that started before the reset can't write the ledger.
    private var generation = 0
    private var isReconciliationPending = false
    private var drainTask: Task<Void, Never>?
    private var expiryTasks: [UUID: Task<Void, Never>] = [:]

    public init(
        recorder: any AppleHealthWorkoutRecording,
        ledger: AppleHealthLedgerStore,
        snapshotSource: any AppleHealthWorkoutSnapshotSource,
        watchLink: (any AppleHealthWatchLinking)? = nil,
        isSettingEnabled: @escaping () -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.watchLink = watchLink
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
        for id in recorder.liveSessionWorkoutIDs() {
            recorder.discardSession(workoutID: id)
        }
        // A Watch writer can't be ended from here: tell it to discard before its ledger entry goes.
        // WatchConnectivity keeps the command queued until the Watch receives it.
        for entry in ledger.entries.values where entry.writer == .watch && !entry.isTerminal && entry.phase != .saved {
            watchLink?.send(.discard(workoutID: entry.workoutID, token: entry.watchToken ?? entry.workoutID))
        }
        ledger.removeAll()
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
            now: now(),
            isWatchAvailable: watchLink?.isWatchAvailable ?? false
        )

        // A session recovered after a relaunch lost its age-limit timer: arm it for the time left.
        for workoutID in liveIDs where expiryTasks[workoutID] == nil {
            guard let startedAt = ledger.entry(for: workoutID)?.sessionStartedAt else { continue }
            let elapsed = environment.now.timeIntervalSince(startedAt)
            scheduleExpiryPass(for: workoutID, after: max(0, AppleHealthEnvironment.maximumSessionAge - elapsed))
        }

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
        case let .launchWatch(workoutID, startedAt, syncVersion):
            let isReady = await watchLink?.prepareWatchSession(workoutID: workoutID) ?? false
            guard isCurrent(passGeneration) else { return }
            guard isReady, let watchLink else {
                // A definite or timed-out failure before any claim: the iPhone records it instead.
                update(workoutID, passGeneration) { entry in
                    entry.writer = .iPhone
                    entry.phase = .recording
                }
                await perform(.startSession(workoutID: workoutID, startedAt: startedAt, syncVersion: syncVersion),
                              snapshot: snapshot, passGeneration: passGeneration)
                return
            }
            // Record the Watch as the writer before the claim leaves, so the iPhone can never also save it.
            let token = UUID()
            update(workoutID, passGeneration) { entry in
                entry.writer = .watch
                entry.phase = .recording
                entry.watchToken = token
            }
            await watchLink.sendClaim(workoutID: workoutID, startedAt: startedAt, token: token, syncVersion: syncVersion)

        case let .sendWatchCommand(command):
            watchLink?.send(command)

        case let .startSession(workoutID, startedAt, syncVersion):
            do {
                try await recorder.startSession(workoutID: workoutID, startedAt: startedAt, syncVersion: syncVersion)
                scheduleExpiryPass(for: workoutID, after: AppleHealthEnvironment.maximumSessionAge)
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
                let confirmation = try await recorder.finishSession(workoutID: workoutID, endedAt: endedAt)
                update(workoutID, passGeneration) { entry in
                    entry.phase = .saved
                    entry.isSaveConfirmed = confirmation == .visible
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

        case let .replaceSavedWorkout(workoutID, startedAt, endedAt, syncVersion):
            do {
                let existing = try await recorder.savedWorkout(workoutID: workoutID)
                guard isCurrent(passGeneration), isSettingEnabled() else { return }
                guard let existing else {
                    // After a confirmed save, a missing copy means the person deleted it in Health.
                    // Otherwise (saved while locked) it may not be readable yet: retry later.
                    update(workoutID, passGeneration) { entry in
                        if entry.isSaveConfirmed { entry.phase = .removedInHealth }
                    }
                    return
                }
                if existing.startedAt == startedAt, existing.endedAt == endedAt {
                    // The replacement already landed (for example, before a crash): adopt it.
                    update(workoutID, passGeneration) { entry in
                        entry.isSaveConfirmed = true
                        entry.lastWrittenVersion = existing.syncVersion ?? entry.lastWrittenVersion
                        entry.lastWrittenStart = startedAt
                        entry.lastWrittenEnd = endedAt
                    }
                    return
                }
                let version = max(syncVersion, (existing.syncVersion ?? 0) + 1)
                let confirmation = try await recorder.saveWorkout(
                    workoutID: workoutID,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    syncVersion: version
                )
                update(workoutID, passGeneration) { entry in
                    entry.isSaveConfirmed = confirmation == .visible
                    entry.lastWrittenVersion = version
                    entry.lastWrittenStart = startedAt
                    entry.lastWrittenEnd = endedAt
                }
            } catch {
                guard error == .terminal else { return } // Retried on the next pass.
                update(workoutID, passGeneration) { entry in
                    entry.phase = .abandoned
                }
            }

        case let .deleteSavedWorkout(workoutID):
            let isFirstAttempt = ledger.entry(for: workoutID)?.phase == .saved
            do {
                if isFirstAttempt {
                    // Confirm the copy exists before deleting, and record the pending delete, so a delete
                    // interrupted by a crash is never mistaken for one the person made in Health.
                    let existing = try await recorder.savedWorkout(workoutID: workoutID)
                    guard isCurrent(passGeneration) else { return }
                    guard existing != nil else {
                        update(workoutID, passGeneration) { entry in
                            // Already gone: the person deleted it in Health first. Never bring it back.
                            // A copy saved while locked may not be readable yet: retry on a later pass.
                            if entry.isSaveConfirmed { entry.phase = .removedInHealth }
                        }
                        return
                    }
                    update(workoutID, passGeneration) { $0.phase = .deletingWithWorkout }
                }
                let deletedCount = try await recorder.deleteSavedWorkout(workoutID: workoutID)
                update(workoutID, passGeneration) { entry in
                    // Zero on the first attempt: the person deleted it in Health after the lookup. Zero
                    // when resuming a recorded delete: Baros deleted it before a crash.
                    entry.phase = deletedCount == 0 && isFirstAttempt ? .removedInHealth : .deletedWithWorkout
                }
            } catch {
                update(workoutID, passGeneration) { entry in
                    if error == .terminal {
                        entry.phase = .abandoned
                    } else if isFirstAttempt {
                        // HealthKit answered: this first delete didn't happen. Look the copy up again next time.
                        entry.phase = .saved
                    }
                    // Resuming an interrupted delete: an earlier attempt may have succeeded, so keep the record.
                }
            }

        case let .discardSession(workoutID):
            recorder.discardSession(workoutID: workoutID)

        case let .saveWorkout(workoutID, startedAt, endedAt, syncVersion):
            do {
                let phase = ledger.entry(for: workoutID)?.phase
                let isRestoring = phase == .deletingWithWorkout || phase == .deletedWithWorkout
                if let existing = try await recorder.savedWorkout(workoutID: workoutID) {
                    update(workoutID, passGeneration) { entry in
                        entry.phase = .saved
                        entry.isSaveConfirmed = true
                        entry.lastWrittenVersion = existing.syncVersion ?? entry.lastWrittenVersion
                        entry.lastWrittenStart = existing.startedAt
                        entry.lastWrittenEnd = existing.endedAt
                    }
                    if isRestoring, existing.startedAt != startedAt || existing.endedAt != endedAt {
                        // A restore found a surviving copy with other times: replace it on the next pass.
                        requestReconciliation()
                    }
                    return
                }
                // The lookup can wait; the setting, permission, or a reset may have changed meanwhile.
                guard isCurrent(passGeneration) else { return }
                guard isSettingEnabled(), recorder.authorization() == .authorized else {
                    // Finished while writing was off: never written, as in the policy.
                    update(workoutID, passGeneration) { entry in
                        entry.writer = .none
                        entry.phase = .abandoned
                    }
                    return
                }
                let confirmation = try await recorder.saveWorkout(
                    workoutID: workoutID,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    syncVersion: syncVersion
                )
                update(workoutID, passGeneration) { entry in
                    entry.phase = .saved
                    entry.isSaveConfirmed = confirmation == .visible
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

    /// The Watch carried out a command. Only an acknowledgement for the pending command counts.
    public func handleWatchAcknowledgement(workoutID: UUID, token: UUID, outcome: AppleHealthWatchOutcome) {
        // Only the current claim's acknowledgement counts; a delayed one for an old claim is ignored.
        guard
            !isPaused,
            var entry = ledger.entry(for: workoutID),
            entry.writer == .watch,
            entry.watchToken == token
        else { return }
        switch outcome {
        case .saved, .savedWhileLocked:
            guard case .finish = entry.pendingWatchCommand else { return }
            entry.phase = .saved
            entry.isSaveConfirmed = outcome == .saved
        case .discarded, .failed:
            entry.phase = .abandoned
        }
        entry.pendingWatchCommand = nil
        ledger.save(entry)
    }

    /// What the Watch should do with its session, when it asks (after a relaunch, or from its End button).
    /// `nil` means keep recording. A workout the iPhone doesn't know is discarded.
    public func watchCommand(forStatusOf workoutID: UUID, token: UUID, isEndRequest: Bool) -> AppleHealthWatchCommand? {
        guard var entry = ledger.entry(for: workoutID), entry.writer == .watch, entry.watchToken == token else {
            // A session for a workout or claim the iPhone doesn't know: it can never be saved.
            return .discard(workoutID: workoutID, token: token)
        }
        if let pending = entry.pendingWatchCommand { return pending }
        let isActive = (try? snapshotSource.snapshots(includingWorkoutIDs: [workoutID]))?
            .first { $0.workoutID == workoutID }?.status == .active
        guard isEndRequest || !isActive else { return nil }
        guard isActive else {
            // Not active any more: the next pass decides finish or discard.
            requestReconciliation()
            return nil
        }
        // Ended on the Watch while the Baros workout continues: this workout gets no Health copy.
        let command = AppleHealthWatchCommand.discard(workoutID: workoutID, token: token)
        entry.pendingWatchCommand = command
        entry.phase = .awaitingWatch
        ledger.save(entry)
        return command
    }

    /// One pass just after the new session reaches its age limit, even if nothing else changes.
    private func scheduleExpiryPass(for workoutID: UUID, after delay: TimeInterval) {
        expiryTasks[workoutID]?.cancel()
        expiryTasks[workoutID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + 1))
            guard !Task.isCancelled, let self else { return }
            expiryTasks[workoutID] = nil
            guard recorder.liveSessionWorkoutIDs().contains(workoutID) else { return }
            requestReconciliation()
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

extension AppleHealthWorkoutReconciler: LocalDataResetObserving {
    public func localDataResetWillBegin() {
        prepareForLocalDataReset()
    }

    public func localDataResetDidEnd() {
        resumeAfterLocalDataReset()
    }
}
