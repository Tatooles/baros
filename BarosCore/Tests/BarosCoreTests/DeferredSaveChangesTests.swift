import SwiftData
import XCTest
@testable import BarosCore

@MainActor
final class DeferredSaveChangesTests: XCTestCase {
    /// BAROS-IOS-1M: a `didSave` receiver read models inside the seed's `save()`
    /// and blocked launch for 160 s.
    func testHandlerRunsAfterTheSavesReturnWithTheBurstMergedIntoOneCall() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let deferred = DeferredSaveChanges()
        let recorder = Recorder()
        let delivered = expectation(description: "Deferred save changes delivered")
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { notification in
            let changes = PreviousSetsCacheSaveChanges(notification: notification)
            MainActor.assumeIsolated {
                deferred.enqueue(changes) { changes in
                    recorder.deliveries.append((changes, recorder.isSaving))
                    delivered.fulfill()
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let first = WorkoutSession(title: "First", startedAt: .now, status: .completed, source: .blank)
        let second = WorkoutSession(title: "Second", startedAt: .now, status: .completed, source: .blank)

        recorder.isSaving = true
        context.insert(first)
        try context.save()
        context.insert(second)
        try context.save()
        recorder.isSaving = false
        XCTAssertTrue(recorder.deliveries.isEmpty)
        await fulfillment(of: [delivered], timeout: 5)

        XCTAssertEqual(recorder.deliveries.count, 1)
        let delivery = try XCTUnwrap(recorder.deliveries.first)
        XCTAssertFalse(delivery.duringSave)
        XCTAssertEqual(delivery.changes.insertedIDs, [first.persistentModelID, second.persistentModelID])
    }
}

@MainActor
private final class Recorder {
    var isSaving = false
    var deliveries: [(changes: PreviousSetsCacheSaveChanges, duringSave: Bool)] = []
}
