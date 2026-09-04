import SwiftData
import XCTest
@testable import Baros

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

    func testStartingFromPastCopiesStructureWithBlankActualSetValues() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let past = WorkoutSession(title: "Leg Day", startedAt: .now, status: .completed, source: .blank)
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.smithMachine.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.glutes.rawValue,
            notes: "Use belt"
        )
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
        XCTAssertEqual(copiedExercise.exerciseSnapshotEquipmentRaw, "smithMachine")
        XCTAssertEqual(copiedExercise.exerciseSnapshotPrimaryMuscleGroupRaw, "glutes")
        XCTAssertEqual(copiedExercise.notes, "")
        XCTAssertEqual(copiedExercise.sourceLoggedExerciseID, loggedExercise.id)

        let copiedSets = copiedExercise.sortedSets
        XCTAssertEqual(copiedSets.map(\.isCompleted), [false, false])
        XCTAssertEqual(copiedSets.map(\.kind), [.warmup, .working])
        XCTAssertEqual(copiedSets.map(\.weight), [nil, nil])
        XCTAssertEqual(copiedSets.map(\.reps), [nil, nil])
        XCTAssertEqual(copiedSets.map(\.rpe), [nil, nil])
    }

    func testStartingFromPastLeavesReferenceNotesNil() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Overhead Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .shoulders)
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
        XCTAssertNil(newSession.referenceNotes)
        XCTAssertEqual(newSession.loggedExercises.first?.notes, "")
        XCTAssertNil(newSession.loggedExercises.first?.referenceNotes)
    }

    func testStartingFromPastReturnsExistingActiveSessionWithoutCloning() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Overhead Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .shoulders)
        let pastLoggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        pastLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 135, reps: 5, rpe: 8, isCompleted: true)
        ]
        let past = WorkoutSession(
            title: "Push Day",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            loggedExercises: [pastLoggedExercise]
        )
        let existingActive = WorkoutSession(
            title: "Already Active",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .blank
        )
        context.insert(exercise)
        context.insert(past)
        context.insert(existingActive)
        try context.save()

        let engine = ActiveWorkoutEngine()
        let returned = try engine.startWorkout(fromPast: past, context: context)

        XCTAssertEqual(returned.id, existingActive.id)
        XCTAssertEqual(engine.activeSessionID, existingActive.id)
        XCTAssertEqual(try activeSessions(in: context).map(\.id), [existingActive.id])
        XCTAssertTrue(existingActive.loggedExercises.isEmpty)
    }

    func testStartingFromPastRejectsSessionOutsideCurrentOwnerScope() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerBSession = WorkoutSession(
            title: "Owner B Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "issuer|owner_b"
        )
        context.insert(ownerBSession)
        try context.save()

        let engine = ActiveWorkoutEngine()
        XCTAssertThrowsError(
            try engine.startWorkout(
                fromPast: ownerBSession,
                ownerTokenIdentifier: "issuer|owner_a",
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutEngineError, .pastWorkoutUnavailable)
        }
        XCTAssertTrue(try activeSessions(in: context).isEmpty)
    }

    func testAddingExerciseAppendsOrderIndexAndFirstSet() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(squat)
        context.insert(bench)

        _ = try engine.addExercise(squat, to: session, context: context)
        let added = try engine.addExercise(bench, to: session, context: context)

        XCTAssertEqual(added.orderIndex, 1)
        XCTAssertEqual(added.sets.count, 1)
    }

    func testAddingSetCopiesKindOnlyAndStartsIncompleteWithBlankValues() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        try engine.updateSet(loggedExercise.sets[0], weight: 185, reps: 5, rpe: 8, context: context)
        loggedExercise.sets[0].kind = .drop

        let newSet = try engine.addSet(to: loggedExercise, context: context)

        XCTAssertEqual(newSet.orderIndex, 1)
        XCTAssertNil(newSet.weight)
        XCTAssertNil(newSet.reps)
        XCTAssertNil(newSet.rpe)
        XCTAssertEqual(newSet.kind, .drop)
        XCTAssertFalse(newSet.isCompleted)
    }

    func testFillSetFromPreviousOnlyFillsEmptyFields() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        set.reps = 8

        try engine.fillSetFromPrevious(set, previous: PreviousSetPerformance(weight: 185, reps: 5), context: context)

        XCTAssertEqual(set.weight, 185)
        XCTAssertEqual(set.reps, 8)
    }

    func testFillSetFromPreviousNoOpsWhenWeightAndRepsAlreadyExist() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        let originalUpdatedAt = Date(timeIntervalSince1970: 100)
        set.weight = 205
        set.reps = 4
        set.updatedAt = originalUpdatedAt
        try context.save()

        try engine.fillSetFromPrevious(set, previous: PreviousSetPerformance(weight: 185, reps: 5), context: context)

        XCTAssertEqual(set.weight, 205)
        XCTAssertEqual(set.reps, 4)
        XCTAssertEqual(set.updatedAt, originalUpdatedAt)
    }

    func testFillSetFromPreviousUpdatesOnlyTheSetTimestamp() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let baseline = Date(timeIntervalSince1970: 100)
        let commitDate = Date(timeIntervalSince1970: 200)
        let session = WorkoutSession(
            title: "Workout",
            startedAt: baseline,
            status: .active,
            source: .blank,
            createdAt: baseline,
            updatedAt: baseline
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            createdAt: baseline,
            updatedAt: baseline
        )
        let set = LoggedSet(orderIndex: 0, createdAt: baseline, updatedAt: baseline)
        session.loggedExercises = [loggedExercise]
        loggedExercise.sets = [set]
        context.insert(session)
        try context.save()

        try engine.fillSetFromPrevious(
            set,
            previous: PreviousSetPerformance(weight: 185, reps: 5),
            context: context,
            now: commitDate
        )

        XCTAssertEqual(set.weight, 185)
        XCTAssertEqual(set.reps, 5)
        XCTAssertEqual(set.updatedAt, commitDate)
        XCTAssertEqual(loggedExercise.updatedAt, baseline)
        XCTAssertEqual(session.updatedAt, baseline)
    }

    func testRemovingSetReindexesRemainingSets() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
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
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
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
        let firstExercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let secondExercise = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let thirdExercise = Exercise(name: "Deadlift", category: .strength, equipment: .barbell, primaryMuscleGroup: .upperBack)
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

    func testSwappingLoggedExerciseReplacesItInPlaceWithOneBlankSet() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let row = Exercise(name: "Barbell Row", category: .strength, equipment: .barbell, primaryMuscleGroup: .upperBack)
        let deadlift = Exercise(name: "Deadlift", category: .strength, equipment: .barbell, primaryMuscleGroup: .glutes)
        context.insert(squat)
        context.insert(bench)
        context.insert(row)
        context.insert(deadlift)
        let first = try engine.addExercise(squat, to: session, context: context)
        let original = try engine.addExercise(bench, to: session, context: context)
        let last = try engine.addExercise(deadlift, to: session, context: context)
        let originalFirstSet = try XCTUnwrap(original.sortedSets.first)
        originalFirstSet.weight = 225
        originalFirstSet.reps = 5
        originalFirstSet.rpe = 8
        originalFirstSet.isCompleted = true
        let originalSecondSet = try engine.addSet(to: original, context: context)
        original.notes = "Pause on the chest"
        original.referenceNotes = "Previous cue"
        try context.save()
        let swapDate = Date(timeIntervalSince1970: 500)

        let replacement = try engine.swapLoggedExercise(
            original,
            with: row,
            context: context,
            now: swapDate
        )

        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [first.id, replacement.id, last.id])
        XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1, 2])
        XCTAssertEqual(replacement.exercise?.id, row.id)
        XCTAssertEqual(replacement.exerciseSnapshotName, "Barbell Row")
        XCTAssertEqual(replacement.notes, "")
        XCTAssertNil(replacement.referenceNotes)
        XCTAssertEqual(replacement.createdAt, swapDate)
        XCTAssertEqual(replacement.updatedAt, swapDate)

        XCTAssertEqual(replacement.sortedSets.count, 1)
        let replacementSet = try XCTUnwrap(replacement.sortedSets.first)
        XCTAssertEqual(replacementSet.orderIndex, 0)
        XCTAssertNil(replacementSet.weight)
        XCTAssertNil(replacementSet.reps)
        XCTAssertNil(replacementSet.rpe)
        XCTAssertFalse(replacementSet.isCompleted)
        XCTAssertEqual(replacementSet.createdAt, swapDate)
        XCTAssertEqual(replacementSet.updatedAt, swapDate)

        XCTAssertEqual(original.deletedAt, swapDate)
        XCTAssertEqual(original.updatedAt, swapDate)
        XCTAssertEqual(originalFirstSet.deletedAt, swapDate)
        XCTAssertEqual(originalSecondSet.deletedAt, swapDate)
        XCTAssertEqual(session.updatedAt, swapDate)
    }

    func testSwappingLoggedExerciseWithItselfFailsWithoutMutation() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(bench)
        let original = try engine.addExercise(bench, to: session, context: context)
        let originalSet = try XCTUnwrap(original.sortedSets.first)
        original.notes = "Keep this note"
        originalSet.weight = 185
        originalSet.reps = 5
        try context.save()
        let sessionUpdatedAt = session.updatedAt

        XCTAssertThrowsError(
            try engine.swapLoggedExercise(
                original,
                with: bench,
                context: context,
                now: Date(timeIntervalSince1970: 500)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutEngineError, .invalidExerciseSwap)
        }

        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [original.id])
        XCTAssertEqual(original.notes, "Keep this note")
        XCTAssertNil(original.deletedAt)
        XCTAssertEqual(originalSet.weight, 185)
        XCTAssertEqual(originalSet.reps, 5)
        XCTAssertNil(originalSet.deletedAt)
        XCTAssertEqual(session.updatedAt, sessionUpdatedAt)
        XCTAssertEqual(try allLoggedExercises(in: context).count, 1)
        XCTAssertEqual(try allLoggedSets(in: context).count, 1)
    }

    func testSwappingLoggedExerciseRollsBackWhenSavingFails() throws {
        enum SaveFailure: Error {
            case expected
        }

        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let row = Exercise(name: "Barbell Row", category: .strength, equipment: .barbell, primaryMuscleGroup: .upperBack)
        context.insert(bench)
        context.insert(row)
        let original = try engine.addExercise(bench, to: session, context: context)
        let originalSet = try XCTUnwrap(original.sortedSets.first)
        let originalSecondSet = try engine.addSet(to: original, context: context)
        original.notes = "Keep this note"
        originalSet.weight = 185
        originalSet.reps = 5
        originalSecondSet.weight = 175
        originalSecondSet.reps = 8
        try context.save()
        let sessionUpdatedAt = session.updatedAt

        XCTAssertThrowsError(
            try engine.swapLoggedExercise(
                original,
                with: row,
                context: context,
                now: Date(timeIntervalSince1970: 500),
                save: { _ in throw SaveFailure.expected }
            )
        ) { error in
            XCTAssertTrue(error is SaveFailure)
        }

        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [original.id])
        XCTAssertEqual(original.notes, "Keep this note")
        XCTAssertNil(original.deletedAt)
        XCTAssertEqual(originalSet.weight, 185)
        XCTAssertEqual(originalSet.reps, 5)
        XCTAssertNil(originalSet.deletedAt)
        XCTAssertEqual(originalSecondSet.weight, 175)
        XCTAssertEqual(originalSecondSet.reps, 8)
        XCTAssertNil(originalSecondSet.deletedAt)
        XCTAssertEqual(session.updatedAt, sessionUpdatedAt)
        XCTAssertEqual(try allLoggedExercises(in: context).count, 1)
        XCTAssertEqual(try allLoggedSets(in: context).count, 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testSwappingFirstAndLastLoggedExercisesRetainsTheirPositions() throws {
        for originalIndex in [0, 2] {
            let container = try SwiftDataTestSupport.makeInMemoryContainer()
            let context = container.mainContext
            let engine = ActiveWorkoutEngine()
            let session = try engine.startBlankWorkout(context: context)
            let exercises = [
                Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads),
                Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest),
                Exercise(name: "Deadlift", category: .strength, equipment: .barbell, primaryMuscleGroup: .glutes),
            ]
            let replacementExercise = Exercise(
                name: "Barbell Row",
                category: .strength,
                equipment: .barbell,
                primaryMuscleGroup: .upperBack
            )
            for exercise in exercises {
                context.insert(exercise)
            }
            context.insert(replacementExercise)
            let originals = try exercises.map { try engine.addExercise($0, to: session, context: context) }

            let replacement = try engine.swapLoggedExercise(
                originals[originalIndex],
                with: replacementExercise,
                context: context
            )

            XCTAssertEqual(session.sortedLoggedExercises[originalIndex].id, replacement.id)
            XCTAssertEqual(session.sortedLoggedExercises.map(\.orderIndex), [0, 1, 2])
            XCTAssertEqual(
                session.sortedLoggedExercises.map(\.exerciseSnapshotName),
                originalIndex == 0
                    ? ["Barbell Row", "Bench Press", "Deadlift"]
                    : ["Back Squat", "Bench Press", "Barbell Row"]
            )
        }
    }

    func testSwappingOnlyLoggedExerciseKeepsOneVisibleExercise() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let row = Exercise(name: "Barbell Row", category: .strength, equipment: .barbell, primaryMuscleGroup: .upperBack)
        context.insert(bench)
        context.insert(row)
        let original = try engine.addExercise(bench, to: session, context: context)

        let replacement = try engine.swapLoggedExercise(original, with: row, context: context)

        XCTAssertEqual(session.sortedLoggedExercises.map(\.id), [replacement.id])
        XCTAssertEqual(replacement.orderIndex, 0)
        XCTAssertEqual(replacement.exerciseSnapshotName, "Barbell Row")
        XCTAssertEqual(replacement.sortedSets.count, 1)
        XCTAssertTrue(original.isDeleted)
    }

    func testAddingExerciseAfterRemovingLastExerciseUsesNextVisibleOrderIndex() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let firstExercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let removedExercise = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let replacementExercise = Exercise(name: "Deadlift", category: .strength, equipment: .barbell, primaryMuscleGroup: .upperBack)
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
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
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

    func testCheckmarkCommitsTypedWeightAndPreviousRepsWithOneSaveAndNoFollowUpDraft() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        let baseline = Date(timeIntervalSince1970: 100)
        let completionDate = Date(timeIntervalSince1970: 200)
        session.updatedAt = baseline
        loggedExercise.updatedAt = baseline
        set.updatedAt = baseline
        set.rpe = 8
        try context.save()
        var input = ActiveWorkoutSetInput()
        input.update("200", for: .weight, isFocused: true)
        let preparedValues = input.preparedValuesForSetAction(
            current: .init(weight: set.weight, reps: set.reps),
            weightUnit: .pounds,
            completesSet: !set.isCompleted,
            isCompleted: set.isCompleted,
            previous: .init(weight: 185, reps: 5)
        )
        var saveCount = 0

        try engine.toggleSetCompletion(
            set,
            preparedValues: preparedValues,
            context: context,
            now: completionDate,
            save: { context in
                saveCount += 1
                XCTAssertEqual(set.weight, 200)
                XCTAssertEqual(set.reps, 5)
                XCTAssertTrue(set.isCompleted)
                try context.save()
            }
        )

        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(set.rpe, 8)
        XCTAssertEqual(set.completedAt, completionDate)
        XCTAssertEqual(set.updatedAt, completionDate)
        XCTAssertEqual(loggedExercise.updatedAt, completionDate)
        XCTAssertEqual(session.updatedAt, completionDate)
        for _ in 0..<2 {
            let followUp = input.commit(current: .init(weight: set.weight, reps: set.reps), weightUnit: .pounds)
            XCTAssertFalse(followUp.shouldPersist, "Unchanged blur and disappearance must not request another save.")
        }
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testCompletingSetUpdatesMetrics() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        try engine.updateSet(set, weight: 200, reps: 5, rpe: 8, context: context)

        try engine.toggleSetCompletion(set, context: context, now: Date(timeIntervalSince1970: 200))

        let metrics = WorkoutMetrics(session: session, now: Date(timeIntervalSince1970: 260))
        XCTAssertEqual(metrics.completedSetCount, 1)
        XCTAssertEqual(metrics.completedVolume, 1000)
    }

    func testWorkoutMetricsCacheKeyChangesOnlyForMetricInputs() {
        let session = WorkoutSession(title: "Workout", startedAt: .now, status: .active, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8)
        loggedExercise.sets = [set]
        session.loggedExercises = [loggedExercise]
        let initialKey = WorkoutMetrics.CacheKey(session: session)

        session.title = "Renamed"
        session.updatedAt = session.updatedAt.addingTimeInterval(1)
        loggedExercise.notes = "Pause reps"
        set.rpe = 9

        XCTAssertEqual(WorkoutMetrics.CacheKey(session: session), initialKey)

        set.weight = 195
        XCTAssertNotEqual(WorkoutMetrics.CacheKey(session: session), initialKey)
    }

    func testCompletingSetPreservesManualWeightRepsAndRPE() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        try engine.updateSet(set, weight: 195, reps: 4, rpe: 8.5, context: context)

        try engine.toggleSetCompletion(set, context: context, now: Date(timeIntervalSince1970: 300))

        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.weight, 195)
        XCTAssertEqual(set.reps, 4)
        XCTAssertEqual(set.rpe, 8.5)
        XCTAssertEqual(set.completedAt, Date(timeIntervalSince1970: 300))
    }

    func testUpdatingActiveSetRejectsOutOfPolicyNumericValues() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let set = LoggedSet(orderIndex: 0)
        context.insert(set)

        try engine.updateSet(set, weight: 10_001, reps: 1_001, rpe: 10.1, context: context)

        XCTAssertNil(set.weight)
        XCTAssertNil(set.reps)
        XCTAssertNil(set.rpe)
    }

    func testFillingFromPreviousRejectsOutOfPolicyNumericValues() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let set = LoggedSet(orderIndex: 0)
        context.insert(set)

        try engine.fillSetFromPrevious(
            set,
            previous: PreviousSetPerformance(weight: 10_001, reps: 1_001),
            context: context
        )

        XCTAssertNil(set.weight)
        XCTAssertNil(set.reps)
    }

    func testFillingFromPreviousReplacesOutOfPolicyCurrentValues() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let set = LoggedSet(orderIndex: 0, weight: 10_001, reps: 1_001)
        context.insert(set)

        try engine.fillSetFromPrevious(
            set,
            previous: PreviousSetPerformance(weight: 185, reps: 5),
            context: context
        )

        XCTAssertEqual(set.weight, 185)
        XCTAssertEqual(set.reps, 5)
    }

    func testRPEChipsIncludeHalfStepsFromSixThroughTen() {
        XCTAssertEqual(RPEChipRow.values, [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10])
    }

    func testRPEChipSelectionCommitsPreparedValuesAndCompletesSet() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        try engine.updateSet(set, weight: 185, reps: 5, rpe: nil, context: context)
        let baseline = Date(timeIntervalSince1970: 100)
        let commitDate = Date(timeIntervalSince1970: 200)
        session.updatedAt = baseline
        loggedExercise.updatedAt = baseline
        set.updatedAt = baseline
        try context.save()

        try RPEChipSelectionAction.apply(
            value: 8.5,
            preparedValues: .init(weight: 195, reps: 4),
            to: set,
            engine: engine,
            context: context,
            now: commitDate
        )

        XCTAssertEqual(set.weight, 195)
        XCTAssertEqual(set.reps, 4)
        XCTAssertEqual(set.rpe, 8.5)
        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.completedAt, commitDate)
        XCTAssertEqual(set.updatedAt, commitDate)
        XCTAssertEqual(loggedExercise.updatedAt, commitDate)
        XCTAssertEqual(session.updatedAt, commitDate)
    }

    func testSelectingExistingRPEStillCompletesIncompleteSet() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let completionDate = Date(timeIntervalSince1970: 300)
        let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: false)
        context.insert(set)
        try context.save()

        try RPEChipSelectionAction.apply(
            value: 8,
            preparedValues: .init(weight: 185, reps: 5),
            to: set,
            engine: engine,
            context: context,
            now: completionDate
        )

        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.completedAt, completionDate)
    }

    func testChangingCompletedSetRPEPreservesOriginalCompletionDate() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let completionDate = Date(timeIntervalSince1970: 100)
        let editDate = Date(timeIntervalSince1970: 300)
        let set = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            rpe: 8,
            isCompleted: true,
            completedAt: completionDate,
            updatedAt: completionDate
        )
        context.insert(set)
        try context.save()

        try RPEChipSelectionAction.apply(
            value: 9,
            preparedValues: .init(weight: 185, reps: 5),
            to: set,
            engine: engine,
            context: context,
            now: editDate
        )

        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.completedAt, completionDate)
        XCTAssertEqual(set.rpe, 9)
        XCTAssertEqual(set.updatedAt, editDate)
    }

    func testClearingRPEPreservesCompletionStateAndDate() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let completionDate = Date(timeIntervalSince1970: 100)
        let completedSet = LoggedSet(
            orderIndex: 0,
            rpe: 8,
            isCompleted: true,
            completedAt: completionDate
        )
        let incompleteSet = LoggedSet(orderIndex: 1, rpe: 8, isCompleted: false)
        context.insert(completedSet)
        context.insert(incompleteSet)
        try context.save()

        try RPEChipSelectionAction.apply(
            value: nil,
            to: completedSet,
            engine: engine,
            context: context
        )
        try RPEChipSelectionAction.apply(
            value: nil,
            to: incompleteSet,
            engine: engine,
            context: context
        )

        XCTAssertNil(completedSet.rpe)
        XCTAssertTrue(completedSet.isCompleted)
        XCTAssertEqual(completedSet.completedAt, completionDate)
        XCTAssertNil(incompleteSet.rpe)
        XCTAssertFalse(incompleteSet.isCompleted)
        XCTAssertNil(incompleteSet.completedAt)
    }

    func testRPEAutoCompletionUsesOneSaveBoundary() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let set = LoggedSet(orderIndex: 0)
        context.insert(set)
        try context.save()
        var saveCount = 0

        try engine.applyActiveSetRPESelection(
            set,
            rpe: 8,
            preparedValues: .init(weight: 185, reps: 5),
            context: context,
            now: Date(timeIntervalSince1970: 300),
            save: { context in
                saveCount += 1
                try context.save()
            }
        )

        XCTAssertEqual(saveCount, 1)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(set.weight, 185)
        XCTAssertEqual(set.reps, 5)
        XCTAssertEqual(set.rpe, 8)
        XCTAssertTrue(set.isCompleted)
    }

    func testRepeatedRPESelectionDoesNotSaveAndCompletedEditsOnlyTouchSet() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let completionDate = Date(timeIntervalSince1970: 100)
        let editDate = Date(timeIntervalSince1970: 200)
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        try engine.updateSet(set, weight: 185, reps: 5, rpe: 8, context: context)
        try engine.toggleSetCompletion(set, context: context, now: completionDate)
        var saveCount = 0

        for rpe: Double? in [8, 9, nil, nil] {
            try engine.applyActiveSetRPESelection(
                set,
                rpe: rpe,
                preparedValues: .init(weight: 185, reps: 5),
                context: context,
                now: editDate,
                save: { context in
                    saveCount += 1
                    try context.save()
                }
            )
        }

        XCTAssertEqual(saveCount, 2, "Only changing RPE and clearing it need saves.")
        XCTAssertNil(set.rpe)
        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.completedAt, completionDate)
        XCTAssertEqual(set.updatedAt, editDate)
        XCTAssertEqual(loggedExercise.updatedAt, completionDate)
        XCTAssertEqual(session.updatedAt, completionDate)
        XCTAssertFalse(context.hasChanges)
    }

    func testUncheckingCommitsPendingEditsPreservesRPEAndClearsCompletedAt() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
        let set = loggedExercise.sets[0]
        try engine.updateSet(set, weight: 195, reps: 4, rpe: 8, context: context)
        try engine.toggleSetCompletion(set, context: context, now: Date(timeIntervalSince1970: 300))
        var input = ActiveWorkoutSetInput()
        input.update("", for: .weight, isFocused: true)
        input.update("6", for: .reps, isFocused: true)
        let preparedValues = input.preparedValuesForSetAction(
            current: .init(weight: set.weight, reps: set.reps),
            weightUnit: .pounds,
            completesSet: !set.isCompleted,
            isCompleted: set.isCompleted,
            previous: .init(weight: 185, reps: 5)
        )
        let uncheckDate = Date(timeIntervalSince1970: 360)
        var saveCount = 0

        try engine.toggleSetCompletion(
            set,
            preparedValues: preparedValues,
            context: context,
            now: uncheckDate,
            save: { context in
                saveCount += 1
                try context.save()
            }
        )

        XCTAssertEqual(saveCount, 1)
        XCTAssertFalse(set.isCompleted)
        XCTAssertNil(set.weight)
        XCTAssertEqual(set.reps, 6)
        XCTAssertEqual(set.rpe, 8)
        XCTAssertNil(set.completedAt)
        XCTAssertEqual(set.updatedAt, uncheckDate)
        XCTAssertEqual(loggedExercise.updatedAt, uncheckDate)
        XCTAssertEqual(session.updatedAt, uncheckDate)
        XCTAssertFalse(input.commit(current: preparedValues, weightUnit: .pounds).shouldPersist)
        XCTAssertFalse(context.hasChanges)
    }

    func testCheckmarkWithOnlyDraftsOrOnlyPreviousFillSavesOnce() throws {
        for usesPrevious in [false, true] {
            let container = try SwiftDataTestSupport.makeInMemoryContainer()
            let context = container.mainContext
            let engine = ActiveWorkoutEngine()
            let set = LoggedSet(orderIndex: 0)
            context.insert(set)
            try context.save()
            var input = ActiveWorkoutSetInput()
            if !usesPrevious {
                input.update("185", for: .weight, isFocused: true)
                input.update("5", for: .reps, isFocused: true)
            }
            let preparedValues = input.preparedValuesForSetAction(
                current: .init(weight: set.weight, reps: set.reps),
                weightUnit: .pounds,
                completesSet: true,
                isCompleted: false,
                previous: usesPrevious ? .init(weight: 185, reps: 5) : nil
            )
            var saveCount = 0

            try engine.toggleSetCompletion(
                set,
                preparedValues: preparedValues,
                context: context,
                save: { context in
                    saveCount += 1
                    try context.save()
                }
            )

            XCTAssertEqual(saveCount, 1)
            XCTAssertEqual(set.weight, 185)
            XCTAssertEqual(set.reps, 5)
            XCTAssertTrue(set.isCompleted)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testCheckmarkPropagatesSaveFailure() throws {
        enum SaveFailure: Error { case expected }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let set = LoggedSet(orderIndex: 0)
        container.mainContext.insert(set)

        XCTAssertThrowsError(try ActiveWorkoutEngine().toggleSetCompletion(
            set,
            preparedValues: .init(weight: 185, reps: 5),
            context: container.mainContext,
            save: { _ in throw SaveFailure.expected }
        )) { error in
            XCTAssertTrue(error is SaveFailure)
        }
    }

    func testFinalizingWorkoutTitleAppliesDefaultForBlankDraft() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        session.title = "   "

        try engine.finalizeWorkoutTitle(session, context: context)

        XCTAssertEqual(session.title, "Workout")
    }

    func testCommittingWorkoutTitleAppliesTrimmedTitleInOneSave() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let updatedAtBeforeCommit = session.updatedAt

        try engine.commitWorkoutTitle("  Push Day  ", session: session, context: context)

        XCTAssertEqual(session.title, "Push Day")
        XCTAssertGreaterThan(session.updatedAt, updatedAtBeforeCommit)
        XCTAssertFalse(context.hasChanges)
    }

    func testCommittingBlankWorkoutTitleFallsBackToDefault() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)

        try engine.commitWorkoutTitle("   ", session: session, context: context)

        XCTAssertEqual(session.title, "Workout")
        XCTAssertFalse(context.hasChanges)
    }

    func testFinishingMovesSessionOutOfActiveStateAndIntoHistory() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        session.title = ""

        try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 220))

        XCTAssertNil(engine.activeSessionID)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.title, "Workout")
        XCTAssertEqual(session.durationSeconds, 120)
        XCTAssertEqual(try activeSessions(in: context).count, 0)
        XCTAssertEqual(try completedSessions(in: context).count, 1)
    }

    func testFinishingAuthenticatedWorkoutRequestsSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let scheduler = SyncScheduler()
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"
        let session = try engine.startBlankWorkout(
            ownerTokenIdentifier: scheduler.currentOwnerTokenIdentifier,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        try engine.finishWorkout(
            session,
            syncScheduler: scheduler,
            context: context,
            now: Date(timeIntervalSince1970: 220)
        )

        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(session.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entry.ownerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testFinishingWorkoutPreservesOwnerCapturedWhenStarted() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let scheduler = SyncScheduler()
        let startedOwner = "issuer|owner_a"
        scheduler.currentOwnerTokenIdentifier = startedOwner
        let session = try engine.startBlankWorkout(
            ownerTokenIdentifier: scheduler.currentOwnerTokenIdentifier,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"
        try engine.finishWorkout(
            session,
            syncScheduler: scheduler,
            context: context,
            now: Date(timeIntervalSince1970: 220)
        )

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(session.syncOwnerTokenIdentifier, startedOwner)
        XCTAssertTrue(entries.allSatisfy { $0.ownerTokenIdentifier == startedOwner })
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testFinishingSignedOutWorkoutAfterSignInKeepsOwnerlessIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let scheduler = SyncScheduler()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_a"

        try engine.finishWorkout(
            session,
            syncScheduler: scheduler,
            context: context,
            now: Date(timeIntervalSince1970: 220)
        )

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertNil(session.syncOwnerTokenIdentifier)
        XCTAssertTrue(entries.allSatisfy { $0.ownerTokenIdentifier == nil })
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testFinishingSignedOutWorkoutWithCurrentOwnerRecordsOwnedIntent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let scheduler = SyncScheduler()
        let owner = "issuer|owner_a"
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        scheduler.currentOwnerTokenIdentifier = owner

        try engine.finishWorkout(
            session,
            ownerTokenIdentifier: scheduler.currentOwnerTokenIdentifier,
            syncScheduler: scheduler,
            context: context,
            now: Date(timeIntervalSince1970: 220)
        )

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(session.syncOwnerTokenIdentifier, owner)
        XCTAssertTrue(entries.allSatisfy { $0.ownerTokenIdentifier == owner })
        XCTAssertEqual(scheduler.requestCount, 1)
    }

    func testActiveSessionVisibilityIsScopedToCurrentOwner() throws {
        let ownerA = WorkoutSession(
            title: "Owner A",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )
        let ownerB = WorkoutSession(
            title: "Owner B",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: "issuer|owner_b"
        )
        let ownerless = WorkoutSession(
            title: "Ownerless",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .active,
            source: .blank
        )

        XCTAssertEqual(
            WorkoutSession.visibleActiveSessions(
                from: [ownerA, ownerB, ownerless],
                ownerTokenIdentifier: "issuer|owner_b"
            ).map(\.title),
            ["Owner B", "Ownerless"]
        )
        XCTAssertEqual(
            WorkoutSession.visibleActiveSessions(from: [ownerA, ownerB, ownerless]).map(\.title),
            ["Ownerless"]
        )
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
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let deadlift = Exercise(name: "Conventional Deadlift", category: .strength, equipment: .barbell, primaryMuscleGroup: .glutes)
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
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
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
        XCTAssertTrue(movedFirst.sortedSets[0].isCompleted)
    }

    func testReorderingLoggedExercisesRejectsInvalidIDsWithoutMutation() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
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
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let deadlift = Exercise(name: "Conventional Deadlift", category: .strength, equipment: .barbell, primaryMuscleGroup: .glutes)
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

    func testCommittingActiveSetDraftUpdatesOnlyChangedLeafValuesAndTimestamp() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let baseline = Date(timeIntervalSince1970: 100)
        let commitDate = Date(timeIntervalSince1970: 200)
        let session = WorkoutSession(
            title: "Workout",
            startedAt: baseline,
            status: .active,
            source: .blank,
            createdAt: baseline,
            updatedAt: baseline
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            createdAt: baseline,
            updatedAt: baseline
        )
        let set = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            rpe: 8,
            createdAt: baseline,
            updatedAt: baseline
        )
        session.loggedExercises = [loggedExercise]
        loggedExercise.sets = [set]
        context.insert(session)
        try context.save()

        let didPersist = try engine.commitActiveSetDraft(
            set,
            values: .init(weight: 195, reps: 5),
            context: context,
            now: commitDate
        )

        XCTAssertTrue(didPersist)
        XCTAssertEqual(set.weight, 195)
        XCTAssertEqual(set.reps, 5)
        XCTAssertEqual(set.rpe, 8)
        XCTAssertEqual(set.updatedAt, commitDate)
        XCTAssertEqual(loggedExercise.updatedAt, baseline)
        XCTAssertEqual(session.updatedAt, baseline)
        XCTAssertFalse(context.hasChanges)
    }

    func testCommittingUnchangedActiveSetDraftDoesNotDirtyTimestampsOrContext() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let baseline = Date(timeIntervalSince1970: 100)
        let set = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            createdAt: baseline,
            updatedAt: baseline
        )
        context.insert(set)
        try context.save()

        let didPersist = try engine.commitActiveSetDraft(
            set,
            values: .init(weight: 185, reps: 5),
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertFalse(didPersist)
        XCTAssertEqual(set.updatedAt, baseline)
        XCTAssertFalse(context.hasChanges)
    }

    func testLeafOnlyTouchDoesNotChangeParentTimestampsButGraphTouchStillCascades() {
        let baseline = Date(timeIntervalSince1970: 100)
        let leafDate = Date(timeIntervalSince1970: 200)
        let graphDate = Date(timeIntervalSince1970: 300)
        let session = WorkoutSession(
            title: "Workout",
            startedAt: baseline,
            status: .active,
            source: .blank,
            createdAt: baseline,
            updatedAt: baseline
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            createdAt: baseline,
            updatedAt: baseline
        )
        let set = LoggedSet(orderIndex: 0, createdAt: baseline, updatedAt: baseline)
        session.loggedExercises = [loggedExercise]
        loggedExercise.sets = [set]

        set.touchActiveDraft(now: leafDate)

        XCTAssertEqual(set.updatedAt, leafDate)
        XCTAssertEqual(loggedExercise.updatedAt, baseline)
        XCTAssertEqual(session.updatedAt, baseline)

        set.touch(now: graphDate)

        XCTAssertEqual(set.updatedAt, graphDate)
        XCTAssertEqual(loggedExercise.updatedAt, graphDate)
        XCTAssertEqual(session.updatedAt, graphDate)
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
