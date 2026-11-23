import Foundation
import XCTest
@testable import BarosCore

final class AppleHealthWorkoutPolicyTests: XCTestCase {
    private let id = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        _ status: AppleHealthWorkoutSnapshot.Status,
        endedAfter minutes: Double? = nil,
        updatedAfter updatedMinutes: Double = 0,
        isDeleted: Bool = false,
        isVisible: Bool = true
    ) -> AppleHealthWorkoutSnapshot {
        AppleHealthWorkoutSnapshot(
            workoutID: id,
            status: status,
            startedAt: start,
            endedAt: minutes.map { start.addingTimeInterval($0 * 60) },
            updatedAt: start.addingTimeInterval(updatedMinutes * 60),
            isDeleted: isDeleted,
            isVisible: isVisible
        )
    }

    private func environment(
        minutesAfterStart: Double = 1,
        settingEnabled: Bool = true,
        authorization: AppleHealthAuthorization = .authorized
    ) -> AppleHealthEnvironment {
        AppleHealthEnvironment(
            isSettingEnabled: settingEnabled,
            authorization: authorization,
            now: start.addingTimeInterval(minutesAfterStart * 60)
        )
    }

    private func entry(
        writer: AppleHealthLedgerEntry.Writer,
        phase: AppleHealthLedgerEntry.Phase,
        sessionStartedAt: Date? = nil,
        lastWrittenVersion: Int64? = nil
    ) -> AppleHealthLedgerEntry {
        AppleHealthLedgerEntry(
            workoutID: id,
            writer: writer,
            phase: phase,
            sessionStartedAt: sessionStartedAt,
            lastWrittenVersion: lastWrittenVersion
        )
    }

    private func decide(
        _ snapshot: AppleHealthWorkoutSnapshot?,
        entry: AppleHealthLedgerEntry? = nil,
        live: Bool = false,
        _ environment: AppleHealthEnvironment
    ) -> AppleHealthWorkoutDecision {
        AppleHealthWorkoutPolicy.decide(
            workoutID: id,
            snapshot: snapshot,
            entry: entry,
            hasLiveSession: live,
            environment: environment
        )
    }

    // MARK: Active

    func testNewActiveWorkoutRecordsTheWriterAndStartsASessionAtItsStart() {
        let decision = decide(snapshot(.active), environment())

        let version = AppleHealthSyncVersion.next(updatedAt: start, lastWritten: nil)
        XCTAssertEqual(decision.action, .startSession(workoutID: id, startedAt: start, syncVersion: version))
        XCTAssertEqual(decision.entry?.writer, .iPhone)
        XCTAssertEqual(decision.entry?.phase, .recording)
        XCTAssertEqual(decision.entry?.lastWrittenVersion, version)
    }

    func testActiveWorkoutWithSettingOffIsObservedWithoutASession() {
        let decision = decide(snapshot(.active), environment(settingEnabled: false))

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry, AppleHealthLedgerEntry(workoutID: id))
    }

    func testTurningTheSettingOnMidWorkoutWaitsForTheFallback() {
        // First seen with the setting off, then the setting is turned on a minute later.
        let observed = AppleHealthLedgerEntry(workoutID: id)
        let decision = decide(snapshot(.active), entry: observed, environment(minutesAfterStart: 2))

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry, observed)
    }

    func testActiveWorkoutSeenAfterTheStartWindowWaitsForTheFallback() {
        let decision = decide(snapshot(.active), environment(minutesAfterStart: 30))

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry?.phase, .observed)
        XCTAssertEqual(decision.entry?.writer, .undecided)
    }

    func testHiddenActiveWorkoutDoesNotStartASession() {
        let decision = decide(snapshot(.active, isVisible: false), environment())

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry?.phase, .observed)
    }

    func testRunningSessionIsLeftAlone() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(snapshot(.active), entry: recording, live: true, environment(minutesAfterStart: 40))

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry, recording)
    }

    func testHidingTheOwnerDiscardsTheSessionAndKeepsTheFallback() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(snapshot(.active, isVisible: false), entry: recording, live: true, environment())

        XCTAssertEqual(decision.action, .discardSession(workoutID: id))
        XCTAssertEqual(decision.entry?.phase, .sessionLost)
        XCTAssertEqual(decision.entry?.writer, .iPhone)
    }

    func testSessionPastTheMaximumAgeIsDiscardedAndKeepsTheFallback() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let minutes = AppleHealthEnvironment.maximumSessionAge / 60 + 1
        let decision = decide(snapshot(.active), entry: recording, live: true, environment(minutesAfterStart: minutes))

        XCTAssertEqual(decision.action, .discardSession(workoutID: id))
        XCTAssertEqual(decision.entry?.phase, .sessionLost)
    }

    func testSessionThatEndedOnItsOwnIsMarkedLost() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(snapshot(.active), entry: recording, live: false, environment())

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry?.phase, .sessionLost)
    }

    func testTurningTheSettingOffMidWorkoutDiscardsAndWritesNothing() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(snapshot(.active), entry: recording, live: true, environment(settingEnabled: false))

        XCTAssertEqual(decision.action, .discardSession(workoutID: id))
        XCTAssertEqual(decision.entry?.writer, AppleHealthLedgerEntry.Writer.none)
        XCTAssertEqual(decision.entry?.phase, .abandoned)
    }

    func testRevokedPermissionMidWorkoutDiscardsAndWritesNothing() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(snapshot(.active), entry: recording, live: true, environment(authorization: .denied))

        XCTAssertEqual(decision.action, .discardSession(workoutID: id))
        XCTAssertEqual(decision.entry?.phase, .abandoned)
    }

    // MARK: Completed

    func testCompletedWorkoutWithALiveSessionFinishesItAtTheBarosEndTime() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(snapshot(.completed, endedAfter: 50), entry: recording, live: true, environment(minutesAfterStart: 51))

        XCTAssertEqual(decision.action, .finishSession(workoutID: id, endedAt: start.addingTimeInterval(50 * 60)))
        XCTAssertEqual(decision.entry, recording)
    }

    func testCompletedWorkoutWithoutASessionUsesTheFallbackSave() {
        let lost = entry(writer: .iPhone, phase: .sessionLost, sessionStartedAt: start, lastWrittenVersion: 5)
        let completed = snapshot(.completed, endedAfter: 50, updatedAfter: 50)
        let decision = decide(completed, entry: lost, environment(minutesAfterStart: 51))

        let version = AppleHealthSyncVersion.next(updatedAt: completed.updatedAt, lastWritten: 5)
        XCTAssertEqual(
            decision.action,
            .saveWorkout(workoutID: id, startedAt: start, endedAt: start.addingTimeInterval(50 * 60), syncVersion: version)
        )
        XCTAssertEqual(decision.entry?.writer, .iPhone)
    }

    func testWorkoutStartedBeforeTheSettingWasTurnedOnIsSavedAtFinish() {
        let observed = AppleHealthLedgerEntry(workoutID: id)
        let decision = decide(snapshot(.completed, endedAfter: 50), entry: observed, environment(minutesAfterStart: 51))

        guard case .saveWorkout = decision.action else {
            return XCTFail("Expected a fallback save, got \(String(describing: decision.action))")
        }
        XCTAssertEqual(decision.entry?.writer, .iPhone)
    }

    func testWorkoutFinishedWithTheSettingOffIsNeverWritten() {
        let observed = AppleHealthLedgerEntry(workoutID: id)
        let decision = decide(snapshot(.completed, endedAfter: 50), entry: observed, environment(settingEnabled: false))

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry?.phase, .abandoned)
    }

    func testCompletedWorkoutThatArrivedBySyncIsNeverTracked() {
        let decision = decide(snapshot(.completed, endedAfter: 50), environment(minutesAfterStart: 51))

        XCTAssertNil(decision.entry)
        XCTAssertNil(decision.action)
    }

    // MARK: Discarded, deleted, missing

    func testDiscardedWorkoutDiscardsTheSessionAndSavesNothing() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(snapshot(.discarded), entry: recording, live: true, environment())

        XCTAssertEqual(decision.action, .discardSession(workoutID: id))
        XCTAssertEqual(decision.entry?.phase, .abandoned)
    }

    func testTombstonedActiveWorkoutDiscardsTheSession() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(snapshot(.active, isDeleted: true), entry: recording, live: true, environment())

        XCTAssertEqual(decision.action, .discardSession(workoutID: id))
        XCTAssertEqual(decision.entry?.phase, .abandoned)
    }

    func testMissingRowOnlyDiscardsTheLiveSession() {
        let recording = entry(writer: .iPhone, phase: .recording, sessionStartedAt: start)
        let decision = decide(nil, entry: recording, live: true, environment())

        XCTAssertEqual(decision.action, .discardSession(workoutID: id))
        XCTAssertEqual(decision.entry?.phase, .abandoned)
    }

    func testMissingRowNeverTouchesASavedCopy() {
        let saved = entry(writer: .iPhone, phase: .saved)
        let decision = decide(nil, entry: saved, environment())

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry, saved)
    }

    func testUntrackedLiveSessionIsDiscarded() {
        let decision = decide(nil, live: true, environment())

        XCTAssertNil(decision.entry)
        XCTAssertEqual(decision.action, .discardSession(workoutID: id))
    }

    func testWriterNoneIsTerminal() {
        let abandoned = entry(writer: .none, phase: .abandoned)
        let decision = decide(snapshot(.completed, endedAfter: 50), entry: abandoned, environment(minutesAfterStart: 51))

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry, abandoned)
    }

    // MARK: Recovery, edits, and deletes (#462)

    private func saved(start savedStart: Date? = nil, end: Date? = nil, version: Int64 = 1) -> AppleHealthLedgerEntry {
        AppleHealthLedgerEntry(
            workoutID: id, writer: .iPhone, phase: .saved, lastWrittenVersion: version,
            lastWrittenStart: savedStart ?? start, lastWrittenEnd: end ?? start.addingTimeInterval(50 * 60),
            isSaveConfirmed: true
        )
    }

    func testRecoveredSessionIsAdoptedAgainWhileActive() {
        let lost = entry(writer: .iPhone, phase: .sessionLost, sessionStartedAt: start)
        let decision = decide(snapshot(.active), entry: lost, live: true, environment())

        XCTAssertNil(decision.action)
        XCTAssertEqual(decision.entry?.phase, .recording)
    }

    func testRecoveredSessionFinishesNormally() {
        let lost = entry(writer: .iPhone, phase: .sessionLost, sessionStartedAt: start)
        let decision = decide(snapshot(.completed, endedAfter: 50), entry: lost, live: true, environment(minutesAfterStart: 51))

        XCTAssertEqual(decision.action, .finishSession(workoutID: id, endedAt: start.addingTimeInterval(50 * 60)))
    }

    func testDurationEditReplacesTheSavedCopyWithAHigherVersion() {
        let edited = snapshot(.completed, endedAfter: 65, updatedAfter: 120)
        let decision = decide(edited, entry: saved(version: 9_999_999_999_999), environment(minutesAfterStart: 121))

        XCTAssertEqual(
            decision.action,
            .replaceSavedWorkout(workoutID: id, startedAt: start, endedAt: start.addingTimeInterval(65 * 60), syncVersion: 10_000_000_000_000)
        )
    }

    func testTitleOnlyEditLeavesHealthAlone() {
        let renamed = snapshot(.completed, endedAfter: 50, updatedAfter: 120)

        XCTAssertNil(decide(renamed, entry: saved(), environment(minutesAfterStart: 121)).action)
    }

    func testDeletedWorkoutDeletesTheSavedCopy() {
        let deleted = snapshot(.completed, endedAfter: 50, isDeleted: true)

        XCTAssertEqual(decide(deleted, entry: saved(), environment()).action, .deleteSavedWorkout(workoutID: id))
    }

    func testMissingRowNeverDeletesTheSavedCopy() {
        XCTAssertNil(decide(nil, entry: saved(), environment()).action)
    }

    func testRevertedDeleteSavesTheWorkoutAgain() {
        var deleted = saved()
        deleted.phase = .deletedWithWorkout
        let decision = decide(snapshot(.completed, endedAfter: 50, updatedAfter: 200), entry: deleted, environment())

        guard case .saveWorkout = decision.action else {
            return XCTFail("Expected the restored workout to be saved again, got \(String(describing: decision.action))")
        }
    }

    func testCopyDeletedInHealthIsNeverRestored() {
        var removed = saved()
        removed.phase = .removedInHealth

        XCTAssertNil(decide(snapshot(.completed, endedAfter: 65, updatedAfter: 200), entry: removed, environment()).action)
    }

    // MARK: Sync version

    func testSyncVersionNeverGoesBackwards() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(AppleHealthSyncVersion.next(updatedAt: updatedAt, lastWritten: nil), 1_000_000)
        XCTAssertEqual(AppleHealthSyncVersion.next(updatedAt: updatedAt, lastWritten: 999_999), 1_000_000)
        XCTAssertEqual(AppleHealthSyncVersion.next(updatedAt: updatedAt, lastWritten: 2_000_000), 2_000_001)
    }
}
