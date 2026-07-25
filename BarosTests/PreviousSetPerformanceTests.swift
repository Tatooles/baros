import SwiftData
import XCTest
@testable import Baros

@MainActor
final class PreviousSetPerformanceTests: XCTestCase {
    func testOutOfPolicyPreviousSetValuesDisplayAsRecoverableBlank() {
        let previous = PreviousSetPerformance(weight: 10_001, reps: 1_001)

        XCTAssertEqual(previous.displayText(weightUnit: .pounds), "—")
    }

    func testReturnsLastCompletedSessionSetsByIndex() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        try insertCompletedSession(
            startedAt: Date(timeIntervalSince1970: 100),
            exercise: exercise,
            sets: [(135, 10), (145, 8)],
            in: context
        )
        try insertCompletedSession(
            startedAt: Date(timeIntervalSince1970: 200),
            exercise: exercise,
            sets: [(155, 6), (160, 5), (165, 3)],
            in: context
        )

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .active,
            source: .blank
        )
        let activeLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        active.loggedExercises.append(activeLogged)
        context.insert(active)
        context.insert(activeLogged)
        for (index, pair) in [(225.0, 1), (230.0, 1), (235.0, 1)].enumerated() {
            let set = LoggedSet(
                orderIndex: index,
                weight: pair.0,
                reps: pair.1,
                kind: .working,
                isCompleted: true,
                completedAt: active.startedAt
            )
            activeLogged.sets.append(set)
            context.insert(set)
        }
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let previous = PreviousSetPerformance.lastCompletedSets(
            for: activeLogged,
            in: sessions,
            ownerTokenIdentifier: nil
        )

        XCTAssertEqual(previous, [
            PreviousSetPerformance(weight: 155, reps: 6),
            PreviousSetPerformance(weight: 160, reps: 5),
            PreviousSetPerformance(weight: 165, reps: 3),
        ])
    }

    func testReturnsEmptyWhenNoHistory() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .quads
        )
        context.insert(exercise)
        let active = WorkoutSession(title: "Today", startedAt: .now, status: .active, source: .blank)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise)
        active.loggedExercises.append(logged)
        context.insert(active)
        context.insert(logged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertTrue(
            PreviousSetPerformance.lastCompletedSets(for: logged, in: sessions, ownerTokenIdentifier: nil).isEmpty
        )
    }

    func testUsesOnlyFirstMatchingLoggedExerciseFromPreviousSession() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let previousSession = WorkoutSession(
            title: "Duplicate Bench",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let firstPrevious = LoggedExercise(orderIndex: 0, exercise: exercise)
        firstPrevious.sets.append(
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true, completedAt: previousSession.startedAt)
        )
        let secondPrevious = LoggedExercise(orderIndex: 1, exercise: exercise)
        secondPrevious.sets.append(
            LoggedSet(orderIndex: 0, weight: 195, reps: 3, isCompleted: true, completedAt: previousSession.startedAt)
        )
        previousSession.loggedExercises.append(contentsOf: [firstPrevious, secondPrevious])
        context.insert(previousSession)
        context.insert(firstPrevious)
        context.insert(secondPrevious)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .blank
        )
        let activeLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        active.loggedExercises.append(activeLogged)
        context.insert(active)
        context.insert(activeLogged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let previous = PreviousSetPerformance.lastCompletedSets(
            for: activeLogged,
            in: sessions,
            ownerTokenIdentifier: nil
        )

        XCTAssertEqual(previous, [
            PreviousSetPerformance(weight: 185, reps: 5),
        ])
    }

    func testBatchLookupUsesSinglePreviousEntryPerActiveExercise() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let squat = Exercise(
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .quads
        )
        context.insert(bench)
        context.insert(squat)

        let previousSession = WorkoutSession(
            title: "Past",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let firstBench = LoggedExercise(orderIndex: 0, exercise: bench)
        firstBench.sets.append(
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true, completedAt: previousSession.startedAt)
        )
        let secondBench = LoggedExercise(orderIndex: 1, exercise: bench)
        secondBench.sets.append(
            LoggedSet(orderIndex: 0, weight: 195, reps: 3, isCompleted: true, completedAt: previousSession.startedAt)
        )
        let previousSquat = LoggedExercise(orderIndex: 2, exercise: squat)
        previousSquat.sets.append(
            LoggedSet(orderIndex: 0, weight: 225, reps: 8, isCompleted: true, completedAt: previousSession.startedAt)
        )
        previousSession.loggedExercises.append(contentsOf: [firstBench, secondBench, previousSquat])
        context.insert(previousSession)
        context.insert(firstBench)
        context.insert(secondBench)
        context.insert(previousSquat)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .blank
        )
        let activeBench = LoggedExercise(orderIndex: 0, exercise: bench)
        let activeSquat = LoggedExercise(orderIndex: 1, exercise: squat)
        active.loggedExercises.append(contentsOf: [activeBench, activeSquat])
        context.insert(active)
        context.insert(activeBench)
        context.insert(activeSquat)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil
        )

        XCTAssertEqual(lookup[activeBench.id], [
            PreviousSetPerformance(weight: 185, reps: 5),
        ])
        XCTAssertEqual(lookup[activeSquat.id], [
            PreviousSetPerformance(weight: 225, reps: 8),
        ])
    }

    func testBatchLookupContinuesAcrossSessionsUntilAllRoutesAreFound() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let squat = Exercise(
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .quads
        )
        context.insert(bench)
        context.insert(squat)

        try insertCompletedSession(
            startedAt: Date(timeIntervalSince1970: 100),
            exercise: squat,
            sets: [(225, 8)],
            in: context
        )
        try insertCompletedSession(
            startedAt: Date(timeIntervalSince1970: 200),
            exercise: bench,
            sets: [(185, 5)],
            in: context
        )

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .active,
            source: .blank
        )
        let activeBench = LoggedExercise(orderIndex: 0, exercise: bench)
        let activeSquat = LoggedExercise(orderIndex: 1, exercise: squat)
        active.loggedExercises.append(contentsOf: [activeBench, activeSquat])
        context.insert(active)
        context.insert(activeBench)
        context.insert(activeSquat)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil
        )

        XCTAssertEqual(lookup[activeBench.id], [
            PreviousSetPerformance(weight: 185, reps: 5),
        ])
        XCTAssertEqual(lookup[activeSquat.id], [
            PreviousSetPerformance(weight: 225, reps: 8),
        ])
    }

    func testPastWorkoutLookupUsesSourceSessionInsteadOfMostRecentSession() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let selectedLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        let selectedSet = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            isCompleted: true,
            completedAt: selectedSource.startedAt
        )
        selectedLogged.sets.append(selectedSet)
        selectedSource.loggedExercises.append(selectedLogged)
        context.insert(selectedSource)
        context.insert(selectedLogged)

        let newerSession = WorkoutSession(
            title: "Newer Workout",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank
        )
        let newerLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        newerLogged.sets.append(
            LoggedSet(orderIndex: 0, weight: 225, reps: 3, isCompleted: true, completedAt: newerSession.startedAt)
        )
        newerSession.loggedExercises.append(newerLogged)
        context.insert(newerSession)
        context.insert(newerLogged)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let activeLogged = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: selectedLogged.id
        )
        activeLogged.sets.append(LoggedSet(orderIndex: 0, sourceLoggedSetID: selectedSet.id))
        active.loggedExercises.append(activeLogged)
        context.insert(active)
        context.insert(activeLogged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        XCTAssertEqual(lookup[activeLogged.id], [
            PreviousSetPerformance(weight: 185, reps: 5),
        ])
    }

    func testPastWorkoutLookupPreservesDuplicateSourceExerciseEntries() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let firstSourceBench = LoggedExercise(orderIndex: 0, exercise: exercise)
        let firstSourceSet = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            isCompleted: true,
            completedAt: selectedSource.startedAt
        )
        firstSourceBench.sets.append(firstSourceSet)
        let secondSourceBench = LoggedExercise(orderIndex: 1, exercise: exercise)
        let secondSourceSet = LoggedSet(
            orderIndex: 0,
            weight: 195,
            reps: 3,
            isCompleted: true,
            completedAt: selectedSource.startedAt
        )
        secondSourceBench.sets.append(secondSourceSet)
        selectedSource.loggedExercises.append(contentsOf: [firstSourceBench, secondSourceBench])
        context.insert(selectedSource)
        context.insert(firstSourceBench)
        context.insert(secondSourceBench)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let firstActiveBench = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: firstSourceBench.id
        )
        firstActiveBench.sets.append(LoggedSet(orderIndex: 0, sourceLoggedSetID: firstSourceSet.id))
        let secondActiveBench = LoggedExercise(
            orderIndex: 1,
            exercise: exercise,
            sourceLoggedExerciseID: secondSourceBench.id
        )
        secondActiveBench.sets.append(LoggedSet(orderIndex: 0, sourceLoggedSetID: secondSourceSet.id))
        active.loggedExercises.append(contentsOf: [firstActiveBench, secondActiveBench])
        context.insert(active)
        context.insert(firstActiveBench)
        context.insert(secondActiveBench)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        XCTAssertEqual(lookup[firstActiveBench.id], [
            PreviousSetPerformance(weight: 185, reps: 5),
        ])
        XCTAssertEqual(lookup[secondActiveBench.id], [
            PreviousSetPerformance(weight: 195, reps: 3),
        ])
    }

    func testPastWorkoutLookupKeepsSourceSetValuesAfterEarlierSetDeleted() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let sourceLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        let firstSourceSet = LoggedSet(
            orderIndex: 0, weight: 100, reps: 5, isCompleted: true, completedAt: selectedSource.startedAt
        )
        let secondSourceSet = LoggedSet(
            orderIndex: 1, weight: 110, reps: 3, isCompleted: true, completedAt: selectedSource.startedAt
        )
        let thirdSourceSet = LoggedSet(
            orderIndex: 2, weight: 120, reps: 1, isCompleted: true, completedAt: selectedSource.startedAt
        )
        sourceLogged.sets.append(contentsOf: [firstSourceSet, secondSourceSet, thirdSourceSet])
        selectedSource.loggedExercises.append(sourceLogged)
        context.insert(selectedSource)
        context.insert(sourceLogged)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let activeLogged = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: sourceLogged.id
        )
        // Simulate deleting the first cloned set: only the second and third source
        // sets remain, reindexed to active rows 0 and 1. Each keeps its stable
        // sourceLoggedSetID link, so the previous values must not shift up.
        let secondActiveSet = LoggedSet(orderIndex: 0, sourceLoggedSetID: secondSourceSet.id)
        let thirdActiveSet = LoggedSet(orderIndex: 1, sourceLoggedSetID: thirdSourceSet.id)
        activeLogged.sets.append(contentsOf: [secondActiveSet, thirdActiveSet])
        active.loggedExercises.append(activeLogged)
        context.insert(active)
        context.insert(activeLogged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        XCTAssertEqual(lookup[activeLogged.id], [
            PreviousSetPerformance(weight: 110, reps: 3),
            PreviousSetPerformance(weight: 120, reps: 1),
        ])
    }

    func testPastWorkoutLookupTreatsSetAddedAfterCloningAsHavingNoPrevious() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let sourceLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        let firstSourceSet = LoggedSet(
            orderIndex: 0, weight: 100, reps: 5, isCompleted: true, completedAt: selectedSource.startedAt
        )
        let secondSourceSet = LoggedSet(
            orderIndex: 1, weight: 110, reps: 3, isCompleted: true, completedAt: selectedSource.startedAt
        )
        let thirdSourceSet = LoggedSet(
            orderIndex: 2, weight: 120, reps: 1, isCompleted: true, completedAt: selectedSource.startedAt
        )
        sourceLogged.sets.append(contentsOf: [firstSourceSet, secondSourceSet, thirdSourceSet])
        selectedSource.loggedExercises.append(sourceLogged)
        context.insert(selectedSource)
        context.insert(sourceLogged)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let activeLogged = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: sourceLogged.id
        )
        // Clone keeps the first two source sets, the third cloned set was deleted,
        // and then a fresh set was added. The added row has no source link, so it
        // must not reuse the deleted third source set's values.
        let firstActiveSet = LoggedSet(orderIndex: 0, sourceLoggedSetID: firstSourceSet.id)
        let secondActiveSet = LoggedSet(orderIndex: 1, sourceLoggedSetID: secondSourceSet.id)
        let addedActiveSet = LoggedSet(orderIndex: 2)
        activeLogged.sets.append(contentsOf: [firstActiveSet, secondActiveSet, addedActiveSet])
        active.loggedExercises.append(activeLogged)
        context.insert(active)
        context.insert(activeLogged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        // Only the two cloned rows carry previous values; the added row (index 2)
        // falls past the array so the row renders with no previous set.
        XCTAssertEqual(lookup[activeLogged.id], [
            PreviousSetPerformance(weight: 100, reps: 5),
            PreviousSetPerformance(weight: 110, reps: 3),
        ])
    }

    func testPastWorkoutLookupDoesNotReuseSourceSetsAfterAllClonedSetsAreDeleted() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let sourceLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        sourceLogged.sets.append(contentsOf: [
            LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true, completedAt: selectedSource.startedAt),
            LoggedSet(orderIndex: 1, weight: 110, reps: 3, isCompleted: true, completedAt: selectedSource.startedAt),
        ])
        selectedSource.loggedExercises.append(sourceLogged)
        context.insert(selectedSource)
        context.insert(sourceLogged)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let activeLogged = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: sourceLogged.id
        )
        activeLogged.sets.append(LoggedSet(orderIndex: 0))
        active.loggedExercises.append(activeLogged)
        context.insert(active)
        context.insert(activeLogged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        XCTAssertEqual(lookup[activeLogged.id], [])
    }

    func testPastWorkoutLookupUsesHistoryForExerciseAddedAfterCloning() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let sourceBench = LoggedExercise(orderIndex: 0, exercise: exercise)
        let sourceBenchSet = LoggedSet(
            orderIndex: 0, weight: 185, reps: 5, isCompleted: true, completedAt: selectedSource.startedAt
        )
        sourceBench.sets.append(sourceBenchSet)
        selectedSource.loggedExercises.append(sourceBench)
        context.insert(selectedSource)
        context.insert(sourceBench)

        let newerSession = WorkoutSession(
            title: "Newer Workout",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank
        )
        let newerBench = LoggedExercise(orderIndex: 0, exercise: exercise)
        newerBench.sets.append(
            LoggedSet(orderIndex: 0, weight: 225, reps: 3, isCompleted: true, completedAt: newerSession.startedAt)
        )
        newerSession.loggedExercises.append(newerBench)
        context.insert(newerSession)
        context.insert(newerBench)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let clonedBench = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: sourceBench.id
        )
        clonedBench.sets.append(LoggedSet(orderIndex: 0, sourceLoggedSetID: sourceBenchSet.id))
        // A second Bench Press card added by hand after cloning carries no source link.
        let addedBench = LoggedExercise(orderIndex: 1, exercise: exercise)
        addedBench.sets.append(LoggedSet(orderIndex: 0))
        active.loggedExercises.append(contentsOf: [clonedBench, addedBench])
        context.insert(active)
        context.insert(clonedBench)
        context.insert(addedBench)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        // The cloned card keeps its linked source values; the added card uses
        // normal history (the newer session) instead of reusing the source clone.
        XCTAssertEqual(lookup[clonedBench.id], [
            PreviousSetPerformance(weight: 185, reps: 5),
        ])
        XCTAssertEqual(lookup[addedBench.id], [
            PreviousSetPerformance(weight: 225, reps: 3),
        ])
    }

    func testPastWorkoutLookupUsesHistoryAfterAllClonedExercisesAreDeletedAndExerciseIsReadded() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let sourceBench = LoggedExercise(orderIndex: 0, exercise: exercise)
        sourceBench.sets.append(
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true, completedAt: selectedSource.startedAt)
        )
        selectedSource.loggedExercises.append(sourceBench)
        context.insert(selectedSource)
        context.insert(sourceBench)

        let newerSession = WorkoutSession(
            title: "Newer Workout",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank
        )
        let newerBench = LoggedExercise(orderIndex: 0, exercise: exercise)
        newerBench.sets.append(
            LoggedSet(orderIndex: 0, weight: 225, reps: 3, isCompleted: true, completedAt: newerSession.startedAt)
        )
        newerSession.loggedExercises.append(newerBench)
        context.insert(newerSession)
        context.insert(newerBench)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let readdedBench = LoggedExercise(orderIndex: 0, exercise: exercise)
        readdedBench.sets.append(LoggedSet(orderIndex: 0))
        active.loggedExercises.append(readdedBench)
        context.insert(active)
        context.insert(readdedBench)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        XCTAssertEqual(lookup[readdedBench.id], [
            PreviousSetPerformance(weight: 225, reps: 3),
        ])
    }

    func testPastWorkoutLookupUsesStableSourceExerciseIDsForAllClonedDuplicates() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let firstSourceBench = LoggedExercise(orderIndex: 0, exercise: exercise)
        let firstSourceSet = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            isCompleted: true,
            completedAt: selectedSource.startedAt
        )
        firstSourceBench.sets.append(firstSourceSet)
        let secondSourceBench = LoggedExercise(orderIndex: 1, exercise: exercise)
        let secondSourceSet = LoggedSet(
            orderIndex: 0,
            weight: 195,
            reps: 3,
            isCompleted: true,
            completedAt: selectedSource.startedAt
        )
        secondSourceBench.sets.append(secondSourceSet)
        selectedSource.loggedExercises.append(contentsOf: [firstSourceBench, secondSourceBench])
        context.insert(selectedSource)
        context.insert(firstSourceBench)
        context.insert(secondSourceBench)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let firstActiveBench = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: firstSourceBench.id
        )
        firstActiveBench.sets.append(LoggedSet(orderIndex: 0, sourceLoggedSetID: firstSourceSet.id))
        let secondActiveBench = LoggedExercise(
            orderIndex: 1,
            exercise: exercise,
            sourceLoggedExerciseID: secondSourceBench.id
        )
        secondActiveBench.sets.append(LoggedSet(orderIndex: 0, sourceLoggedSetID: secondSourceSet.id))
        active.loggedExercises.append(contentsOf: [firstActiveBench, secondActiveBench])
        context.insert(active)
        context.insert(firstActiveBench)
        context.insert(secondActiveBench)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        XCTAssertEqual(lookup[firstActiveBench.id], [
            PreviousSetPerformance(weight: 185, reps: 5),
        ])
        XCTAssertEqual(lookup[secondActiveBench.id], [
            PreviousSetPerformance(weight: 195, reps: 3),
        ])
    }

    func testPastWorkoutLookupUsesStableSourceExerciseAfterReorderAndDelete() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let firstSourceBench = LoggedExercise(orderIndex: 0, exercise: exercise)
        let firstSourceSet = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            isCompleted: true,
            completedAt: selectedSource.startedAt
        )
        firstSourceBench.sets.append(firstSourceSet)
        let secondSourceBench = LoggedExercise(orderIndex: 1, exercise: exercise)
        let secondSourceSet = LoggedSet(
            orderIndex: 0,
            weight: 195,
            reps: 3,
            isCompleted: true,
            completedAt: selectedSource.startedAt
        )
        secondSourceBench.sets.append(secondSourceSet)
        selectedSource.loggedExercises.append(contentsOf: [firstSourceBench, secondSourceBench])
        context.insert(selectedSource)
        context.insert(firstSourceBench)
        context.insert(secondSourceBench)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let deletedFirstActiveBench = LoggedExercise(
            orderIndex: 1,
            exercise: exercise,
            sourceLoggedExerciseID: firstSourceBench.id,
            deletedAt: Date(timeIntervalSince1970: 250)
        )
        deletedFirstActiveBench.sets.append(
            LoggedSet(orderIndex: 0, deletedAt: Date(timeIntervalSince1970: 250), sourceLoggedSetID: firstSourceSet.id)
        )
        let remainingSecondActiveBench = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: secondSourceBench.id
        )
        remainingSecondActiveBench.sets.append(LoggedSet(orderIndex: 0, sourceLoggedSetID: secondSourceSet.id))
        active.loggedExercises.append(contentsOf: [deletedFirstActiveBench, remainingSecondActiveBench])
        context.insert(active)
        context.insert(deletedFirstActiveBench)
        context.insert(remainingSecondActiveBench)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        XCTAssertEqual(lookup[remainingSecondActiveBench.id], [
            PreviousSetPerformance(weight: 195, reps: 3),
        ])
    }

    func testPastWorkoutLookupReturnsEmptyWhenSourceSessionIsMissingOrDeleted() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        context.insert(exercise)

        let deletedSource = WorkoutSession(
            title: "Deleted Source",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            deletedAt: Date(timeIntervalSince1970: 150)
        )
        let deletedSourceLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        deletedSourceLogged.sets.append(
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true, completedAt: deletedSource.startedAt)
        )
        deletedSource.loggedExercises.append(deletedSourceLogged)
        context.insert(deletedSource)
        context.insert(deletedSourceLogged)

        let missingSourceActive = WorkoutSession(
            title: "Missing Source Active",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: UUID()
        )
        let missingSourceLogged = LoggedExercise(orderIndex: 0, exercise: exercise)
        missingSourceActive.loggedExercises.append(missingSourceLogged)
        context.insert(missingSourceActive)
        context.insert(missingSourceLogged)

        let deletedSourceActive = WorkoutSession(
            title: "Deleted Source Active",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: deletedSource.id
        )
        let deletedSourceActiveLogged = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: deletedSourceLogged.id
        )
        deletedSourceActive.loggedExercises.append(deletedSourceActiveLogged)
        context.insert(deletedSourceActive)
        context.insert(deletedSourceActiveLogged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let missingLookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: missingSourceActive.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: missingSourceActive.sourceSessionID
        )
        let deletedLookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: deletedSourceActive.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: deletedSourceActive.sourceSessionID
        )

        XCTAssertEqual(missingLookup[missingSourceLogged.id], [])
        XCTAssertEqual(deletedLookup[deletedSourceActiveLogged.id], [])
    }

    func testPastWorkoutLookupPreservesIncompleteSourceSetPositions() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .quads
        )
        context.insert(exercise)

        let selectedSource = WorkoutSession(
            title: "Selected Past Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let sourceSquat = LoggedExercise(orderIndex: 0, exercise: exercise)
        let incompleteSourceSet = LoggedSet(
            orderIndex: 0,
            isCompleted: false
        )
        let completedSourceSet = LoggedSet(
            orderIndex: 1,
            weight: 225,
            reps: 5,
            isCompleted: true,
            completedAt: selectedSource.startedAt
        )
        sourceSquat.sets.append(contentsOf: [incompleteSourceSet, completedSourceSet])
        selectedSource.loggedExercises.append(sourceSquat)
        context.insert(selectedSource)
        context.insert(sourceSquat)

        let active = WorkoutSession(
            title: "Today",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .active,
            source: .pastWorkout,
            sourceSessionID: selectedSource.id
        )
        let activeSquat = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            sourceLoggedExerciseID: sourceSquat.id
        )
        activeSquat.sets.append(contentsOf: [
            LoggedSet(orderIndex: 0, sourceLoggedSetID: incompleteSourceSet.id),
            LoggedSet(orderIndex: 1, sourceLoggedSetID: completedSourceSet.id),
        ])
        active.loggedExercises.append(activeSquat)
        context.insert(active)
        context.insert(activeSquat)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lookup = PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: active.sortedLoggedExercises,
            in: sessions,
            ownerTokenIdentifier: nil,
            sourceSessionID: active.sourceSessionID
        )

        XCTAssertEqual(lookup[activeSquat.id], [
            PreviousSetPerformance(weight: nil, reps: nil),
            PreviousSetPerformance(weight: 225, reps: 5),
        ])
    }

    func testDisplayTextIncludesRepsWhenWeightIsMissing() {
        let previous = PreviousSetPerformance(weight: nil, reps: 8)

        XCTAssertEqual(previous.displayText(weightUnit: .pounds), "- × 8")
    }

    func testCacheKeyIgnoresValueEditsAndCompletionInActiveSession() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        try insertCompletedSession(startedAt: Date(timeIntervalSince1970: 100), exercise: exercise, sets: [(135, 10)], in: context)

        let active = WorkoutSession(title: "Today", startedAt: Date(timeIntervalSince1970: 200), status: .active, source: .blank)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise)
        let set = LoggedSet(orderIndex: 0)
        logged.sets.append(set)
        active.loggedExercises.append(logged)
        context.insert(active)
        context.insert(logged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let before = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)

        set.weight = 185
        set.reps = 5
        set.isCompleted = true
        set.touch()
        active.title = "Renamed Mid-Workout"

        let after = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertEqual(before, after)
    }

    func testCacheKeyChangesWhenActiveSetStructureChanges() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)

        let active = WorkoutSession(title: "Today", startedAt: Date(timeIntervalSince1970: 200), status: .active, source: .blank)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise)
        let firstSet = LoggedSet(orderIndex: 0)
        let secondSet = LoggedSet(orderIndex: 1)
        logged.sets.append(contentsOf: [firstSet, secondSet])
        active.loggedExercises.append(logged)
        context.insert(active)
        context.insert(logged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let original = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)

        let addedSet = LoggedSet(orderIndex: 2)
        logged.sets.append(addedSet)
        context.insert(addedSet)
        let afterAdd = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertNotEqual(original, afterAdd)

        addedSet.markDeleted()
        let afterRemove = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertEqual(original, afterRemove)

        firstSet.orderIndex = 1
        secondSet.orderIndex = 0
        let afterReorder = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertNotEqual(original, afterReorder)
    }

    func testCacheKeyChangesWhenExerciseListChanges() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        context.insert(bench)
        context.insert(squat)

        let active = WorkoutSession(title: "Today", startedAt: Date(timeIntervalSince1970: 200), status: .active, source: .blank)
        let loggedBench = LoggedExercise(orderIndex: 0, exercise: bench)
        active.loggedExercises.append(loggedBench)
        context.insert(active)
        context.insert(loggedBench)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let original = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)

        let loggedSquat = LoggedExercise(orderIndex: 1, exercise: squat)
        active.loggedExercises.append(loggedSquat)
        context.insert(loggedSquat)
        let afterAdd = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertNotEqual(original, afterAdd)

        loggedSquat.markDeleted()
        let afterRemove = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertEqual(original, afterRemove)
    }

    func testCacheKeyChangesWhenSyncCompletes() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)

        let active = WorkoutSession(title: "Today", startedAt: Date(timeIntervalSince1970: 200), status: .active, source: .blank)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise)
        active.loggedExercises.append(logged)
        context.insert(active)
        context.insert(logged)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let beforeSync = PreviousSetPerformance.CacheKey(
            session: active, sessions: sessions, ownerTokenIdentifier: nil, lastSyncedAt: nil
        )
        // Sync applies remote child-record edits without bumping the parent
        // session's updatedAt, so a completed sync must invalidate on its own.
        let afterSync = PreviousSetPerformance.CacheKey(
            session: active, sessions: sessions, ownerTokenIdentifier: nil, lastSyncedAt: Date(timeIntervalSince1970: 300)
        )
        XCTAssertNotEqual(beforeSync, afterSync)
    }

    func testCacheKeyChangesWhenCompletedHistoryChanges() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        try insertCompletedSession(startedAt: Date(timeIntervalSince1970: 100), exercise: exercise, sets: [(135, 10)], in: context)

        let active = WorkoutSession(title: "Today", startedAt: Date(timeIntervalSince1970: 200), status: .active, source: .blank)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise)
        active.loggedExercises.append(logged)
        context.insert(active)
        context.insert(logged)
        try context.save()

        var sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let original = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)

        try insertCompletedSession(startedAt: Date(timeIntervalSince1970: 150), exercise: exercise, sets: [(155, 8)], in: context)
        sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let afterNewSession = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertNotEqual(original, afterNewSession)

        let editBaseline = afterNewSession
        let completed = sessions.first { $0.status == .completed }
        // Real edits touch with .now, which always advances past creation times.
        completed?.touch(now: Date(timeIntervalSinceNow: 60))
        let afterHistoryEdit = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertNotEqual(editBaseline, afterHistoryEdit)
    }

    func testCacheKeyChangesWhenCompletedHistorySetIsEditedThroughSaveService() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        try insertCompletedSession(startedAt: Date(timeIntervalSince1970: 100), exercise: exercise, sets: [(135, 10)], in: context)

        let active = WorkoutSession(title: "Today", startedAt: Date(timeIntervalSince1970: 200), status: .active, source: .blank)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise)
        active.loggedExercises.append(logged)
        context.insert(active)
        context.insert(logged)
        try context.save()

        var sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let original = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        let completed = try XCTUnwrap(sessions.first { $0.status == .completed })
        var draft = CompletedWorkoutEditDraft(session: completed)
        draft.exercises[0].sets[0].weight = 145

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: completed,
            context: context,
            now: Date(timeIntervalSince1970: 300)
        )

        sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let afterHistorySetEdit = PreviousSetPerformance.CacheKey(session: active, sessions: sessions, ownerTokenIdentifier: nil)
        XCTAssertNotEqual(original, afterHistorySetEdit)
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
