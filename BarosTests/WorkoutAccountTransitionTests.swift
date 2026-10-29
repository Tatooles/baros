import SwiftData
import XCTest
@testable import Baros

@MainActor
final class WorkoutAccountTransitionTests: XCTestCase {
    func testNoWorkoutPerformsAccountActionWithoutConfirmation() async throws {
        let h = try Harness()
        await h.request()
        XCTAssertEqual(h.calls, 1)
        XCTAssertFalse(h.gate.needsResolution)
    }

    func testCancelPreservesOwnerAndActiveWorkout() async throws {
        let h = try Harness()
        let session = try h.start()
        await h.request()
        XCTAssertTrue(h.gate.needsResolution)
        h.gate.cancel()
        await h.gate.resolve(.discard)
        XCTAssertEqual(h.calls, 0)
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(h.owner, "issuer|a")
    }

    func testFinishAndDiscardPersistBeforeAccountAction() async throws {
        for resolution in [WorkoutAccountTransition.Resolution.finish, .discard] {
            let h = try Harness()
            let session = try h.start()
            await h.gate.request {
                XCTAssertNotEqual(session.status, .active)
                XCTAssertFalse(h.context.hasChanges)
                XCTAssertTrue(h.engine.isAccountTransitionInProgress)
                XCTAssertThrowsError(try h.engine.startBlankWorkout(context: h.context))
                h.owner = nil
                h.calls += 1
            }
            await h.gate.resolve(resolution)
            XCTAssertEqual(h.calls, 1)
            XCTAssertEqual(session.status, resolution == .finish ? .completed : .discarded)
            XCTAssertEqual(session.syncOwnerTokenIdentifier, "issuer|a")
            XCTAssertFalse(h.engine.isAccountTransitionInProgress)
        }
    }

    func testFailedSaveNeverCallsAccountActionAndPreservesActiveWorkout() async throws {
        for resolution in [WorkoutAccountTransition.Resolution.finish, .discard] {
            let h = try Harness(failsSave: true)
            let session = try h.start()
            await h.request()
            await h.gate.resolve(resolution)
            XCTAssertEqual(session.status, .active)
            XCTAssertNil(session.endedAt)
            XCTAssertEqual(h.calls, 0)
            XCTAssertEqual(h.owner, "issuer|a")
            XCTAssertNotNil(h.gate.errorMessage)
            XCTAssertTrue(try h.context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
        }
    }

    func testSwitchAccountUsesSameGateAndNeverTransfersWorkoutOwnership() async throws {
        let h = try Harness()
        let session = try h.start()
        await h.gate.request { h.owner = "issuer|b"; h.calls += 1 }
        XCTAssertEqual(h.owner, "issuer|a")
        await h.gate.resolve(.finish)
        XCTAssertEqual(h.owner, "issuer|b")
        XCTAssertEqual(session.syncOwnerTokenIdentifier, "issuer|a")
        let entries = try h.context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.ownerTokenIdentifier == "issuer|a" })
    }

    func testOwnerChangeAndNewWorkoutInvalidatePendingConfirmation() async throws {
        for changeOwner in [false, true] {
            let h = try Harness()
            let session = try h.start()
            await h.request()
            if changeOwner { h.owner = "issuer|b" }
            else {
                h.context.insert(WorkoutSession(title: "Legacy", startedAt: .now,
                    status: .active, source: .blank, syncOwnerTokenIdentifier: h.owner))
                try h.context.save()
            }
            await h.gate.resolve(.discard)
            XCTAssertEqual(session.status, .active)
            XCTAssertEqual(h.calls, 0)
            XCTAssertNotNil(h.gate.errorMessage)
        }
    }

    func testAnotherOwnerCanSignOutAndManageAccountWithoutDiscardingHiddenWorkout() async throws {
        for destination in [WorkoutAccountTransition.Destination.signOut, .manageAccount] {
            let h = try Harness()
            let session = try h.start()
            h.owner = "issuer|b"
            await h.gate.request(destination: destination) { h.owner = nil; h.calls += 1 }
            XCTAssertFalse(h.gate.needsResolution)
            XCTAssertNil(h.gate.errorMessage)
            XCTAssertEqual(session.status, .active)
            XCTAssertEqual(session.syncOwnerTokenIdentifier, "issuer|a")
            XCTAssertEqual(h.calls, 1)
            XCTAssertThrowsError(try h.engine.startBlankWorkout(context: h.context))
            XCTAssertEqual(try h.engine.startBlankWorkout(ownerTokenIdentifier: "issuer|a", context: h.context).id, session.id)
        }
    }

    func testDeleteAccountStillBlocksHiddenWorkoutBecauseResetWouldEraseIt() async throws {
        let h = try Harness()
        let session = try h.start()
        h.owner = "issuer|b"
        await h.gate.request(destination: .deleteAccount) { h.calls += 1 }
        XCTAssertNotNil(h.gate.errorMessage)
        XCTAssertFalse(h.gate.needsResolution)
        XCTAssertEqual(h.calls, 0)
        XCTAssertEqual(session.status, .active)
    }

    func testOutgoingWorkoutIsResolvedWithoutChangingAnotherOwnersHiddenRecord() async throws {
        let h = try Harness()
        let hidden = try h.start()
        let outgoing = WorkoutSession(title: "B workout", startedAt: .now, status: .active,
            source: .blank, syncOwnerTokenIdentifier: "issuer|b")
        h.context.insert(outgoing)
        try h.context.save()
        h.owner = "issuer|b"
        await h.gate.request { h.owner = nil; h.calls += 1 }
        XCTAssertTrue(h.gate.needsResolution)
        await h.gate.resolve(.finish)
        XCTAssertEqual(h.calls, 1)
        XCTAssertEqual(outgoing.status, .completed)
        XCTAssertEqual(hidden.status, .active)
        XCTAssertThrowsError(try h.engine.startBlankWorkout(context: h.context))
    }

    func testLegacyBatchFinalizationUsesOneSaveAndRestoresEveryWorkoutOnFailure() async throws {
        for resolution in [WorkoutAccountTransition.Resolution.finish, .discard] {
            for failsSave in [false, true] {
                let h = try Harness()
                let first = try h.start()
                first.title = "  First draft  "
                let second = WorkoutSession(title: "  Second draft  ", startedAt: .now,
                    status: .active, source: .blank, syncOwnerTokenIdentifier: h.owner)
                h.context.insert(second)
                try h.context.save()
                let baselineDates = [first.updatedAt, second.updatedAt]
                h.engine.restTimer.start(sessionID: first.id, setID: UUID(), duration: 120)
                var saveCalls = 0
                let gate = WorkoutAccountTransition(context: h.context, engine: h.engine,
                    save: { context in
                        saveCalls += 1
                        // Both records must be staged before the only save.
                        XCTAssertEqual(first.status, resolution == .finish ? .completed : .discarded)
                        XCTAssertEqual(second.status, first.status)
                        XCTAssertEqual(h.engine.activeSessionID, first.id)
                        XCTAssertNotNil(h.engine.restTimer.current)
                        if failsSave { throw Failure.expected }
                        try context.save()
                    }, owner: { h.owner })
                await gate.request { h.calls += 1 }
                await gate.resolve(resolution)
                XCTAssertEqual(saveCalls, 1)
                if failsSave {
                    XCTAssertEqual(h.calls, 0)
                    XCTAssertEqual(first.status, .active)
                    XCTAssertEqual(second.status, .active)
                    XCTAssertEqual(first.title, "  First draft  ")
                    XCTAssertEqual(second.title, "  Second draft  ")
                    XCTAssertEqual([first.updatedAt, second.updatedAt], baselineDates)
                    XCTAssertNil(first.endedAt)
                    XCTAssertNil(second.endedAt)
                    XCTAssertNotNil(h.engine.restTimer.current)
                    XCTAssertEqual(h.engine.activeSessionID, first.id)
                    XCTAssertTrue(try h.context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
                    let reopened = ModelContext(h.container)
                    XCTAssertTrue(try reopened.fetch(FetchDescriptor<WorkoutSession>()).allSatisfy { $0.status == .active })
                } else {
                    XCTAssertEqual(h.calls, 1)
                    XCTAssertEqual(first.status, resolution == .finish ? .completed : .discarded)
                    XCTAssertEqual(second.status, first.status)
                    XCTAssertNil(h.engine.activeSessionID)
                    XCTAssertNil(h.engine.restTimer.current)
                }
                h.engine.restTimer.cancel()
            }
        }
    }

    func testAccountActionFailureDoesNotUndoSuccessfulWorkoutFinalization() async throws {
        let h = try Harness()
        let session = try h.start()
        await h.gate.request { throw Failure.expected }
        await h.gate.resolve(.finish)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(h.owner, "issuer|a")
        XCTAssertNotNil(h.gate.errorMessage)
    }

    func testConfirmedLossPreservesHiddenWorkoutUntilExplicitDiscardAndSuccessfulSave() throws {
        let h = try Harness()
        let session = try h.start()
        h.owner = nil
        let reopenedContext = ModelContext(h.container)
        let sessions = try reopenedContext.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(WorkoutRecovery.hiddenSessions(in: sessions, owner: nil).map(\.id), [session.id])
        XCTAssertTrue(WorkoutRecovery.hiddenSessions(in: sessions, owner: "issuer|a").isEmpty)
        XCTAssertThrowsError(try h.engine.startBlankWorkout(context: h.context))
        XCTAssertThrowsError(try WorkoutRecovery.discard(id: session.id, expectedOwner: nil,
            currentOwner: nil, engine: h.engine, context: h.context, save: { _ in throw Failure.expected }))
        XCTAssertEqual(session.status, .active)
        XCTAssertThrowsError(try h.engine.startBlankWorkout(context: h.context))
        try WorkoutRecovery.discard(id: session.id, expectedOwner: nil,
            currentOwner: nil, engine: h.engine, context: h.context)
        XCTAssertEqual(session.status, .discarded)
        XCTAssertNoThrow(try h.engine.startBlankWorkout(context: h.context))
    }

    func testRecoveryRejectsStaleConfirmationAndDoesNotDeleteHistory() throws {
        let h = try Harness()
        let session = try h.start()
        let history = WorkoutSession(title: "Saved history", startedAt: .now,
            status: .completed, source: .blank, syncOwnerTokenIdentifier: "issuer|a")
        h.context.insert(history)
        try h.context.save()
        XCTAssertThrowsError(try WorkoutRecovery.discard(id: session.id, expectedOwner: nil,
            currentOwner: "issuer|b", engine: h.engine, context: h.context))
        XCTAssertEqual(session.status, .active)
        try WorkoutRecovery.discard(id: session.id, expectedOwner: nil,
            currentOwner: nil, engine: h.engine, context: h.context)
        XCTAssertEqual(history.status, .completed)
        XCTAssertFalse(history.isDeleted)
    }

    func testLoadingLegacyMultipleActiveRecordsNeverSilentlyDiscardsThem() throws {
        let h = try Harness()
        let first = try h.start()
        let second = WorkoutSession(title: "Second", startedAt: .now, status: .active,
            source: .blank, syncOwnerTokenIdentifier: "issuer|b")
        h.context.insert(second)
        try h.context.save()
        for owner: String? in [nil, "issuer|a", "issuer|b"] {
            let engine = ActiveWorkoutEngine()
            engine.loadActiveSession(ownerTokenIdentifier: owner, context: h.context)
            XCTAssertEqual(first.status, .active)
            XCTAssertEqual(second.status, .active)
            XCTAssertThrowsError(try engine.startBlankWorkout(ownerTokenIdentifier: owner, context: h.context))
        }
    }

    func testDiskRelaunchRetainsHiddenWorkoutAndOriginalOwnerCanRecoverIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recovery.store")
        let id: UUID = try {
            let container = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: url)
            let session = try ActiveWorkoutEngine().startBlankWorkout(ownerTokenIdentifier: "issuer|a",
                context: container.mainContext)
            return session.id
        }()
        let reopened = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: url)
        let sessions = try reopened.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(WorkoutRecovery.hiddenSessions(in: sessions, owner: nil).map(\.id), [id])
        let engine = ActiveWorkoutEngine()
        XCTAssertThrowsError(try engine.startBlankWorkout(context: reopened.mainContext))
        let recovered = try engine.startBlankWorkout(ownerTokenIdentifier: "issuer|a", context: reopened.mainContext)
        XCTAssertEqual(recovered.id, id)
        XCTAssertEqual(recovered.status, .active)
    }

    private enum Failure: Error { case expected }

    @MainActor
    private final class Harness {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        let engine = ActiveWorkoutEngine()
        var owner: String? = "issuer|a"
        var calls = 0
        let failsSave: Bool
        lazy var gate = WorkoutAccountTransition(context: context, engine: engine,
            save: { [unowned self] context in
                if failsSave { throw Failure.expected }
                try context.save()
            }, owner: { [unowned self] in owner })
        init(failsSave: Bool = false) throws {
            self.failsSave = failsSave
            container = try SwiftDataTestSupport.makeInMemoryContainer()
        }
        func start() throws -> WorkoutSession {
            try engine.startBlankWorkout(ownerTokenIdentifier: owner, context: context)
        }
        func request() async { await gate.request { self.calls += 1 } }
    }
}
