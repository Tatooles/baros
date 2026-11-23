import Foundation
import XCTest
@testable import BarosCore

/// The Watch writer rules from ADR 0005, "One writer per workout".
@MainActor
final class AppleHealthWatchWriterTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var recorder: WatchTestRecorder!
    private var watch: FakeWatchLink!
    private var source: WatchTestSnapshotSource!
    private var ledger: AppleHealthLedgerStore!
    private var settingEnabled = true
    private var now = Date(timeIntervalSince1970: 1_800_000_060)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let id = UUID()

    override func setUp() async throws {
        suiteName = "AppleHealthWatchWriterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        recorder = WatchTestRecorder()
        watch = FakeWatchLink()
        source = WatchTestSnapshotSource()
        ledger = AppleHealthLedgerStore(defaults: defaults)
        watch.ledger = ledger
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
            watchLink: watch,
            isSettingEnabled: { [unowned self] in settingEnabled },
            now: { [unowned self] in now }
        )
    }

    private func snapshot(
        _ status: AppleHealthWorkoutSnapshot.Status,
        endedAfter minutes: Double? = nil,
        isVisible: Bool = true
    ) -> AppleHealthWorkoutSnapshot {
        AppleHealthWorkoutSnapshot(
            workoutID: id, status: status, startedAt: start,
            endedAt: minutes.map { start.addingTimeInterval($0 * 60) },
            updatedAt: start.addingTimeInterval((minutes ?? 0) * 60),
            isDeleted: false, isVisible: isVisible
        )
    }

    private func startOnWatch(_ reconciler: AppleHealthWorkoutReconciler) async {
        source.snapshots = [snapshot(.active)]
        await reconciler.requestReconciliation().value
    }

    func testWatchIsRecordedAsTheWriterBeforeTheClaimIsSent() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)

        XCTAssertEqual(watch.claims.count, 1)
        XCTAssertEqual(watch.writerWhenClaimWasSent, .watch)
        XCTAssertTrue(recorder.liveIDs.isEmpty, "The iPhone never records a Watch-writer workout")
    }

    func testFinishSendsTheTokenAndOnlyTheAcknowledgementSavesIt() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)
        let token = watch.claims.first?.token

        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        await reconciler.requestReconciliation().value

        XCTAssertEqual(watch.commands, [.finish(workoutID: id, token: token!, endedAt: start.addingTimeInterval(50 * 60))])
        XCTAssertEqual(ledger.entry(for: id)?.phase, .awaitingWatch)

        reconciler.handleWatchAcknowledgement(workoutID: id, token: watch.claims.first!.token, outcome: .saved)

        XCTAssertEqual(ledger.entry(for: id)?.phase, .saved)
        XCTAssertEqual(recorder.saveAttempts, 0, "Watch or nothing: the iPhone never saves it")
    }

    func testPendingCommandIsResentUntilAcknowledged() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)
        source.snapshots = [snapshot(.completed, endedAfter: 50)]

        await reconciler.requestReconciliation().value
        await reconciler.requestReconciliation().value
        XCTAssertEqual(watch.commands.count, 2)

        reconciler.handleWatchAcknowledgement(workoutID: id, token: watch.claims.first!.token, outcome: .saved)
        await reconciler.requestReconciliation().value

        XCTAssertEqual(watch.commands.count, 2)
    }

    func testWatchNotReadyFallsBackToTheIPhone() async {
        watch.isReady = false
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)

        XCTAssertTrue(watch.claims.isEmpty)
        XCTAssertEqual(recorder.liveIDs, [id])
        XCTAssertEqual(ledger.entry(for: id)?.writer, .iPhone)
    }

    func testDiscardedWorkoutTellsTheWatchToDiscard() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)

        source.snapshots = [snapshot(.discarded)]
        await reconciler.requestReconciliation().value
        reconciler.handleWatchAcknowledgement(workoutID: id, token: watch.claims.first!.token, outcome: .discarded)

        XCTAssertEqual(watch.commands, [.discard(workoutID: id, token: watch.claims.first!.token)])
        XCTAssertEqual(ledger.entry(for: id)?.phase, .abandoned)
    }

    func testHiddenOwnerDiscardsTheWatchSession() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)

        source.snapshots = [snapshot(.active, isVisible: false)]
        await reconciler.requestReconciliation().value

        XCTAssertEqual(watch.commands, [.discard(workoutID: id, token: watch.claims.first!.token)])
    }

    func testSavedAcknowledgementWithoutAPendingFinishIsIgnored() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)

        reconciler.handleWatchAcknowledgement(workoutID: id, token: watch.claims.first!.token, outcome: .saved)

        XCTAssertEqual(ledger.entry(for: id)?.phase, .recording)
    }

    func testStatusRequests() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)

        let token = watch.claims.first!.token
        let stranger = UUID()
        XCTAssertEqual(reconciler.watchCommand(forStatusOf: stranger, token: token, isEndRequest: false),
                       .discard(workoutID: stranger, token: token))
        XCTAssertNil(reconciler.watchCommand(forStatusOf: id, token: token, isEndRequest: false), "After a relaunch, keep recording")
        XCTAssertEqual(reconciler.watchCommand(forStatusOf: id, token: token, isEndRequest: true), .discard(workoutID: id, token: token))
        XCTAssertEqual(ledger.entry(for: id)?.pendingWatchCommand, .discard(workoutID: id, token: token))
    }

    func testAcknowledgementForAnOldClaimIsIgnored() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)
        source.snapshots = [snapshot(.completed, endedAfter: 50)]
        await reconciler.requestReconciliation().value

        reconciler.handleWatchAcknowledgement(workoutID: id, token: UUID(), outcome: .discarded)

        XCTAssertEqual(ledger.entry(for: id)?.phase, .awaitingWatch)
    }

    func testLocalDataResetTellsAWatchWriterToDiscard() async {
        let reconciler = makeReconciler()
        await startOnWatch(reconciler)

        reconciler.prepareForLocalDataReset()

        XCTAssertEqual(watch.commands, [.discard(workoutID: id, token: watch.claims.first!.token)])
        XCTAssertTrue(ledger.entries.isEmpty)
    }

    func testEditsToAWatchSavedWorkoutAreNotPropagated() async {
        ledger.save(AppleHealthLedgerEntry(
            workoutID: id, writer: .watch, phase: .saved, lastWrittenStart: start,
            lastWrittenEnd: start.addingTimeInterval(50 * 60), isSaveConfirmed: true
        ))
        source.snapshots = [snapshot(.completed, endedAfter: 65)]
        let reconciler = makeReconciler()

        await reconciler.requestReconciliation().value

        XCTAssertEqual(recorder.saveAttempts, 0)
        XCTAssertTrue(watch.commands.isEmpty)
    }
}

@MainActor
private final class FakeWatchLink: AppleHealthWatchLinking {
    weak var ledger: AppleHealthLedgerStore?
    var isWatchAvailable = true
    var isReady = true
    var claims: [(workoutID: UUID, token: UUID)] = []
    var writerWhenClaimWasSent: AppleHealthLedgerEntry.Writer?
    var commands: [AppleHealthWatchCommand] = []

    func prepareWatchSession(workoutID: UUID) async -> Bool { isReady }

    func sendClaim(workoutID: UUID, startedAt: Date, token: UUID, syncVersion: Int64) async {
        writerWhenClaimWasSent = ledger?.entry(for: workoutID)?.writer
        claims.append((workoutID, token))
    }

    func send(_ command: AppleHealthWatchCommand) {
        commands.append(command)
    }
}

@MainActor
private final class WatchTestSnapshotSource: AppleHealthWorkoutSnapshotSource {
    var snapshots: [AppleHealthWorkoutSnapshot] = []

    func snapshots(includingWorkoutIDs workoutIDs: Set<UUID>) throws -> [AppleHealthWorkoutSnapshot] {
        snapshots.filter { $0.status == .active || workoutIDs.contains($0.workoutID) }
    }
}

@MainActor
private final class WatchTestRecorder: AppleHealthWorkoutRecording {
    var liveIDs: Set<UUID> = []
    var saveAttempts = 0

    func authorization() -> AppleHealthAuthorization { .authorized }
    func liveSessionWorkoutIDs() -> Set<UUID> { liveIDs }
    func startSession(workoutID: UUID, startedAt: Date, syncVersion: Int64) async throws(AppleHealthRecordingFailure) {
        liveIDs.insert(workoutID)
    }
    func finishSession(workoutID: UUID, endedAt: Date) async throws(AppleHealthRecordingFailure) -> AppleHealthSaveConfirmation {
        liveIDs.remove(workoutID)
        return .visible
    }
    func discardSession(workoutID: UUID) { liveIDs.remove(workoutID) }
    func savedWorkout(workoutID: UUID) async throws(AppleHealthRecordingFailure) -> AppleHealthSavedCopy? { nil }
    func saveWorkout(
        workoutID: UUID, startedAt: Date, endedAt: Date, syncVersion: Int64
    ) async throws(AppleHealthRecordingFailure) -> AppleHealthSaveConfirmation {
        saveAttempts += 1
        return .visible
    }
    func deleteSavedWorkout(workoutID: UUID) async throws(AppleHealthRecordingFailure) -> Int { 0 }
}
