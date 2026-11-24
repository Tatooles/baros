import SwiftData
import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class PreviousSetPerformanceTests: XCTestCase {
    func testCacheSaveChangesExtractsSwiftDataIdentifiers() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            title: "Active",
            startedAt: .now,
            status: .active,
            source: .blank
        )
        let notificationCapture = NotificationCapture()
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { notificationCapture.store($0) }
        defer { NotificationCenter.default.removeObserver(observer) }

        context.insert(session)
        try context.save()

        let insertedChanges = PreviousSetsCacheSaveChanges(
            notification: try XCTUnwrap(notificationCapture.take())
        )
        XCTAssertTrue(insertedChanges.insertedIDs.contains(session.persistentModelID))

        session.title = "Updated"
        try context.save()

        let updatedChanges = PreviousSetsCacheSaveChanges(
            notification: try XCTUnwrap(notificationCapture.take())
        )
        XCTAssertTrue(updatedChanges.updatedIDs.contains(session.persistentModelID))
    }

    func testLoaderDoesNotFetchHistoryForSyncBookkeepingSaves() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let active = WorkoutSession(title: "Active", startedAt: .now, status: .active, source: .blank)
        context.insert(active)
        try context.save()
        var fetchCount = 0
        let cache = PreviousSetsCacheLoaderCache { context, owner in
            fetchCount += 1
            return try PreviousSetsCacheLoaderCache.fetchCompletedHistory(context: context, ownerTokenIdentifier: owner)
        }
        cache.reload(session: active, context: context, ownerTokenIdentifier: nil, lastSyncedAt: nil, onUpdate: { _ in })
        XCTAssertEqual(fetchCount, 1)

        let outbox = SyncOutboxEntry(entityKind: .loggedSet, entityID: UUID(), operation: .create, now: .now)
        let cursor = SyncCursorState(ownerTokenIdentifier: "owner")
        let insertion = try captureSave(in: context) {
            context.insert(outbox)
            context.insert(cursor)
        }
        XCTAssertTrue(PreviousSetsCacheSaveChanges(notification: insertion).containsOnlySyncBookkeeping)
        cache.reloadIfNeeded(after: insertion, session: active, context: context, ownerTokenIdentifier: nil,
                             lastSyncedAt: nil, onUpdate: { _ in })

        let update = try captureSave(in: context) {
            cursor.loggedSetsCursor = 123
            outbox.status = .failed
        }
        cache.reloadIfNeeded(after: update, session: active, context: context, ownerTokenIdentifier: nil,
                             lastSyncedAt: nil, onUpdate: { _ in })
        let deletion = try captureSave(in: context) { context.delete(outbox) }
        cache.reloadIfNeeded(after: deletion, session: active, context: context, ownerTokenIdentifier: nil,
                             lastSyncedAt: nil, onUpdate: { _ in })
        XCTAssertEqual(fetchCount, 1, "Bookkeeping insert/update/delete must not fetch completed history")
    }

    func testLoaderRetainsMixedSaveAndRemoteChildInvalidation() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let exercise = Exercise(name: "Bench", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        try insertCompletedSession(startedAt: Date(timeIntervalSince1970: 100), exercise: exercise, sets: [(135, 10)], in: context)
        let active = WorkoutSession(title: "Active", startedAt: .now, status: .active, source: .blank)
        let activeExercise = LoggedExercise(orderIndex: 0, exercise: exercise)
        active.loggedExercises.append(activeExercise)
        context.insert(active)
        try context.save()
        let historical = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.status == .completed })
        let historicalSet = try XCTUnwrap(historical.sortedLoggedExercises.first?.sortedSets.first)
        let parentUpdatedAt = historical.updatedAt
        var fetchCount = 0
        var previous: [UUID: [PreviousSetPerformance]] = [:]
        let cache = PreviousSetsCacheLoaderCache { context, owner in
            fetchCount += 1
            return try PreviousSetsCacheLoaderCache.fetchCompletedHistory(context: context, ownerTokenIdentifier: owner)
        }
        cache.reload(session: active, context: context, ownerTokenIdentifier: nil, lastSyncedAt: nil, onUpdate: { previous = $0 })
        XCTAssertEqual(previous[activeExercise.id]?.first?.weight, 135)

        let mixedSave = try captureSave(in: context) {
            historicalSet.weight = 155
            context.insert(SyncCursorState(ownerTokenIdentifier: "owner"))
        }
        XCTAssertFalse(PreviousSetsCacheSaveChanges(notification: mixedSave).containsOnlySyncBookkeeping)
        cache.reloadIfNeeded(after: mixedSave, session: active, context: context, ownerTokenIdentifier: nil,
                             lastSyncedAt: nil, onUpdate: { previous = $0 })
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(historical.updatedAt, parentUpdatedAt)
        cache.reload(session: active, context: context, ownerTokenIdentifier: nil,
                     lastSyncedAt: Date(timeIntervalSince1970: 300), onUpdate: { previous = $0 })
        XCTAssertEqual(previous[activeExercise.id]?.first?.weight, 155)

        let fullInvalidation = Notification(name: ModelContext.didSave, object: context, userInfo: [
            ModelContext.NotificationKey.updatedIdentifiers.rawValue: [historicalSet.persistentModelID],
            ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue: true,
        ])
        cache.reloadIfNeeded(after: fullInvalidation, session: active, context: context, ownerTokenIdentifier: nil,
                             lastSyncedAt: nil, onUpdate: { previous = $0 })
        XCTAssertEqual(fetchCount, 4)
    }

    func testLoaderAcceptsSameContainerSavesAndIgnoresOtherContainers() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let active = WorkoutSession(title: "Active", startedAt: .now, status: .active, source: .blank)
        context.insert(active)
        try context.save()
        var fetchCount = 0
        let cache = PreviousSetsCacheLoaderCache { context, owner in
            fetchCount += 1
            return try PreviousSetsCacheLoaderCache.fetchCompletedHistory(context: context, ownerTokenIdentifier: owner)
        }
        cache.reload(session: active, context: context, ownerTokenIdentifier: nil, lastSyncedAt: nil, onUpdate: { _ in })
        let otherContainer = try SwiftDataTestSupport.makeInMemoryContainer()
        let unrelated = try captureSave(in: otherContainer.mainContext) {
            otherContainer.mainContext.insert(WorkoutSession(title: "Other", startedAt: .now, status: .completed, source: .blank))
        }
        cache.reloadIfNeeded(after: unrelated, session: active, context: context, ownerTokenIdentifier: nil,
                             lastSyncedAt: nil, onUpdate: { _ in })
        XCTAssertEqual(fetchCount, 1)

        let sibling = ModelContext(container)
        let related = try captureSave(in: sibling) {
            sibling.insert(WorkoutSession(title: "History", startedAt: .now, status: .completed, source: .blank))
        }
        cache.reloadIfNeeded(after: related, session: active, context: context, ownerTokenIdentifier: nil,
                             lastSyncedAt: nil, onUpdate: { _ in })
        XCTAssertEqual(fetchCount, 2)
    }

    func testCompletedHistoryFetchPreservesVisibilityAndRecency() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 200)
        let local = WorkoutSession(title: "Local", startedAt: old, status: .completed, source: .blank)
        let owned = WorkoutSession(title: "Owned", startedAt: recent, status: .completed, source: .blank, syncOwnerTokenIdentifier: "owner")
        let foreign = WorkoutSession(title: "Foreign", startedAt: recent, status: .completed, source: .blank, syncOwnerTokenIdentifier: "other")
        let deleted = WorkoutSession(title: "Deleted", startedAt: recent, status: .completed, source: .blank)
        deleted.deletedAt = recent
        let active = WorkoutSession(title: "Active", startedAt: recent, status: .active, source: .blank)
        for session in [local, owned, foreign, deleted, active] { context.insert(session) }
        try context.save()

        XCTAssertEqual(try PreviousSetsCacheLoaderCache.fetchCompletedHistory(context: context, ownerTokenIdentifier: "owner").map(\.id), [owned.id, local.id])
        XCTAssertEqual(try PreviousSetsCacheLoaderCache.fetchCompletedHistory(context: context, ownerTokenIdentifier: nil).map(\.id), [local.id])
    }

    private func captureSave(in context: ModelContext, changes: () -> Void) throws -> Notification {
        let capture = NotificationCapture()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: nil) {
            capture.store($0)
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        changes()
        try context.save()
        return try XCTUnwrap(capture.take())
    }

    private func insertCompletedSession(
        startedAt: Date,
        exercise: Exercise,
        sets: [(Double, Int)],
        in context: ModelContext
    ) throws {
        let session = WorkoutSession(title: "Past", startedAt: startedAt, status: .completed, source: .blank)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise)
        session.loggedExercises.append(logged)
        context.insert(session)
        context.insert(logged)

        for (index, pair) in sets.enumerated() {
            let set = LoggedSet(
                orderIndex: index,
                weight: pair.0,
                reps: pair.1,
                kind: .working,
                isCompleted: true,
                completedAt: startedAt
            )
            logged.sets.append(set)
            context.insert(set)
        }
        try context.save()
    }
}

private final class NotificationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var notification: Notification?

    func store(_ notification: Notification) {
        lock.withLock {
            self.notification = notification
        }
    }

    func take() -> Notification? {
        lock.withLock {
            defer { notification = nil }
            return notification
        }
    }
}
