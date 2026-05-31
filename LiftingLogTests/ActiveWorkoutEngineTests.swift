import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class ActiveWorkoutEngineTests: XCTestCase {
    func testStartingBlankCreatesOneActiveSessionWithBlankSource() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()

        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.source, .blank)
        XCTAssertEqual(engine.activeSessionID, session.id)
        XCTAssertEqual(try activeSessions(in: context).count, 1)
    }

    func testStartingBlankTwiceReturnsExistingActiveSession() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()

        let first = try engine.startBlankWorkout(context: context)
        let second = try engine.startBlankWorkout(context: context)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try activeSessions(in: context).count, 1)
    }

    func testStartingBlankIgnoresTombstonedActiveSession() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let deletedActive = WorkoutSession(
            title: "Deleted Active",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank
        )
        deletedActive.markDeleted(now: Date(timeIntervalSince1970: 200))
        context.insert(deletedActive)
        try context.save()

        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 300))

        XCTAssertNotEqual(session.id, deletedActive.id)
        XCTAssertEqual(engine.activeSessionID, session.id)
        XCTAssertEqual(try activeSessions(in: context).map(\.id), [session.id])
    }

    func testStartingFromPastCopiesStructureWithPlaceholderValuesAndBlankActualSetValues() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let past = WorkoutSession(title: "Leg Day", startedAt: .now, status: .completed, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name, notes: "Use belt")
        loggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 315, reps: 5, rpe: 8, kind: .warmup, isCompleted: true),
            LoggedSet(orderIndex: 1, weight: 335, reps: 3, rpe: 9, kind: .working, isCompleted: true)
        ]
        past.loggedExercises = [loggedExercise]
        context.insert(exercise)
        context.insert(past)
        try context.save()

        let engine = ActiveWorkoutEngine()
        let newSession = try engine.startWorkout(fromPast: past, context: context)

        XCTAssertEqual(newSession.source, .pastWorkout)
        XCTAssertEqual(newSession.sourceSessionID, past.id)
        XCTAssertEqual(newSession.title, "Leg Day")
        XCTAssertEqual(newSession.loggedExercises.first?.sets.count, 2)
        let copiedExercise = try XCTUnwrap(newSession.loggedExercises.first)
        XCTAssertEqual(copiedExercise.orderIndex, 0)
        XCTAssertEqual(copiedExercise.exerciseSnapshotName, "Back Squat")
        XCTAssertEqual(copiedExercise.notes, "")

        let copiedSets = copiedExercise.sortedSets
        XCTAssertEqual(copiedSets.map(\.isCompleted), [false, false])
        XCTAssertEqual(copiedSets.map(\.kind), [.warmup, .working])
        XCTAssertEqual(copiedSets.map(\.weight), [nil, nil])
        XCTAssertEqual(copiedSets.map(\.reps), [nil, nil])
        XCTAssertEqual(copiedSets.map(\.rpe), [nil, nil])
        XCTAssertEqual(copiedSets.map(\.placeholderWeight), [315, 335])
        XCTAssertEqual(copiedSets.map(\.placeholderReps), [5, 3])
        XCTAssertEqual(copiedSets.map(\.placeholderRPE), [8, 9])
    }

    func testStartingFromPastCopiesTitleAndShowsPreviousNotesAsReferenceOnly() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Overhead Press", category: .strength, equipment: .barbell, primaryMuscle: "Shoulders")
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name, notes: "Used wrist wraps")
        let past = WorkoutSession(
            title: "Push Day",
            startedAt: .now,
            notes: "Shoulders felt rough",
            status: .completed,
            source: .blank,
            loggedExercises: [loggedExercise]
        )
        context.insert(exercise)
        context.insert(past)
        try context.save()

        let engine = ActiveWorkoutEngine()
        let newSession = try engine.startWorkout(fromPast: past, context: context)

        XCTAssertEqual(newSession.title, "Push Day")
        XCTAssertEqual(newSession.notes, "")
        XCTAssertEqual(newSession.referenceNotes, "Shoulders felt rough")
        XCTAssertEqual(newSession.loggedExercises.first?.notes, "")
        XCTAssertEqual(newSession.loggedExercises.first?.referenceNotes, "Used wrist wraps")
    }

    func testAddingExerciseAppendsOrderIndexAndFirstSet() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(squat)
        context.insert(bench)

        _ = try engine.addExercise(squat, to: session, context: context)
        let added = try engine.addExercise(bench, to: session, context: context)

        XCTAssertEqual(added.orderIndex, 1)
        XCTAssertEqual(added.sets.count, 1)
    }

    func testAddingSetCarriesPreviousValuesAsPlaceholdersAndStartsIncomplete() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        try engine.updateSet(loggedExercise.sets[0], weight: 185, reps: 5, rpe: 8, context: context)

        let newSet = try engine.addSet(to: loggedExercise, context: context)

        XCTAssertEqual(newSet.orderIndex, 1)
        XCTAssertNil(newSet.weight)
        XCTAssertNil(newSet.reps)
        XCTAssertNil(newSet.rpe)
        XCTAssertEqual(newSet.placeholderWeight, 185)
        XCTAssertEqual(newSet.placeholderReps, 5)
        XCTAssertEqual(newSet.placeholderRPE, 8)
        XCTAssertFalse(newSet.isCompleted)
    }

    func testAddingSetFromIncompleteClonedSetCarriesPlaceholderDefaultsForward() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let previousSet = loggedExercise.sets[0]
        previousSet.placeholderWeight = 185
        previousSet.placeholderReps = 5
        previousSet.placeholderRPE = 8

        let newSet = try engine.addSet(to: loggedExercise, context: context)

        XCTAssertEqual(newSet.orderIndex, 1)
        XCTAssertNil(newSet.weight)
        XCTAssertNil(newSet.reps)
        XCTAssertNil(newSet.rpe)
        XCTAssertEqual(newSet.placeholderWeight, 185)
        XCTAssertEqual(newSet.placeholderReps, 5)
        XCTAssertEqual(newSet.placeholderRPE, 8)
        XCTAssertFalse(newSet.isCompleted)
    }

    func testRemovingSetReindexesRemainingSets() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let secondSet = try engine.addSet(to: loggedExercise, context: context)
        _ = try engine.addSet(to: loggedExercise, context: context)

        try engine.removeSet(secondSet, context: context)

        XCTAssertEqual(loggedExercise.sortedSets.map(\.orderIndex), [0, 1])
        let newSet = try engine.addSet(to: loggedExercise, context: context)
        XCTAssertEqual(newSet.orderIndex, 2)
    }

    func testRemovingLoggedExerciseTombstonesExerciseAndSetsWithoutDeletingRecords() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        _ = try engine.addSet(to: loggedExercise, context: context)
        let deletedAt = Date(timeIntervalSince1970: 200)

        try engine.removeLoggedExercise(loggedExercise, context: context, now: deletedAt)

        let persistedExercises = try allLoggedExercises(in: context)
        let persistedSets = try allLoggedSets(in: context)
        XCTAssertEqual(persistedExercises.map(\.id), [loggedExercise.id])
        XCTAssertEqual(persistedSets.count, 2)
        XCTAssertEqual(loggedExercise.deletedAt, deletedAt)
        XCTAssertEqual(loggedExercise.updatedAt, deletedAt)
        XCTAssertTrue(loggedExercise.sets.allSatisfy { $0.deletedAt == deletedAt })
        XCTAssertTrue(loggedExercise.sets.allSatisfy { $0.updatedAt == deletedAt })
        XCTAssertEqual(session.loggedExercises.count, 1)
    }

    func testRemovingLoggedExerciseReindexesRemainingNonDeletedSiblings() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let firstExercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        let secondExercise = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let thirdExercise = Exercise(name: "Deadlift", category: .strength, equipment: .barbell, primaryMuscle: "Back")
        context.insert(firstExercise)
        context.insert(secondExercise)
        context.insert(thirdExercise)
        let first = try engine.addExercise(firstExercise, to: session, context: context)
        let removed = try engine.addExercise(secondExercise, to: session, context: context)
        let third = try engine.addExercise(thirdExercise, to: session, context: context)

        try engine.removeLoggedExercise(removed, context: context, now: Date(timeIntervalSince1970: 300))

        let activeSiblings = session.loggedExercises
            .filter { !$0.isDeleted }
            .sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(activeSiblings.map(\.id), [first.id, third.id])
        XCTAssertEqual(activeSiblings.map(\.orderIndex), [0, 1])
        XCTAssertEqual(removed.orderIndex, 1)
        XCTAssertEqual(try allLoggedExercises(in: context).count, 3)
    }

    func testAddingExerciseAfterRemovingLastExerciseUsesNextVisibleOrderIndex() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let firstExercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        let removedExercise = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let replacementExercise = Exercise(name: "Deadlift", category: .strength, equipment: .barbell, primaryMuscle: "Back")
        context.insert(firstExercise)
        context.insert(removedExercise)
        context.insert(replacementExercise)
        _ = try engine.addExercise(firstExercise, to: session, context: context)
        let removed = try engine.addExercise(removedExercise, to: session, context: context)
        try engine.removeLoggedExercise(removed, context: context, now: Date(timeIntervalSince1970: 500))

        let replacement = try engine.addExercise(replacementExercise, to: session, context: context)

        XCTAssertEqual(replacement.orderIndex, 1)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1])
        XCTAssertEqual(try allLoggedExercises(in: context).count, 3)
    }

    func testRemovingSetTombstonesSetAndReindexesRemainingNonDeletedSiblings() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let firstSet = loggedExercise.sets[0]
        let removedSet = try engine.addSet(to: loggedExercise, context: context)
        let thirdSet = try engine.addSet(to: loggedExercise, context: context)
        let deletedAt = Date(timeIntervalSince1970: 400)

        try engine.removeSet(removedSet, context: context, now: deletedAt)

        let persistedSets = try allLoggedSets(in: context)
        let activeSets = loggedExercise.sets
            .filter { !$0.isDeleted }
            .sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(persistedSets.count, 3)
        XCTAssertEqual(removedSet.deletedAt, deletedAt)
        XCTAssertEqual(removedSet.updatedAt, deletedAt)
        XCTAssertEqual(activeSets.map(\.id), [firstSet.id, thirdSet.id])
        XCTAssertEqual(activeSets.map(\.orderIndex), [0, 1])
        XCTAssertEqual(removedSet.orderIndex, 1)
    }

    func testExerciseCardSetProgressIgnoresTombstonedSets() throws {
        let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let completedSet = LoggedSet(orderIndex: 0, isCompleted: true)
        let deletedCompletedSet = LoggedSet(orderIndex: 1, isCompleted: true)
        let openSet = LoggedSet(orderIndex: 2, isCompleted: false)
        deletedCompletedSet.markDeleted(now: Date(timeIntervalSince1970: 600))
        loggedExercise.sets = [completedSet, deletedCompletedSet, openSet]

        let progress = ExerciseCardView.setProgress(for: loggedExercise)

        XCTAssertEqual(progress.completed, 1)
        XCTAssertEqual(progress.total, 2)
        XCTAssertFalse(progress.isComplete)
    }

    func testCompletingSetUpdatesMetrics() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        try engine.updateSet(set, weight: 200, reps: 5, rpe: 8, context: context)

        try engine.toggleSetCompletion(set, context: context, now: Date(timeIntervalSince1970: 200))

        let metrics = WorkoutMetrics(session: session, now: Date(timeIntervalSince1970: 260))
        XCTAssertEqual(metrics.completedSetCount, 1)
        XCTAssertEqual(metrics.completedVolume, 1000)
    }

    func testCompletingSetCommitsBlankWeightRepsAndRPEFromPlaceholders() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        set.placeholderWeight = 185
        set.placeholderReps = 5
        set.placeholderRPE = 8

        try engine.toggleSetCompletion(set, context: context, now: Date(timeIntervalSince1970: 300))

        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.weight, 185)
        XCTAssertEqual(set.reps, 5)
        XCTAssertEqual(set.rpe, 8)
    }

    func testCompletingSetDoesNotOverwriteManualWeightRepsOrRPEWithPlaceholders() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        set.placeholderWeight = 185
        set.placeholderReps = 5
        set.placeholderRPE = 7
        try engine.updateSet(set, weight: 195, reps: 4, rpe: 8.5, context: context)

        try engine.toggleSetCompletion(set, context: context, now: Date(timeIntervalSince1970: 300))

        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.weight, 195)
        XCTAssertEqual(set.reps, 4)
        XCTAssertEqual(set.rpe, 8.5)
    }

    func testUncheckingCompletedSetDoesNotApplyPlaceholders() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        set.placeholderWeight = 185
        set.placeholderReps = 5
        try engine.updateSet(set, weight: 195, reps: 4, rpe: nil, context: context)
        try engine.toggleSetCompletion(set, context: context, now: Date(timeIntervalSince1970: 300))

        try engine.toggleSetCompletion(set, context: context, now: Date(timeIntervalSince1970: 360))

        XCTAssertFalse(set.isCompleted)
        XCTAssertEqual(set.weight, 195)
        XCTAssertEqual(set.reps, 4)
        XCTAssertNil(set.completedAt)
    }

    func testUpdatingWorkoutTitleAllowsEmptyDraftWhileEditing() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)

        try engine.updateWorkoutTitle("", session: session, context: context)

        XCTAssertEqual(session.title, "")
    }

    func testFinalizingWorkoutTitleAppliesDefaultForBlankDraft() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        try engine.updateWorkoutTitle("   ", session: session, context: context)

        try engine.finalizeWorkoutTitle(session, context: context)

        XCTAssertEqual(session.title, "Workout")
    }

    func testFinishingMovesSessionOutOfActiveStateAndIntoHistory() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        try engine.updateWorkoutTitle("", session: session, context: context)

        try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 220))

        XCTAssertNil(engine.activeSessionID)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.title, "Workout")
        XCTAssertEqual(session.durationSeconds, 120)
        XCTAssertEqual(try activeSessions(in: context).count, 0)
        XCTAssertEqual(try completedSessions(in: context).count, 1)
    }

    func testDiscardedSessionsDoNotAppearInCompletedHistoryFetches() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)

        try engine.discardWorkout(session, context: context)

        XCTAssertEqual(try activeSessions(in: context).count, 0)
        XCTAssertEqual(try completedSessions(in: context).count, 0)
    }

    func testReorderingLoggedExercisesUpdatesVisibleOrderIndexes() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        let deadlift = Exercise(name: "Conventional Deadlift", category: .strength, equipment: .barbell, primaryMuscle: "Posterior Chain")
        context.insert(squat)
        context.insert(bench)
        context.insert(deadlift)
        let first = try engine.addExercise(squat, to: session, context: context)
        let second = try engine.addExercise(bench, to: session, context: context)
        let third = try engine.addExercise(deadlift, to: session, context: context)

        try engine.reorderLoggedExercises(
            in: session,
            orderedIDs: [third.id, first.id, second.id],
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1, 2])
        XCTAssertEqual(third.updatedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(first.updatedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(second.updatedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(session.updatedAt, Date(timeIntervalSince1970: 200))
    }

    func testReorderingLoggedExercisesPreservesExerciseData() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(squat)
        context.insert(bench)
        let first = try engine.addExercise(squat, to: session, context: context)
        let second = try engine.addExercise(bench, to: session, context: context)
        first.notes = "Keep torso upright"
        first.referenceNotes = "Use belt"
        let firstSet = first.sortedSets[0]
        firstSet.weight = 315
        firstSet.reps = 5
        firstSet.rpe = 8
        firstSet.placeholderWeight = 305
        firstSet.placeholderReps = 5
        firstSet.placeholderRPE = 7.5
        firstSet.isCompleted = true

        try engine.reorderLoggedExercises(in: session, orderedIDs: [second.id, first.id], context: context)

        let movedFirst = try XCTUnwrap(session.sortedLoggedExercises.last)
        XCTAssertEqual(movedFirst.id, first.id)
        XCTAssertEqual(movedFirst.notes, "Keep torso upright")
        XCTAssertEqual(movedFirst.referenceNotes, "Use belt")
        XCTAssertEqual(movedFirst.sortedSets.map(\.id), [firstSet.id])
        XCTAssertEqual(movedFirst.sortedSets[0].weight, 315)
        XCTAssertEqual(movedFirst.sortedSets[0].reps, 5)
        XCTAssertEqual(movedFirst.sortedSets[0].rpe, 8)
        XCTAssertEqual(movedFirst.sortedSets[0].placeholderWeight, 305)
        XCTAssertEqual(movedFirst.sortedSets[0].placeholderReps, 5)
        XCTAssertEqual(movedFirst.sortedSets[0].placeholderRPE, 7.5)
        XCTAssertTrue(movedFirst.sortedSets[0].isCompleted)
    }

    func testReorderingLoggedExercisesRejectsInvalidIDsWithoutMutation() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        context.insert(squat)
        context.insert(bench)
        let first = try engine.addExercise(squat, to: session, context: context)
        let second = try engine.addExercise(bench, to: session, context: context)
        let originalIDs = session.sortedLoggedExercises.map(\.id)
        let originalIndexes = session.sortedLoggedExercises.map(\.orderIndex)

        XCTAssertThrowsError(
            try engine.reorderLoggedExercises(
                in: session,
                orderedIDs: [second.id, UUID()],
                context: context,
                now: Date(timeIntervalSince1970: 300)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutEngineError, .invalidExerciseReorder)
        }

        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), originalIDs)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), originalIndexes)
        XCTAssertEqual(first.orderIndex, 0)
        XCTAssertEqual(second.orderIndex, 1)
    }

    func testReorderingLoggedExercisesExcludesTombstonedExercises() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        let deadlift = Exercise(name: "Conventional Deadlift", category: .strength, equipment: .barbell, primaryMuscle: "Posterior Chain")
        context.insert(squat)
        context.insert(bench)
        context.insert(deadlift)
        let first = try engine.addExercise(squat, to: session, context: context)
        let removed = try engine.addExercise(bench, to: session, context: context)
        let third = try engine.addExercise(deadlift, to: session, context: context)
        removed.markDeleted(now: Date(timeIntervalSince1970: 150))

        try engine.reorderLoggedExercises(
            in: session,
            orderedIDs: [third.id, first.id],
            context: context,
            now: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [third.id, first.id])
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1])
        XCTAssertEqual(removed.orderIndex, 1)
        XCTAssertEqual(removed.deletedAt, Date(timeIntervalSince1970: 150))
        XCTAssertEqual(try allLoggedExercises(in: context).count, 3)
    }

    private func activeSessions(in context: ModelContext) throws -> [WorkoutSession] {
        WorkoutSession.visibleActiveSessions(from: try context.fetch(FetchDescriptor<WorkoutSession>()))
    }

    private func completedSessions(in context: ModelContext) throws -> [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(from: try context.fetch(FetchDescriptor<WorkoutSession>()))
    }

    private func allLoggedExercises(in context: ModelContext) throws -> [LoggedExercise] {
        try context.fetch(FetchDescriptor<LoggedExercise>())
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func allLoggedSets(in context: ModelContext) throws -> [LoggedSet] {
        try context.fetch(FetchDescriptor<LoggedSet>())
            .sorted { $0.orderIndex < $1.orderIndex }
    }
}
