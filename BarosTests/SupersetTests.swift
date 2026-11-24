import CoreData
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class SupersetGroupingTests: XCTestCase {
    private let a = UUID(), b = UUID()
}

@MainActor
final class SupersetWorkoutTests: XCTestCase {
    func testRoundRestSharesOnePeriodAndPartnerUncheckCancelsIt() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, 0])
        let timer = RestTimerCoordinator(schedulesTasks: false)
        let engine = ActiveWorkoutEngine(restTimer: timer)
        let sets = session.sortedLoggedExercises.map { $0.sortedSets[0] }
        let slots = sets.map { timer.slot(for: $0.id) }
        try engine.toggleSetCompletion(sets[0], context: context)
        let period = try XCTUnwrap(timer.current)
        XCTAssertTrue(slots.allSatisfy { $0.period === period })
        let end = period.rest.endsAt
        timer.adjust(by: 30)
        XCTAssertTrue(slots.allSatisfy { $0.period?.rest.endsAt == end.addingTimeInterval(30) })
        timer.reportInlineVisibility(true, restID: period.rest.id, setID: sets[0].id)
        timer.reportInlineVisibility(false, restID: period.rest.id, setID: sets[1].id)
        XCTAssertFalse(timer.showsHeaderFallback, "One visible partner suffices")
        try engine.toggleSetCompletion(sets[1], context: context)
        XCTAssertNil(timer.current)
        XCTAssertTrue(slots.allSatisfy { $0.period == nil })
        try engine.toggleSetCompletion(sets[1], context: context)
        let snapshot = WorkoutLiveActivitySnapshot(session: session, restPeriod: timer.current)
        XCTAssertEqual(snapshot.restEndsAt, timer.current?.rest.endsAt)
        let saved = try JSONEncoder().encode(XCTUnwrap(timer.current).rest)
        let restored = RestTimerCoordinator(restoredRest: try JSONDecoder().decode(WorkoutRest.self, from: saved), schedulesTasks: false)
        restored.reconcile(with: session)
        let restoredSlots = sets.map { restored.slot(for: $0.id) }
        XCTAssertTrue(restoredSlots.allSatisfy { $0.period === restored.current })
        timer.skip()
        XCTAssertTrue(slots.allSatisfy { $0.period == nil })
        try engine.toggleSetCompletion(sets[1], context: context)
        try engine.toggleSetCompletion(sets[1], context: context)
        try engine.removeSet(sets[2], context: context)
        XCTAssertNil(timer.current, "Deleting a partner cancels round rest")
        restored.reconcile(with: session)
        XCTAssertNil(restored.current, "Restoration also rejects a removed participant")
    }

    func testUploadsSendGroupsAndOnlyThisDevicesRemovals() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, nil])
        let exercises = session.sortedLoggedExercises
        let grouped = SyncPayloadMapper.loggedExercisePayload(from: exercises[0])
        XCTAssertEqual(grouped.supersetGroupID, exercises[0].supersetGroupID?.uuidString.lowercased())
        let groupedArgs = ConvexSyncArgumentMapper.loggedExerciseRecord(grouped)
        XCTAssertEqual(groupedArgs["supersetGroupID"] as? String, grouped.supersetGroupID)

        let untouchedArgs = ConvexSyncArgumentMapper.loggedExerciseRecord(
            SyncPayloadMapper.loggedExercisePayload(from: exercises[2])
        )
        XCTAssertFalse(untouchedArgs.keys.contains("supersetGroupID"))

        try ActiveWorkoutEngine().changeSuperset(.remove, for: exercises[1], context: context)
        let removedArgs = ConvexSyncArgumentMapper.loggedExerciseRecord(
            SyncPayloadMapper.loggedExercisePayload(from: exercises[1])
        )
        XCTAssertTrue(removedArgs.keys.contains("supersetGroupID"))
        XCTAssertNil(removedArgs["supersetGroupID"] ?? nil)
    }

    func testUpgradedDeviceEditingAnUnseenGroupKeepsTheServerGrouping() async throws {
        let owner = "issuer|owner"
        let (context, session) = try makeWorkout(names: ["A", "B"], status: .completed, owner: owner)
        let exercise = session.sortedLoggedExercises[0]
        XCTAssertNil(exercise.supersetGroupID)
        XCTAssertFalse(exercise.hasLocalSupersetChange)

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.exercises[0].notes = "Edited after upgrading"
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft, for: session, ownerTokenIdentifier: owner, context: context
        )
        let client = FakeSyncClient()
        client.fetchResponses = [SyncFetchChangesResponse(
            userSettings: [], exercises: [], workoutSessions: [], loggedExercises: [], loggedSets: [],
            cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
            hasMore: SyncHasMore(userSettings: false, exercises: false)
        )]
        _ = try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let upload = try XCTUnwrap(client.upsertedLoggedExercises.last { $0.clientId == exercise.id.uuidString.lowercased() })
        XCTAssertEqual(upload.notes, "Edited after upgrading")
        XCTAssertFalse(ConvexSyncArgumentMapper.loggedExerciseRecord(upload).keys.contains("supersetGroupID"))
    }

    private func grouped(_ session: WorkoutSession, _ positions: [Int]) -> Bool {
        let ids = session.sortedLoggedExercises.map(\.supersetGroupID)
        guard let group = ids[positions[0]] else { return false }
        let members = ids.indices.filter { ids[$0] == group }
        return members == positions
    }

    private func makeWorkout(
        names: [String],
        groups: [Int?]? = nil,
        setCount: Int = 2,
        status: WorkoutSessionStatus = .active,
        owner: String? = nil
    ) throws -> (ModelContext, WorkoutSession) {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        containers.append(container)
        let session = try insertWorkout(names: names, groups: groups, setCount: setCount, status: status,
                                        owner: owner, into: container.mainContext)
        return (container.mainContext, session)
    }

    private var containers: [ModelContainer] = []

    private func insertWorkout(
        names: [String],
        groups: [Int?]? = nil,
        setCount: Int = 2,
        status: WorkoutSessionStatus = .active,
        owner: String? = nil,
        into context: ModelContext
    ) throws -> WorkoutSession {
        let groupIDs = [UUID(), UUID()]
        let start = Date(timeIntervalSince1970: 100)
        let session = WorkoutSession(
            title: "Workout", startedAt: start, endedAt: status == .completed ? start.addingTimeInterval(60) : nil,
            status: status, source: .blank, createdAt: start, updatedAt: start, syncOwnerTokenIdentifier: owner
        )
        context.insert(session)
        for (index, name) in names.enumerated() {
            let exercise = Exercise(name: name, category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
            context.insert(exercise)
            let logged = LoggedExercise(
                orderIndex: index, exercise: exercise,
                supersetGroupID: groups?[index].map { groupIDs[$0] },
                createdAt: start, updatedAt: start
            )
            context.insert(logged)
            logged.session = session
            session.loggedExercises.append(logged)
            for setIndex in 0..<setCount {
                let set = LoggedSet(orderIndex: setIndex, isCompleted: status == .completed,
                                    createdAt: start, updatedAt: start)
                context.insert(set)
                set.loggedExercise = logged
                logged.sets.append(set)
            }
        }
        try context.save()
        return session
    }
}

@MainActor
final class NativeGroupedReorderListTests: XCTestCase {
    private struct Row: ReorderListExercise {
        let id = UUID()
        let name: String
        var supersetGroupID: UUID?
        var metadata: String? { nil }
        var trailingDetail: String? { nil }
        var isNew: Bool { false }
        var accessibilityValue: String { "" }
    }

    func testDeletingARowRemovesItFromTheTableInsteadOfWaitingForAReload() throws {
        let group = UUID()
        let rows = [Row(name: "A", supersetGroupID: group), Row(name: "B", supersetGroupID: group), Row(name: "C")]
        var removed: [Set<UUID>] = []
        let list = NativeGroupedReorderList(
            blocks: SupersetGrouping.blocks(rows, groupID: \.supersetGroupID),
            reorder: { _ in }, remove: { removed.append($0) }, add: {}, link: nil,
            memory: ReorderListMemory(), memberReveal: ReorderMemberReveal(), header: EmptyView()
        )
        let coordinator = list.makeCoordinator()
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 402, height: 800), style: .plain)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "ExerciseBlock")
        table.dataSource = coordinator
        table.delegate = coordinator
        table.setEditing(true, animated: false)
        table.layoutIfNeeded()
        XCTAssertEqual(table.numberOfRows(inSection: 0), 3, "Superset, C and the actions row")

        coordinator.tableView(table, commit: .delete, forRowAt: IndexPath(row: 1, section: 0))

        XCTAssertEqual(removed, [[rows[2].id]])
        XCTAssertEqual(table.numberOfRows(inSection: 0), 2, "The table drops the row before SwiftUI's update arrives")
        XCTAssertEqual(coordinator.blocks.map(\.id), [rows[0].id])
    }
}
