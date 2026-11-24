import CoreData
import SwiftData
import XCTest
@testable import BarosCore

@MainActor
final class SupersetGroupingTests: XCTestCase {
    private let a = UUID(), b = UUID()

    func testBlocksOnlyTrustRunsOfTwoOrMore() {
        let ids: [UUID?] = [nil, a, a, b, nil, a]
        let blocks = SupersetGrouping.blocks(Array(ids.indices).map(Item.init), groupID: { ids[$0.index] })
        XCTAssertEqual(blocks.map { $0.members.map(\.index) }, [[0], [1, 2], [3], [4], [5]])
        XCTAssertEqual(blocks.map(\.isSuperset), [false, true, false, false, false])
        XCTAssertTrue(SupersetGrouping.isGrouped(ids, at: 1))
        XCTAssertFalse(SupersetGrouping.isGrouped(ids, at: 3), "A lone id displays as ungrouped")
        XCTAssertFalse(SupersetGrouping.isGrouped(ids, at: 5))
    }

    func testNormalizedClearsLoneIDsAndSplitsRepeatedRuns() {
        var fresh = [UUID(), UUID()].makeIterator()
        let result = SupersetGrouping.normalized([a, a, nil, a, a, b], makeID: { fresh.next()! })
        XCTAssertEqual(Array(result[0...2]), [a, a, nil])
        XCTAssertNotNil(result[3])
        XCTAssertNotEqual(result[3], a, "A later run of the same id becomes its own superset")
        XCTAssertEqual(result[3], result[4])
        XCTAssertNil(result[5])
    }

    func testLinkingPairsJoinsAndMergesKeepingTheUpperID() {
        let pair = SupersetGrouping.linking([nil, nil, nil], 1, with: 0)
        XCTAssertNotNil(pair[0])
        XCTAssertEqual(pair[0], pair[1])
        XCTAssertNil(pair[2])

        XCTAssertEqual(SupersetGrouping.linking([a, a, nil], 2, with: 1), [a, a, a], "Join Previous joins the group above")
        XCTAssertEqual(SupersetGrouping.linking([nil, a, a], 0, with: 1), [a, a, a], "Superset with Next joins the group below")
        XCTAssertEqual(SupersetGrouping.linking([a, a, b, b], 1, with: 2), [a, a, a, a], "Two groups merge under the upper id")
        XCTAssertEqual(SupersetGrouping.linking([a, a], 0, with: 1), [a, a], "Already grouped neighbors are unchanged")
    }

    func testRemovingUngroupsAndDropsGroupsOfOne() {
        XCTAssertEqual(SupersetGrouping.removing([a, a], at: 1), [nil, nil])
        XCTAssertEqual(SupersetGrouping.removing([a, a, a], at: 2), [a, a, nil])
        XCTAssertEqual(SupersetGrouping.removing([a, a, a], at: 1), [nil, nil, nil])

        let split = SupersetGrouping.removing([a, a, a, a, a], at: 2)
        XCTAssertEqual(Array(split[0...2]), [a, a, nil])
        XCTAssertNotNil(split[3])
        XCTAssertNotEqual(split[3], a, "Each side stays a superset of its own")
        XCTAssertEqual(split[3], split[4])
    }

    func testCopiedUsesFreshIDsPerGroup() {
        let copy = SupersetGrouping.copied([a, a, nil, b, b, b, a])
        XCTAssertFalse(copy.contains(a))
        XCTAssertFalse(copy.contains(b))
        XCTAssertEqual(copy[0], copy[1])
        XCTAssertNil(copy[2])
        XCTAssertEqual(Set(copy[3...5]).count, 1)
        XCTAssertNotEqual(copy[0], copy[3])
        XCTAssertNil(copy[6])
    }

    private struct Item: Identifiable {
        let index: Int
        let id = UUID()
    }
}

@MainActor
final class SupersetWorkoutTests: XCTestCase {
    func testMenuActionsPairJoinMergeAndRemoveInOneSave() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C", "D"])
        let engine = ActiveWorkoutEngine()
        let exercises = session.sortedLoggedExercises
        var saves = 0
        let save: (ModelContext) throws -> Void = { saves += 1; try $0.save() }
        let now = Date(timeIntervalSince1970: 500)

        try engine.changeSuperset(.joinPrevious, for: exercises[1], context: context, now: now, save: save)
        XCTAssertEqual(saves, 1)
        XCTAssertTrue(grouped(session, [0, 1]))
        XCTAssertEqual(exercises[0].updatedAt, now)
        XCTAssertEqual(exercises[1].updatedAt, now)
        XCTAssertNotEqual(exercises[2].updatedAt, now)

        try engine.changeSuperset(.joinNext, for: exercises[2], context: context, save: save)
        XCTAssertTrue(grouped(session, [2, 3]))
        XCTAssertNotEqual(exercises[1].supersetGroupID, exercises[2].supersetGroupID)

        let upper = exercises[0].supersetGroupID
        try engine.changeSuperset(.joinNext, for: exercises[1], context: context, save: save)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.supersetGroupID), Array(repeating: upper, count: 4))

        try engine.changeSuperset(.remove, for: exercises[3], context: context, save: save)
        XCTAssertTrue(grouped(session, [0, 1, 2]))
        XCTAssertNil(exercises[3].supersetGroupID)

        XCTAssertThrowsError(try engine.changeSuperset(.joinPrevious, for: exercises[1], context: context)) {
            XCTAssertEqual($0 as? ActiveWorkoutEngineError, .invalidSupersetChange)
        }
        XCTAssertThrowsError(try engine.changeSuperset(.joinPrevious, for: exercises[0], context: context))
        XCTAssertThrowsError(try engine.changeSuperset(.remove, for: exercises[3], context: context))
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1, 2, 3], "Grouping never reorders")
    }

    func testFailedSupersetSaveRestoresGroupingAndTimestamps() throws {
        let (context, session) = try makeWorkout(names: ["A", "B"])
        let engine = ActiveWorkoutEngine()
        let before = WorkoutExerciseListSnapshot(session: session)
        let sessionUpdatedAt = session.updatedAt
        XCTAssertThrowsError(try engine.changeSuperset(
            .joinNext, for: session.sortedLoggedExercises[0], context: context,
            save: { _ in throw CocoaError(.fileWriteUnknown) }
        ))
        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), before)
        XCTAssertEqual(session.updatedAt, sessionUpdatedAt)
    }

    func testRemovingOrSwappingAnExerciseKeepsTheRestOfTheGroup() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C", "D", "E"], groups: [0, 0, 0, 1, 1])
        let engine = ActiveWorkoutEngine()
        let exercises = session.sortedLoggedExercises

        try engine.removeLoggedExercise(exercises[1], context: context)
        XCTAssertTrue(grouped(session, [0, 1]), "A and C close the gap and stay a pair")

        try engine.removeLoggedExercise(exercises[4], context: context)
        XCTAssertNil(exercises[3].supersetGroupID, "A group of one disappears")

        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(library)
        let replacement = try engine.swapLoggedExercise(exercises[2], with: library, context: context)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [exercises[0].id, replacement.id, exercises[3].id])
        XCTAssertTrue(grouped(session, [0, 1]), "The replacement takes the swapped exercise's place in the superset")
    }

    func testCheckingASetChecksTheRoundAndFillsEachPartnerLikeItsOwnCheck() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, 0], setCount: 2)
        let timer = RestTimerCoordinator(schedulesTasks: false)
        let engine = ActiveWorkoutEngine(restTimer: timer)
        let (a, b, c) = (session.sortedLoggedExercises[0], session.sortedLoggedExercises[1], session.sortedLoggedExercises[2])
        engine.previousSetsByLoggedExerciseID = [
            b.id: [PreviousSetPerformance(weight: 95, reps: 12)],
            c.id: [PreviousSetPerformance(weight: 40, reps: 15)],
        ]
        c.sortedSets[0].weight = 50
        try context.save()
        let now = Date(timeIntervalSince1970: 900)

        try engine.toggleSetCompletion(a.sortedSets[0], preparedValues: .init(weight: 135, reps: 8), context: context, now: now)

        XCTAssertTrue([a, b, c].allSatisfy { $0.sortedSets[0].isCompleted })
        XCTAssertTrue([a, b, c].allSatisfy { !$0.sortedSets[1].isCompleted })
        XCTAssertEqual(b.sortedSets[0].weight, 95)
        XCTAssertEqual(b.sortedSets[0].reps, 12)
        XCTAssertEqual(c.sortedSets[0].weight, 50)
        XCTAssertEqual(c.sortedSets[0].reps, 15)
        XCTAssertEqual(b.sortedSets[0].completedAt, now)
        XCTAssertEqual(timer.current?.rest.setID, a.sortedSets[0].id, "Rest starts once, after the round")

        try engine.toggleSetCompletion(c.sortedSets[1], context: context)
        XCTAssertEqual(b.sortedSets[1].weight, 95)
        XCTAssertEqual(b.sortedSets[1].reps, 12)
        XCTAssertTrue(a.sortedSets[1].isCompleted)

        try engine.toggleSetCompletion(b.sortedSets[1], context: context)
        XCTAssertFalse(b.sortedSets[1].isCompleted)
        XCTAssertTrue(a.sortedSets[1].isCompleted)
        XCTAssertTrue(c.sortedSets[1].isCompleted)
    }

    func testLinkedCompletionPreservesRejectedPartnerInputAfterCommit() throws {
        let (context, session) = try makeWorkout(names: ["A", "B"], groups: [0, 0])
        let engine = ActiveWorkoutEngine()
        let registry = ActiveSetInputRegistry()
        engine.setInputRegistry = registry
        let a = session.sortedLoggedExercises[0].sortedSets[0]
        let b = session.sortedLoggedExercises[1].sortedSets[0]
        var input = ActiveWorkoutSetInput()
        input.update("1001", for: .reps, isFocused: true)
        _ = input.commit(current: .init(weight: nil, reps: nil), weightUnit: .pounds)
        registry.register(fields: [.setReps(b.id)], commit: {}, prepareLinked: { current, previous, suggestions in
            input.preparedValuesForSetAction(current: current, weightUnit: .pounds,
                completesSet: true, isCompleted: false, previous: previous, suggestions: suggestions)
        })
        engine.previousSetsByLoggedExerciseID = [session.sortedLoggedExercises[1].id: [.init(weight: 50, reps: 12)]]
        try engine.toggleSetCompletion(a, context: context)
        XCTAssertTrue(b.isCompleted, "Direct completion also permits a blank rejected field")
        XCTAssertNil(b.reps, "Never replace rejected reps with history")
        XCTAssertEqual(b.weight, 50, "Other empty fields still fill normally")
    }

    func testExtraSetsAndUngroupedExercisesCompleteAlone() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, nil], setCount: 2)
        let engine = ActiveWorkoutEngine()
        let exercises = session.sortedLoggedExercises
        try engine.addSet(to: exercises[0], context: context)

        try engine.toggleSetCompletion(exercises[0].sortedSets[2], context: context)
        XCTAssertFalse(exercises[1].sortedSets.contains(where: \.isCompleted))

        try engine.toggleSetCompletion(exercises[1].sortedSets[0], context: context)
        XCTAssertTrue(exercises[0].sortedSets[0].isCompleted)
        XCTAssertFalse(exercises[2].sortedSets[0].isCompleted, "Ungrouped exercises are not in the round")
    }

    func testChoosingAnRPECompletesTheRoundToo() throws {
        let (context, session) = try makeWorkout(names: ["A", "B"], groups: [0, 0], setCount: 1)
        let engine = ActiveWorkoutEngine()
        let exercises = session.sortedLoggedExercises
        try engine.applyActiveSetRPESelection(
            exercises[1].sortedSets[0], rpe: 8, preparedValues: .init(weight: 100, reps: 5), context: context
        )
        XCTAssertTrue(exercises[0].sortedSets[0].isCompleted)
    }

    func testFailedRoundSaveRestoresPartnersAndRetryCompletesTheRound() throws {
        let (context, session) = try makeWorkout(names: ["A", "B"], groups: [0, 0], setCount: 1)
        let engine = ActiveWorkoutEngine(reportSetSaveFailure: { _ in })
        let exercises = session.sortedLoggedExercises
        let partner = exercises[1].sortedSets[0]
        let partnerUpdatedAt = partner.updatedAt
        let sessionUpdatedAt = session.updatedAt
        engine.previousSetsByLoggedExerciseID = [exercises[1].id: [PreviousSetPerformance(weight: 60, reps: 10)]]

        XCTAssertThrowsError(try engine.toggleSetCompletion(
            exercises[0].sortedSets[0], context: context, save: { _ in throw CocoaError(.fileWriteUnknown) }
        ))
        XCTAssertFalse(partner.isCompleted)
        XCTAssertNil(partner.weight)
        XCTAssertEqual(partner.updatedAt, partnerUpdatedAt)
        XCTAssertEqual(session.updatedAt, sessionUpdatedAt)

        try engine.retrySetSave(in: session, context: context)
        XCTAssertTrue(partner.isCompleted)
        XCTAssertEqual(partner.weight, 60)
    }

    func testSheetMovesSupersetsAsBlocksAndKeepsGroupingThroughRemovalsAndAdditions() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C", "D", "E"], groups: [nil, 0, 0, 1, 1])
        let engine = ActiveWorkoutEngine()
        let library = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(library)
        try context.save()
        let ids = session.sortedLoggedExercises.map(\.id)
        let pairGroup = session.sortedLoggedExercises[1].supersetGroupID

        var draft = WorkoutExerciseListDraft(session: session)
        XCTAssertEqual(draft.exercises.map(\.supersetGroupID), session.sortedLoggedExercises.map(\.supersetGroupID))
        draft.append([library])
        let addition = draft.additions[0].id
        draft.orderedIDs = [ids[3], ids[4], ids[0], ids[1], ids[2], addition]
        draft.orderedIDs.removeAll { $0 == ids[4] }
        try engine.applyExerciseListChanges(
            in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline,
            additions: draft.additions, context: context
        )

        let result = session.sortedLoggedExercises
        XCTAssertEqual(result.map(\.exerciseSnapshotName), ["D", "A", "B", "C", "Curl"])
        XCTAssertNil(result[0].supersetGroupID, "Removal to one exercise drops the group")
        XCTAssertEqual(result[2].supersetGroupID, pairGroup)
        XCTAssertEqual(result[3].supersetGroupID, pairGroup)
        XCTAssertNil(result[4].supersetGroupID, "Additions don't join a superset")
    }

    func testAddingExercisesAsASupersetGroupsOnlyTheNewOnesInOneSave() throws {
        let (context, session) = try makeWorkout(names: ["A", "B"], groups: [0, 0])
        let engine = ActiveWorkoutEngine()
        let existingGroup = session.sortedLoggedExercises[0].supersetGroupID
        let curl = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        let raise = Exercise(name: "Raise", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .shoulders)
        context.insert(curl)
        context.insert(raise)
        try context.save()
        var saveCount = 0

        let added = try engine.addExercises([curl, raise], to: session, asSuperset: true, context: context, save: {
            saveCount += 1
            try $0.save()
        })

        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.exerciseSnapshotName), ["A", "B", "Curl", "Raise"])
        XCTAssertTrue(grouped(session, [2, 3]))
        XCTAssertNotEqual(added[0].supersetGroupID, existingGroup, "New exercises don't join the superset above")
        XCTAssertTrue(grouped(session, [0, 1]))
    }

    func testAddingAsASupersetLeavesASingleNewExerciseUngrouped() throws {
        let (context, session) = try makeWorkout(names: ["A"])
        let engine = ActiveWorkoutEngine()
        let existing = try XCTUnwrap(session.sortedLoggedExercises[0].exercise)
        let curl = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        context.insert(curl)
        try context.save()

        let added = try engine.addExercises([existing, curl], to: session, asSuperset: true, context: context)

        XCTAssertEqual(added.map(\.exerciseSnapshotName), ["Curl"])
        XCTAssertNil(added[0].supersetGroupID, "One new exercise is never a superset")
    }

    func testAddingWithoutSupersetLeavesNewExercisesUngrouped() throws {
        let (context, session) = try makeWorkout(names: ["A"])
        let engine = ActiveWorkoutEngine()
        let curl = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        let raise = Exercise(name: "Raise", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .shoulders)
        context.insert(curl)
        context.insert(raise)
        try context.save()

        let added = try engine.addExercises([curl, raise], to: session, context: context)

        XCTAssertEqual(added.map(\.supersetGroupID), [nil, nil])
    }

    func testTogglingALinkJoinsMergesAndSplits() {
        let (a, b) = (UUID(), UUID())
        var fresh = (0..<20).map { _ in UUID() }.makeIterator()
        func toggled(_ ids: [UUID?], below upper: Int) -> [UUID?] {
            SupersetGrouping.togglingLink(ids, below: upper, makeID: { fresh.next()! })
        }

        let pair = toggled([nil, nil, nil], below: 0)
        XCTAssertNotNil(pair[0])
        XCTAssertEqual(pair[0], pair[1])
        XCTAssertNil(pair[2])
        XCTAssertEqual(toggled([a, a, nil], below: 1), [a, a, a], "A single joins the superset above it")
        XCTAssertEqual(toggled([a, a, b, b], below: 1), [a, a, a, a], "The upper superset's id wins a merge")

        XCTAssertEqual(toggled([a, a], below: 0), [nil, nil])
        let splitTrio = toggled([a, a, a, a], below: 1)
        XCTAssertEqual(Array(splitTrio[0...1]), [a, a])
        XCTAssertNotNil(splitTrio[2])
        XCTAssertNotEqual(splitTrio[2], a)
        XCTAssertEqual(splitTrio[2], splitTrio[3])
        XCTAssertEqual(toggled([a, a, a], below: 1), [a, a, nil])
        let splitFirst = toggled([a, a, a], below: 0)
        XCTAssertNil(splitFirst[0])
        XCTAssertNotNil(splitFirst[1])
        XCTAssertEqual(splitFirst[1], splitFirst[2])
    }

    func testMovingAnExerciseJoinsStaysInOrLeavesASuperset() {
        let (a, b) = (UUID(), UUID())
        func moved(_ ids: [UUID?], _ source: Int, _ destination: Int) -> SupersetGrouping.Arrangement {
            SupersetGrouping.movingExercise(ids, from: source, to: destination)
        }

        // A single dropped between two members joins their superset.
        XCTAssertEqual(moved([nil, a, a], 0, 1), .init(order: [1, 0, 2], groupIDs: [a, a, a]))
        // Beside a superset but not inside it, a single stays single.
        XCTAssertEqual(moved([a, a, nil], 2, 0).groupIDs, [nil, a, a])
        // A member reorders within its superset, ends included.
        XCTAssertEqual(moved([a, a, a, nil], 0, 2), .init(order: [1, 2, 0, 3], groupIDs: [a, a, a, nil]))
        // Dragged clear of it, a member leaves, and a superset left with one is ungrouped.
        XCTAssertEqual(moved([a, a, nil, nil], 0, 3).groupIDs, [nil, nil, nil, nil])
        // Between two members of another superset, it joins that one instead.
        XCTAssertEqual(moved([a, a, a, b, b], 0, 3).groupIDs, [a, a, b, b, b])
        XCTAssertEqual(moved([nil], 0, 0), .init(order: [0], groupIDs: [nil]))
        // At the list's end there's no row to pass, so going past the superset's edge leaves it.
        let pastEnd = SupersetGrouping.movingExercise([nil, a, a, a], from: 3, to: 3, leavesSuperset: true)
        XCTAssertEqual(pastEnd.groupIDs, [nil, a, a, nil])
        let pastStart = SupersetGrouping.movingExercise([a, a, nil], from: 1, to: 0, leavesSuperset: true)
        XCTAssertEqual(pastStart.groupIDs, [nil, nil, nil])
    }

    func testMovingABlockKeepsSupersetsWholeAndApart() {
        let (a, b) = (UUID(), UUID())
        let result = SupersetGrouping.movingBlock([nil, a, a, b, b], from: 1, to: 0)
        XCTAssertEqual(result, .init(order: [1, 2, 0, 3, 4], groupIDs: [a, a, nil, b, b]))
        // Two supersets swapped stay two supersets.
        let swapped = SupersetGrouping.movingBlock([a, a, b, b], from: 1, to: 0)
        XCTAssertEqual(swapped.order, [2, 3, 0, 1])
        XCTAssertEqual(swapped.groupIDs, [b, b, a, a])
    }

    func testSameSupersetsIgnoresTheIDsThemselves() {
        let (a, b) = (UUID(), UUID())
        XCTAssertTrue(SupersetGrouping.sameSupersets([a, a, nil], [b, b, nil]))
        XCTAssertTrue(SupersetGrouping.sameSupersets([a, nil, nil], [nil, nil, b]), "Lone ids are singles")
        XCTAssertFalse(SupersetGrouping.sameSupersets([a, a, nil], [nil, b, b]))
        XCTAssertFalse(SupersetGrouping.sameSupersets([a, a, a], [a, a, b]))
    }

    func testDraftHasChangesOnlyWhenSavingWouldChangeTheWorkout() throws {
        let (_, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, nil])
        var draft = WorkoutExerciseListDraft(session: session)
        XCTAssertFalse(draft.hasChanges)
        let groups = draft.exercises.map(\.supersetGroupID)
        // Splitting and rejoining gives the superset a new id but the same shape.
        draft.regroup(SupersetGrouping.togglingLink(groups, below: 0))
        XCTAssertTrue(draft.hasChanges)
        draft.regroup(SupersetGrouping.togglingLink(draft.exercises.map(\.supersetGroupID), below: 0))
        XCTAssertFalse(draft.hasChanges)
        draft.orderedIDs.removeLast()
        XCTAssertTrue(draft.hasChanges)
    }

    func testSheetSavesLinksWithAdditionsOrderAndRemovalsInOneChange() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C", "D"], groups: [0, 0, nil, nil])
        let engine = ActiveWorkoutEngine()
        let curl = Exercise(name: "Curl", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .biceps)
        let raise = Exercise(name: "Raise", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .shoulders)
        context.insert(curl)
        context.insert(raise)
        try context.save()
        let ids = session.sortedLoggedExercises.map(\.id)

        var draft = WorkoutExerciseListDraft(session: session)
        draft.append([curl, raise], asSuperset: true)
        XCTAssertEqual(draft.exercises[4].supersetGroupID, draft.exercises[5].supersetGroupID)
        XCTAssertNotNil(draft.exercises[4].supersetGroupID)
        draft.orderedIDs.removeAll { $0 == ids[3] }
        draft.regroup(SupersetGrouping.togglingLink(draft.exercises.map(\.supersetGroupID), below: 0))
        XCTAssertNil(draft.exercises[0].supersetGroupID)
        draft.regroup(SupersetGrouping.togglingLink(draft.exercises.map(\.supersetGroupID), below: 2))
        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), draft.baseline, "Linking only touches the draft")

        try engine.applyExerciseListChanges(
            in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline,
            additions: draft.additions, supersetGroupIDs: draft.supersetGroupIDs, context: context
        )

        let result = session.sortedLoggedExercises
        XCTAssertEqual(result.map(\.exerciseSnapshotName), ["A", "B", "C", "Curl", "Raise"])
        XCTAssertNil(result[0].supersetGroupID)
        XCTAssertNil(result[1].supersetGroupID)
        XCTAssertTrue(grouped(session, [2, 3, 4]))
        XCTAssertTrue(result[0].hasLocalSupersetChange, "Clearing a group must sync")
        XCTAssertTrue(result[2].hasLocalSupersetChange)
        XCTAssertTrue(result[4].hasLocalSupersetChange)
    }

    func testSheetWithoutLinkChangesLeavesExercisesUntouched() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, nil])
        let engine = ActiveWorkoutEngine()
        let before = WorkoutExerciseListSnapshot(session: session)
        let draft = WorkoutExerciseListDraft(session: session)

        try engine.applyExerciseListChanges(
            in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline,
            supersetGroupIDs: draft.supersetGroupIDs, context: context
        )

        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), before)
        XCTAssertFalse(session.sortedLoggedExercises[0].hasLocalSupersetChange)
    }

    func testSheetFailedSaveRestoresLinks() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"])
        let engine = ActiveWorkoutEngine()
        var draft = WorkoutExerciseListDraft(session: session)
        draft.regroup(SupersetGrouping.togglingLink([nil, nil, nil], below: 0))

        XCTAssertThrowsError(try engine.applyExerciseListChanges(
            in: session, orderedIDs: draft.orderedIDs, baseline: draft.baseline,
            supersetGroupIDs: draft.supersetGroupIDs, context: context,
            save: { _ in throw CocoaError(.fileWriteUnknown) }
        ))

        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), draft.baseline)
        XCTAssertFalse(session.sortedLoggedExercises[0].hasLocalSupersetChange)
    }

    func testSheetFailedSaveRestoresGroupingAndStaleGroupingRejectsTheDraft() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, nil])
        let engine = ActiveWorkoutEngine()
        let ids = session.sortedLoggedExercises.map(\.id)
        let draft = WorkoutExerciseListDraft(session: session)

        XCTAssertThrowsError(try engine.applyExerciseListChanges(
            in: session, orderedIDs: [ids[0], ids[2]], baseline: draft.baseline, context: context,
            save: { _ in throw CocoaError(.fileWriteUnknown) }
        ))
        XCTAssertEqual(WorkoutExerciseListSnapshot(session: session), draft.baseline)

        try engine.changeSuperset(.joinPrevious, for: session.sortedLoggedExercises[2], context: context)
        XCTAssertThrowsError(try engine.applyExerciseListChanges(
            in: session, orderedIDs: [ids[2], ids[0], ids[1]], baseline: draft.baseline, context: context,
            save: { _ in XCTFail("A stale draft must not save") }
        )) { XCTAssertEqual($0 as? ActiveWorkoutEngineError, .invalidExerciseReorder) }
        XCTAssertTrue(grouped(session, [0, 1, 2]))
    }

    func testOrdersThatSplitASupersetAreNormalized() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, nil])
        let engine = ActiveWorkoutEngine()
        let ids = session.sortedLoggedExercises.map(\.id)
        try engine.reorderLoggedExercises(in: session, orderedIDs: [ids[0], ids[2], ids[1]], context: context)
        XCTAssertTrue(session.sortedLoggedExercises.allSatisfy { $0.supersetGroupID == nil })
    }

    func testStartingFromAPastWorkoutCopiesGroupingWithFreshIDs() throws {
        let (context, past) = try makeWorkout(names: ["A", "B", "C", "D"], groups: [0, 0, nil, 1], status: .completed)
        let engine = ActiveWorkoutEngine()
        let copy = try engine.startWorkout(fromPast: past, context: context)
        let copied = copy.sortedLoggedExercises
        XCTAssertNotNil(copied[0].supersetGroupID)
        XCTAssertEqual(copied[0].supersetGroupID, copied[1].supersetGroupID)
        XCTAssertNotEqual(copied[0].supersetGroupID, past.sortedLoggedExercises[0].supersetGroupID)
        XCTAssertNil(copied[2].supersetGroupID)
        XCTAssertNil(copied[3].supersetGroupID, "A lone stored id is not copied")
    }

    func testFinishingAndEditingACompletedWorkoutPreserveGrouping() throws {
        let (context, session) = try makeWorkout(names: ["A", "B", "C"], groups: [0, 0, 0], owner: "owner")
        let engine = ActiveWorkoutEngine()
        let lone = UUID()
        session.sortedLoggedExercises[2].supersetGroupID = lone
        try context.save()
        let groups = session.sortedLoggedExercises.map(\.supersetGroupID)
        try engine.finishWorkout(session, ownerTokenIdentifier: "owner", context: context)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.supersetGroupID), groups)

        var draft = CompletedWorkoutEditDraft(session: session)
        draft.exercises[0].notes = "Edited"
        draft.exercises[1].sets.removeLast()
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft, for: session, ownerTokenIdentifier: "owner", context: context
        )
        XCTAssertEqual(session.sortedLoggedExercises[0].notes, "Edited")
        XCTAssertEqual(session.sortedLoggedExercises.map(\.supersetGroupID), groups)
    }

    func testGroupingSurvivesRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        var groups: [UUID?] = []
        do {
            let container = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: url)
            let session = try insertWorkout(names: ["A", "B", "C"], groups: [0, 0, nil], into: container.mainContext)
            groups = session.sortedLoggedExercises.map(\.supersetGroupID)
        }
        let relaunched = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: url)
        let session = try XCTUnwrap(relaunched.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.supersetGroupID), groups)
        XCTAssertNotNil(groups[0])
    }

    func testStoreFromBeforeSupersetsUpgradesWithExercisesUngrouped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")

        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: BarosSchema.models))
        let legacy = try XCTUnwrap(model.copy() as? NSManagedObjectModel)
        let entity = try XCTUnwrap(legacy.entitiesByName["LoggedExercise"])
        let supersetAttributes: Set = ["supersetGroupID", "hasLocalSupersetChange"]
        entity.properties.removeAll { supersetAttributes.contains($0.name) }
        XCTAssertTrue(supersetAttributes.isDisjoint(with: entity.attributesByName.keys))

        let exerciseID = UUID()
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: legacy)
            let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
            let context = NSManagedObjectContext(.mainQueue)
            context.persistentStoreCoordinator = coordinator
            let row = NSManagedObject(entity: entity, insertInto: context)
            for attribute in entity.attributesByName.values where !attribute.isOptional && attribute.defaultValue == nil {
                row.setValue(Self.placeholder(for: attribute.attributeType), forKey: attribute.name)
            }
            row.setValue(exerciseID, forKey: "id")
            row.setValue("Legacy Row", forKey: "exerciseSnapshotName")
            try context.save()
            try coordinator.remove(store)
        }

        let container = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: url)
        let upgraded = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<LoggedExercise>()).first)
        XCTAssertEqual(upgraded.id, exerciseID)
        XCTAssertEqual(upgraded.exerciseSnapshotName, "Legacy Row")
        XCTAssertNil(upgraded.supersetGroupID)
        XCTAssertFalse(upgraded.hasLocalSupersetChange, "Upgraded rows don't claim to know their grouping")
        upgraded.supersetGroupID = UUID()
        try container.mainContext.save()
    }

    func testDownloadsDecodeWithAndWithoutTheField() throws {
        let legacy = try JSONDecoder().decode(LoggedExerciseSyncRecord.self, from: Data(Self.recordJSON(group: nil).utf8))
        XCTAssertNil(legacy.supersetGroupID)
        let explicitNull = try JSONDecoder().decode(LoggedExerciseSyncRecord.self, from: Data(Self.recordJSON(group: "null").utf8))
        XCTAssertNil(explicitNull.supersetGroupID)
        let grouped = try JSONDecoder().decode(
            LoggedExerciseSyncRecord.self, from: Data(Self.recordJSON(group: "\"abc\"").utf8)
        )
        XCTAssertEqual(grouped.supersetGroupID, "abc")
    }

    func testPullAppliesServerGrouping() async throws {
        let (context, session) = try makeWorkout(names: ["A", "B"], status: .completed, owner: "issuer|owner")
        let exercise = session.sortedLoggedExercises[1]
        let group = UUID()
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [], exercises: [], workoutSessions: [],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: exercise.id.uuidString.lowercased(),
                        createdAt: 1, updatedAt: exercise.updatedAt.timeIntervalSince1970 + 10, deletedAt: nil,
                        serverUpdatedAt: 50, sessionClientId: session.id.uuidString.lowercased(),
                        exerciseClientId: nil, orderIndex: 1, exerciseSnapshotName: "B",
                        exerciseSnapshotEquipmentRaw: "barbell", exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
                        hasSnapshotMetadata: true, notes: "", referenceNotes: nil, sourceLoggedExerciseID: nil,
                        supersetGroupID: group.uuidString.lowercased()
                    )
                ],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 50, loggedSets: 0),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]
        _ = try await SyncCoordinator(client: client).run(ownerTokenIdentifier: "issuer|owner", context: context)
        XCTAssertEqual(exercise.supersetGroupID, group)
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

    private static func placeholder(for type: NSAttributeType) -> Any? {
        switch type {
        case .UUIDAttributeType: UUID()
        case .stringAttributeType: ""
        case .dateAttributeType: Date(timeIntervalSince1970: 0)
        case .booleanAttributeType: false
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType: 0
        case .doubleAttributeType, .floatAttributeType: 0.0
        case .binaryDataAttributeType: Data()
        default: nil
        }
    }

    private static func recordJSON(group: String?) -> String {
        """
        {"clientId":"x","createdAt":1,"updatedAt":2,"deletedAt":null,"serverUpdatedAt":3,
         "sessionClientId":"s","exerciseClientId":null,"orderIndex":0,"exerciseSnapshotName":"A",
         "exerciseSnapshotEquipmentRaw":"barbell","exerciseSnapshotPrimaryMuscleGroupRaw":"chest",
         "hasSnapshotMetadata":true,"notes":"","referenceNotes":null,"sourceLoggedExerciseID":null
         \(group.map { ",\"supersetGroupID\":\($0)" } ?? "")}
        """
    }
}
