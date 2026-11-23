import Foundation
import SwiftData
import XCTest
@testable import BarosCore

@MainActor
final class SwiftDataAppleHealthSnapshotSourceTests: XCTestCase {
    private let owner = "issuer|owner"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSource(
        _ container: ModelContainer,
        _ visibility: SwiftDataAppleHealthSnapshotSource.CurrentOwnerVisibility
    ) -> SwiftDataAppleHealthSnapshotSource {
        SwiftDataAppleHealthSnapshotSource(container: container, currentOwner: { visibility })
    }

    func testReadsSavedActiveWorkoutsAndRequestedOnesOnly() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let active = WorkoutSession(title: "Push", startedAt: start, status: .active, source: .blank, syncOwnerTokenIdentifier: owner)
        let tracked = WorkoutSession(title: "Pull", startedAt: start, endedAt: start.addingTimeInterval(3_000), status: .completed, source: .blank)
        let untracked = WorkoutSession(title: "Legs", startedAt: start, endedAt: start.addingTimeInterval(3_000), status: .completed, source: .blank)
        [active, tracked, untracked].forEach(context.insert)
        try context.save()

        let snapshots = try makeSource(container, .resolved(ownerTokenIdentifier: owner))
            .snapshots(includingWorkoutIDs: [tracked.id])

        XCTAssertEqual(Set(snapshots.map(\.workoutID)), [active.id, tracked.id])
        let activeSnapshot = try XCTUnwrap(snapshots.first { $0.workoutID == active.id })
        XCTAssertEqual(activeSnapshot.status, .active)
        XCTAssertTrue(activeSnapshot.isVisible)
        let completed = try XCTUnwrap(snapshots.first { $0.workoutID == tracked.id })
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.endedAt, start.addingTimeInterval(3_000))
    }

    func testUnsavedChangesAreNotSeen() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = WorkoutSession(title: "Push", startedAt: start, status: .active, source: .blank, syncOwnerTokenIdentifier: owner)
        context.insert(session)
        try context.save()

        session.status = .completed
        session.endedAt = start.addingTimeInterval(60)

        let snapshot = try XCTUnwrap(makeSource(container, .resolved(ownerTokenIdentifier: owner))
            .snapshots(includingWorkoutIDs: [session.id]).first)
        XCTAssertEqual(snapshot.status, .active, "Only committed state counts")
    }

    func testActiveWorkoutOfAnotherOwnerIsHidden() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let session = WorkoutSession(title: "Push", startedAt: start, status: .active, source: .blank, syncOwnerTokenIdentifier: owner)
        container.mainContext.insert(session)
        try container.mainContext.save()

        let snapshot = try XCTUnwrap(makeSource(container, .resolved(ownerTokenIdentifier: nil))
            .snapshots(includingWorkoutIDs: []).first)

        XCTAssertFalse(snapshot.isVisible)
    }

    func testTombstoneIsReportedAsDeleted() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let session = WorkoutSession(
            title: "Pull", startedAt: start, endedAt: start.addingTimeInterval(60), status: .completed,
            source: .blank, deletedAt: start.addingTimeInterval(120)
        )
        container.mainContext.insert(session)
        try container.mainContext.save()

        let snapshot = try XCTUnwrap(makeSource(container, .resolved(ownerTokenIdentifier: nil))
            .snapshots(includingWorkoutIDs: [session.id]).first)

        XCTAssertTrue(snapshot.isDeleted)
    }

    func testUnresolvedOwnerIsUnknownNotMissing() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()

        XCTAssertThrowsError(try makeSource(container, .unresolved).snapshots(includingWorkoutIDs: []))
    }

    func testLocalDataResetTellsTheObserverBeforeRowsGoAndAfterward() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(WorkoutSession(title: "Push", startedAt: start, status: .active, source: .blank))
        try context.save()
        let observer = ResetObserverSpy(container: container)

        try LocalDataResetService(observer: observer).reset(context: context)

        XCTAssertEqual(observer.events, ["willBegin(rows: 1)", "didEnd(rows: 0)"])
    }
}

@MainActor
private final class ResetObserverSpy: LocalDataResetObserving {
    let container: ModelContainer
    var events: [String] = []

    init(container: ModelContainer) {
        self.container = container
    }

    private var rowCount: Int {
        (try? ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>())) ?? -1
    }

    func localDataResetWillBegin() {
        events.append("willBegin(rows: \(rowCount))")
    }

    func localDataResetDidEnd() {
        events.append("didEnd(rows: \(rowCount))")
    }
}
