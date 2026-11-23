import Foundation
import XCTest
@testable import BarosCore

@MainActor
final class AppleHealthWorkoutReconcilerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var recorder: FakeAppleHealthRecorder!
    private var source: FakeSnapshotSource!
    private var ledger: AppleHealthLedgerStore!
    private var settingEnabled = true
    private var now = Date(timeIntervalSince1970: 1_800_000_060)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let id = UUID()

    override func setUp() async throws {
        suiteName = "AppleHealthWorkoutReconcilerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        recorder = FakeAppleHealthRecorder()
        source = FakeSnapshotSource()
        ledger = AppleHealthLedgerStore(defaults: defaults)
        settingEnabled = true
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeReconciler() -> AppleHealthWorkoutReconciler {
        AppleHealthWorkoutReconciler(
            recorder: recorder,
            ledger: ledger,
            snapshotSource: source,
            isSettingEnabled: { [unowned self] in settingEnabled },
            now: { [unowned self] in now }
        )
    }

    private func snapshot(_ status: AppleHealthWorkoutSnapshot.Status, endedAfter minutes: Double? = nil) -> AppleHealthWorkoutSnapshot {
        AppleHealthWorkoutSnapshot(
            workoutID: id,
            status: status,
            startedAt: start,
            endedAt: minutes.map { start.addingTimeInterval($0 * 60) },
            updatedAt: start.addingTimeInterval((minutes ?? 0) * 60),
            isDeleted: false,
            isVisible: true
        )
    }

    func testStartThenFinishSavesExactlyOneWorkout() async {
        let reconciler = makeReconciler()
        source.snapshots = [snapshot(.active)]
        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.liveIDs, [id])
        XCTAssertEqual(ledger.entry(for: id)?.phase, .recording)

        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        now = start.addingTimeInterval(51 * 60)
        await reconciler.requestReconciliation().value
        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.finishedIDs, [id])
        XCTAssertTrue(recorder.fallbackSaves.isEmpty)
        XCTAssertEqual(ledger.entry(for: id)?.phase, .saved)
        XCTAssertEqual(ledger.entry(for: id)?.isSaveConfirmed, true)
    }

    func testTransientFinishFailureFallsBackWithoutDuplicating() async {
        let reconciler = makeReconciler()
        source.snapshots = [snapshot(.active)]
        await reconciler.requestReconciliation().value

        // HealthKit saved the workout but reported a failure, so Baros never recorded the save.
        recorder.finishFailure = .transient
        recorder.finishSavesDespiteFailure = true
        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        await reconciler.requestReconciliation().value
        XCTAssertEqual(ledger.entry(for: id)?.phase, .sessionLost)

        await reconciler.requestReconciliation().value

        XCTAssertTrue(recorder.fallbackSaves.isEmpty, "The existing copy must be found, not saved again")
        XCTAssertEqual(ledger.entry(for: id)?.phase, .saved)
    }

    func testTransientFallbackFailureRetriesOnTheNextPass() async {
        ledger.save(AppleHealthLedgerEntry(workoutID: id, writer: .iPhone, phase: .sessionLost))
        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        recorder.saveFailure = .transient
        let reconciler = makeReconciler()

        await reconciler.requestReconciliation().value
        XCTAssertEqual(ledger.entry(for: id)?.phase, .sessionLost)

        recorder.saveFailure = nil
        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.fallbackSaves.count, 1)
        XCTAssertEqual(ledger.entry(for: id)?.phase, .saved)
    }

    func testTerminalSaveFailureStopsRetrying() async {
        ledger.save(AppleHealthLedgerEntry(workoutID: id, writer: .iPhone, phase: .sessionLost))
        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        recorder.saveFailure = .terminal
        let reconciler = makeReconciler()

        await reconciler.requestReconciliation().value
        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.saveAttempts, 1)
        XCTAssertEqual(ledger.entry(for: id)?.writer, AppleHealthLedgerEntry.Writer.none)
        XCTAssertEqual(ledger.entry(for: id)?.phase, .abandoned)
    }

    func testFailedStartStillSavesWithTheFallbackAtFinish() async {
        recorder.startFailure = .transient
        source.snapshots = [snapshot(.active)]
        let reconciler = makeReconciler()
        await reconciler.requestReconciliation().value
        XCTAssertEqual(ledger.entry(for: id)?.phase, .sessionLost)

        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.fallbackSaves.count, 1)
        XCTAssertEqual(ledger.entry(for: id)?.phase, .saved)
    }

    func testDiscardedWorkoutSavesNothing() async {
        let reconciler = makeReconciler()
        source.snapshots = [snapshot(.active)]
        await reconciler.requestReconciliation().value

        source.snapshots = [snapshot(.discarded)]
        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.discardedIDs, [id])
        XCTAssertTrue(recorder.liveIDs.isEmpty)
        XCTAssertTrue(recorder.savedIDs.isEmpty)
        XCTAssertEqual(ledger.entry(for: id)?.phase, .abandoned)
    }

    func testFailedSnapshotFetchChangesNothing() async {
        let reconciler = makeReconciler()
        source.snapshots = [snapshot(.active)]
        await reconciler.requestReconciliation().value
        let before = ledger.entry(for: id)

        source.error = FakeSnapshotSource.Failure()
        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.liveIDs, [id], "A failed fetch must not look like a missing row")
        XCTAssertTrue(recorder.discardedIDs.isEmpty)
        XCTAssertEqual(ledger.entry(for: id), before)
    }

    func testLocalDataResetDiscardsSessionsClearsTheLedgerAndKeepsSavedCopies() async {
        let saved = UUID()
        recorder.savedIDs = [saved]
        ledger.save(AppleHealthLedgerEntry(workoutID: saved, writer: .iPhone, phase: .saved, isSaveConfirmed: true))
        let reconciler = makeReconciler()
        source.snapshots = [snapshot(.active)]
        await reconciler.requestReconciliation().value

        reconciler.prepareForLocalDataReset()
        XCTAssertTrue(ledger.entries.isEmpty)

        // Rows are gone after the reset. Passes while paused do nothing.
        source.snapshots = []
        await reconciler.requestReconciliation().value
        reconciler.resumeAfterLocalDataReset()
        await reconciler.requestReconciliation().value

        XCTAssertTrue(recorder.liveIDs.isEmpty)
        XCTAssertEqual(recorder.savedIDs, [saved], "Saved Health copies stay after a reset")
        XCTAssertTrue(ledger.entries.isEmpty)
    }

    func testExistingCopyRecordsWhatHealthActuallyHolds() async {
        ledger.save(AppleHealthLedgerEntry(workoutID: id, writer: .iPhone, phase: .sessionLost, lastWrittenVersion: 1))
        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        let copy = AppleHealthSavedCopy(syncVersion: 9_999_999_999_999, startedAt: start, endedAt: start.addingTimeInterval(45 * 60))
        recorder.existingCopies[id] = copy
        let reconciler = makeReconciler()

        await reconciler.requestReconciliation().value

        XCTAssertTrue(recorder.fallbackSaves.isEmpty)
        XCTAssertEqual(ledger.entry(for: id)?.lastWrittenVersion, copy.syncVersion)
        XCTAssertEqual(ledger.entry(for: id)?.lastWrittenEnd, copy.endedAt)
    }

    func testSaveOnALockedPhoneIsSavedButNotConfirmed() async {
        ledger.save(AppleHealthLedgerEntry(workoutID: id, writer: .iPhone, phase: .sessionLost))
        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        recorder.saveConfirmation = .savedWhileLocked
        let reconciler = makeReconciler()

        await reconciler.requestReconciliation().value

        XCTAssertEqual(ledger.entry(for: id)?.phase, .saved)
        XCTAssertEqual(ledger.entry(for: id)?.isSaveConfirmed, false)
    }

    func testTurningTheSettingOffDuringTheLookupStopsTheFallbackSave() async {
        ledger.save(AppleHealthLedgerEntry(workoutID: id, writer: .iPhone, phase: .sessionLost))
        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        recorder.onLookup = { [unowned self] in settingEnabled = false }
        let reconciler = makeReconciler()

        await reconciler.requestReconciliation().value
        recorder.onLookup = nil
        settingEnabled = true
        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.saveAttempts, 0, "Turning the setting back on later must not export it")
        XCTAssertEqual(ledger.entry(for: id)?.phase, .abandoned)
    }

    func testResetDuringTheLookupStopsTheFallbackSave() async {
        ledger.save(AppleHealthLedgerEntry(workoutID: id, writer: .iPhone, phase: .sessionLost))
        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        let reconciler = makeReconciler()
        recorder.onLookup = { reconciler.prepareForLocalDataReset() }

        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.saveAttempts, 0)
        XCTAssertTrue(ledger.entries.isEmpty)
    }

    func testLedgerSurvivesRelaunch() async {
        let reconciler = makeReconciler()
        source.snapshots = [snapshot(.active)]
        await reconciler.requestReconciliation().value

        let reloaded = AppleHealthLedgerStore(defaults: defaults)

        XCTAssertEqual(reloaded.entry(for: id), ledger.entry(for: id))
    }

    func testCorruptLedgerLoadsEmpty() {
        defaults.set(Data("not json".utf8), forKey: AppleHealthLedgerStore.standardKey)

        XCTAssertTrue(AppleHealthLedgerStore(defaults: defaults).entries.isEmpty)
    }
}

@MainActor
private final class FakeSnapshotSource: AppleHealthWorkoutSnapshotSource {
    struct Failure: Error {}

    var snapshots: [AppleHealthWorkoutSnapshot] = []
    var error: Failure?

    func snapshots(includingWorkoutIDs workoutIDs: Set<UUID>) throws -> [AppleHealthWorkoutSnapshot] {
        if let error { throw error }
        return snapshots.filter { $0.status == .active || workoutIDs.contains($0.workoutID) }
    }
}

@MainActor
private final class FakeAppleHealthRecorder: AppleHealthWorkoutRecording {
    var authorizationStatus: AppleHealthAuthorization = .authorized
    var liveIDs: Set<UUID> = []
    var savedIDs: Set<UUID> = []
    var finishedIDs: [UUID] = []
    var discardedIDs: [UUID] = []
    var fallbackSaves: [UUID] = []
    var saveAttempts = 0
    var startFailure: AppleHealthRecordingFailure?
    var finishFailure: AppleHealthRecordingFailure?
    var finishSavesDespiteFailure = false
    var saveFailure: AppleHealthRecordingFailure?
    var saveConfirmation: AppleHealthSaveConfirmation = .visible
    var existingCopies: [UUID: AppleHealthSavedCopy] = [:]
    var onLookup: (() -> Void)?

    func authorization() -> AppleHealthAuthorization { authorizationStatus }

    func liveSessionWorkoutIDs() -> Set<UUID> { liveIDs }

    func startSession(workoutID: UUID, startedAt: Date, syncVersion: Int64) async throws(AppleHealthRecordingFailure) {
        if let startFailure { throw startFailure }
        liveIDs.insert(workoutID)
    }

    func finishSession(workoutID: UUID, endedAt: Date) async throws(AppleHealthRecordingFailure) -> AppleHealthSaveConfirmation {
        // The session always ends after one attempt, even when the save fails.
        liveIDs.remove(workoutID)
        finishedIDs.append(workoutID)
        if let finishFailure {
            if finishSavesDespiteFailure { savedIDs.insert(workoutID) }
            throw finishFailure
        }
        savedIDs.insert(workoutID)
        return .visible
    }

    func discardSession(workoutID: UUID) async {
        liveIDs.remove(workoutID)
        discardedIDs.append(workoutID)
    }

    func savedWorkout(workoutID: UUID) async throws(AppleHealthRecordingFailure) -> AppleHealthSavedCopy? {
        onLookup?()
        if let copy = existingCopies[workoutID] { return copy }
        return savedIDs.contains(workoutID) ? AppleHealthSavedCopy(syncVersion: nil, startedAt: .distantPast, endedAt: .distantPast) : nil
    }

    func saveWorkout(
        workoutID: UUID,
        startedAt: Date,
        endedAt: Date,
        syncVersion: Int64
    ) async throws(AppleHealthRecordingFailure) -> AppleHealthSaveConfirmation {
        saveAttempts += 1
        if let saveFailure { throw saveFailure }
        fallbackSaves.append(workoutID)
        savedIDs.insert(workoutID)
        return saveConfirmation
    }
}
