import SwiftData
import XCTest
@testable import Baros

@MainActor
final class HistoryPersistenceTests: XCTestCase {
    func testFinishedWorkoutAppearsInCompletedHistoryFetch() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)

        try engine.finishWorkout(session, context: context)

        XCTAssertEqual(try completedSessions(in: context).map(\.id), [session.id])
    }

    func testTombstonedCompletedWorkoutNoLongerAppears() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        try engine.finishWorkout(session, context: context)

        session.markDeletedCascade(now: Date(timeIntervalSince1970: 200))
        try context.save()

        XCTAssertTrue(try completedSessions(in: context).isEmpty)
    }

    func testVisibleCompletedSessionsExcludeTombstonedSessions() {
        let activeSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            title: "Active",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .active,
            source: .blank
        )
        let deletedCompletedSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            title: "Deleted",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank
        )
        deletedCompletedSession.markDeletedCascade(now: Date(timeIntervalSince1970: 300))
        let visibleCompletedSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
            title: "Visible",
            startedAt: Date(timeIntervalSince1970: 400),
            status: .completed,
            source: .blank
        )

        let sessions = WorkoutSession.visibleCompletedSessions(from: [
            activeSession,
            deletedCompletedSession,
            visibleCompletedSession
        ])

        XCTAssertEqual(sessions.map(\.id), [visibleCompletedSession.id])
    }

    func testVisibleCompletedSessionsAreScopedToOwnerAndSignedOutShowsOnlyLocalHistory() {
        let ownerASession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000304")!,
            title: "Owner A",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )
        let ownerBSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000305")!,
            title: "Owner B",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "issuer|owner_b"
        )
        let signedOutSession = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000306")!,
            title: "Signed Out",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .completed,
            source: .blank
        )

        let sessions = [ownerASession, ownerBSession, signedOutSession]

        XCTAssertEqual(
            WorkoutSession.visibleCompletedSessions(from: sessions, ownerTokenIdentifier: "issuer|owner_b").map(\.id),
            [ownerBSession.id, signedOutSession.id]
        )
        XCTAssertEqual(
            WorkoutSession.visibleCompletedSessions(from: sessions, ownerTokenIdentifier: nil).map(\.id),
            [signedOutSession.id]
        )
    }

    func testCompletedWorkoutHistoryMutationsRequireMatchingOwnerWhenWorkoutIsOwned() {
        let ownerlessSession = WorkoutSession(title: "Local", startedAt: .now, status: .completed, source: .blank)
        let ownedSession = WorkoutSession(
            title: "Owned",
            startedAt: .now,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )

        XCTAssertTrue(ownerlessSession.allowsHistoryMutation(ownerTokenIdentifier: nil))
        XCTAssertTrue(ownerlessSession.allowsHistoryMutation(ownerTokenIdentifier: "issuer|owner_a"))
        XCTAssertTrue(ownedSession.allowsHistoryMutation(ownerTokenIdentifier: "issuer|owner_a"))
        XCTAssertFalse(ownedSession.allowsHistoryMutation(ownerTokenIdentifier: nil))
        XCTAssertFalse(ownedSession.allowsHistoryMutation(ownerTokenIdentifier: "issuer|owner_b"))
    }

    func testWorkoutHistoryRowExerciseCountIgnoresTombstonedLoggedExercises() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let visibleExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press")
        let deletedExercise = LoggedExercise(orderIndex: 1, exerciseSnapshotName: "Back Squat")
        let session = WorkoutSession(
            title: "Push",
            startedAt: .now,
            status: .completed,
            source: .blank,
            loggedExercises: [visibleExercise, deletedExercise]
        )
        context.insert(session)
        try context.save()
        let relationshipDeletedExercise = try XCTUnwrap(session.loggedExercises.first { $0.exerciseSnapshotName == "Back Squat" })
        relationshipDeletedExercise.markDeleted(now: Date(timeIntervalSince1970: 700))
        try context.save()

        XCTAssertTrue(relationshipDeletedExercise.isDeleted)
        XCTAssertEqual(session.visibleExerciseCount, 1)
    }

    func testDeletingCompletedWorkoutTombstonesSessionLoggedExercisesAndSets() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let session = WorkoutSession(title: "Push", startedAt: .now, status: .completed, source: .blank)
        let firstLoggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        firstLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true),
            LoggedSet(orderIndex: 1, weight: 195, reps: 3, rpe: 9, isCompleted: true)
        ]
        let secondLoggedExercise = LoggedExercise(orderIndex: 1, exercise: exercise, exerciseSnapshotName: exercise.name)
        secondLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 205, reps: 2, rpe: 9, isCompleted: true)
        ]
        session.loggedExercises = [firstLoggedExercise, secondLoggedExercise]
        context.insert(exercise)
        context.insert(session)
        try context.save()
        let deletedAt = Date(timeIntervalSince1970: 300)

        session.markDeletedCascade(now: deletedAt)
        try context.save()

        let persistedSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let persistedLoggedExercises = try context.fetch(FetchDescriptor<LoggedExercise>())
        let persistedSets = try context.fetch(FetchDescriptor<LoggedSet>())
        XCTAssertEqual(persistedSessions.map(\.id), [session.id])
        XCTAssertEqual(persistedLoggedExercises.count, 2)
        XCTAssertEqual(persistedSets.count, 3)
        XCTAssertEqual(session.deletedAt, deletedAt)
        XCTAssertEqual(session.updatedAt, deletedAt)
        XCTAssertTrue(session.loggedExercises.allSatisfy { $0.deletedAt == deletedAt })
        XCTAssertTrue(session.loggedExercises.allSatisfy { $0.updatedAt == deletedAt })
        XCTAssertTrue(session.loggedExercises.flatMap(\.sets).allSatisfy { $0.deletedAt == deletedAt })
        XCTAssertTrue(session.loggedExercises.flatMap(\.sets).allSatisfy { $0.updatedAt == deletedAt })
    }

    func testExerciseHistoryCountsCompletedSetsOnly() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let session = WorkoutSession(title: "Push", startedAt: .now, status: .completed, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        loggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true),
            LoggedSet(orderIndex: 1, weight: 185, reps: 5, rpe: 8, isCompleted: false)
        ]
        session.loggedExercises = [loggedExercise]
        context.insert(exercise)
        context.insert(session)
        try context.save()

        let summaries = ExerciseHistorySummary.makeSummaries(from: [session])

        XCTAssertEqual(summaries.first?.completedSetCount, 1)
    }

    func testExerciseHistorySummaryIgnoresTombstonedWorkoutGraphRecords() throws {
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let visibleSession = WorkoutSession(title: "Visible Push", startedAt: Date(timeIntervalSince1970: 100), status: .completed, source: .blank)
        let visibleLoggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        visibleLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true),
            LoggedSet(orderIndex: 1, weight: 195, reps: 3, rpe: 9, isCompleted: true)
        ]
        visibleLoggedExercise.sets[1].markDeleted(now: Date(timeIntervalSince1970: 200))
        let deletedLoggedExercise = LoggedExercise(orderIndex: 1, exercise: exercise, exerciseSnapshotName: exercise.name)
        deletedLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 205, reps: 2, rpe: 9, isCompleted: true)
        ]
        deletedLoggedExercise.markDeleted(now: Date(timeIntervalSince1970: 200))
        visibleSession.loggedExercises = [visibleLoggedExercise, deletedLoggedExercise]
        let deletedSession = WorkoutSession(title: "Deleted Push", startedAt: Date(timeIntervalSince1970: 300), status: .completed, source: .blank)
        let deletedSessionExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        deletedSessionExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 225, reps: 1, rpe: 10, isCompleted: true)
        ]
        deletedSession.loggedExercises = [deletedSessionExercise]
        deletedSession.markDeletedCascade(now: Date(timeIntervalSince1970: 400))

        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [visibleSession, deletedSession]).first)

        XCTAssertEqual(summary.name, "Bench Press")
        XCTAssertEqual(summary.lastPerformedAt, visibleSession.startedAt)
        XCTAssertEqual(summary.completedSetCount, 1)
    }

    func testExerciseHistorySummaryUsesSnapshotNameAfterExerciseRename() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Barbell Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let session = WorkoutSession(title: "Push", startedAt: .now, status: .completed, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: "Bench Press")
        loggedExercise.sets = [LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true)]
        session.loggedExercises = [loggedExercise]
        context.insert(exercise)
        context.insert(session)
        try context.save()

        let summaries = ExerciseHistorySummary.makeSummaries(from: [session])

        XCTAssertEqual(summaries.first?.name, "Bench Press")
    }

    func testStartingFromPastWorkoutDoesNotMutateOriginalPastWorkout() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads)
        let past = WorkoutSession(title: "Leg Day", startedAt: .now, status: .completed, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        loggedExercise.sets = [LoggedSet(orderIndex: 0, weight: 315, reps: 5, rpe: 8, isCompleted: true)]
        past.loggedExercises = [loggedExercise]
        context.insert(exercise)
        context.insert(past)
        try context.save()

        _ = try ActiveWorkoutEngine().startWorkout(fromPast: past, context: context)

        XCTAssertEqual(past.status, .completed)
        XCTAssertEqual(past.loggedExercises.first?.sets.first?.isCompleted, true)
        XCTAssertEqual(past.loggedExercises.first?.sets.first?.weight, 315)
    }

    func testExerciseHistoryGroupsCompletedSetsByWorkoutSession() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let newerSession = WorkoutSession(
            title: "Push B",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank
        )
        let olderSession = WorkoutSession(
            title: "Push A",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        let newerLoggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        newerLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true),
            LoggedSet(orderIndex: 1, weight: 195, reps: 3, rpe: 9, isCompleted: true)
        ]
        let olderLoggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        olderLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 175, reps: 6, rpe: 7, isCompleted: true),
            LoggedSet(orderIndex: 1, weight: 175, reps: 6, rpe: 7, isCompleted: false)
        ]
        newerSession.loggedExercises = [newerLoggedExercise]
        olderSession.loggedExercises = [olderLoggedExercise]
        context.insert(exercise)
        context.insert(newerSession)
        context.insert(olderSession)
        try context.save()

        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [olderSession, newerSession]).first)
        let groups = ExerciseHistorySessionGroup.makeGroups(from: [olderSession, newerSession], matching: summary)

        XCTAssertEqual(groups.map(\.title), ["Push B", "Push A"])
        XCTAssertEqual(groups.map(\.completedSetCount), [2, 1])
        XCTAssertEqual(groups.first?.setEntries.map { $0.displaySetNumber }, [1, 2])
        XCTAssertEqual(groups.last?.setEntries.map { $0.displaySetNumber }, [1])
    }

    func testExerciseHistoryGroupingMatchesSnapshotNameWhenExerciseIDIsMissing() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            title: "Snapshot Session",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: nil, exerciseSnapshotName: "Incline DB Press")
        loggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 70, reps: 8, rpe: 8, isCompleted: true)
        ]
        session.loggedExercises = [loggedExercise]
        context.insert(session)
        try context.save()

        let summary = ExerciseHistorySummary(
            id: "snapshot-incline db press",
            exerciseID: nil,
            name: "incline db press",
            equipmentRaw: ExerciseEquipment.other.rawValue,
            primaryMuscleGroupRaw: ExerciseMuscleGroup.other.rawValue,
            lastPerformedAt: session.startedAt,
            completedSetCount: 1
        )
        let groups = ExerciseHistorySessionGroup.makeGroups(from: [session], matching: summary)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.title, "Snapshot Session")
        XCTAssertEqual(groups.first?.setEntries.first?.set.weight, 70)
    }

    func testExerciseHistorySuppressesUnknownSnapshotMetadata() throws {
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: nil,
            exerciseSnapshotName: "Legacy Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.other.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.other.rawValue,
            sets: [LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true)]
        )
        loggedExercise.hasSnapshotMetadata = false
        let session = WorkoutSession(
            title: "Legacy Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            loggedExercises: [loggedExercise]
        )

        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [session]).first)
        let route = ExerciseHistoryRoute(loggedExercise: loggedExercise)

        XCTAssertEqual(summary.name, "Legacy Bench Press")
        XCTAssertNil(summary.equipmentRaw)
        XCTAssertNil(summary.primaryMuscleGroupRaw)
        XCTAssertNil(summary.metadataDisplayText)
        XCTAssertEqual(summary.id, "snapshot-legacy bench press-unknown")
        XCTAssertEqual(route.id, "snapshot-legacy bench press-unknown")
        XCTAssertEqual(ExerciseHistorySummary.find(in: [summary], matching: route)?.id, summary.id)
    }

    func testExerciseHistorySeparatesSameNameDifferentEquipmentBySnapshotFallback() throws {
        let barbell = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
            sets: [LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true)]
        )
        let dumbbell = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.dumbbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
            sets: [LoggedSet(orderIndex: 0, weight: 70, reps: 8, isCompleted: true)]
        )
        let barbellSession = WorkoutSession(
            title: "Barbell Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            loggedExercises: [barbell]
        )
        let dumbbellSession = WorkoutSession(
            title: "Dumbbell Push",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            loggedExercises: [dumbbell]
        )

        let summaries = ExerciseHistorySummary.makeSummaries(from: [barbellSession, dumbbellSession])

        XCTAssertEqual(summaries.count, 2)
        XCTAssertTrue(summaries.contains { $0.name == "Bench Press" && $0.equipmentRaw == "barbell" })
        XCTAssertTrue(summaries.contains { $0.name == "Bench Press" && $0.equipmentRaw == "dumbbell" })
    }

    func testExerciseHistoryGroupsFallbackByNameAndEquipment() throws {
        let summary = ExerciseHistorySummary(
            id: "snapshot-bench press-barbell",
            exerciseID: nil,
            name: "Bench Press",
            equipmentRaw: ExerciseEquipment.barbell.rawValue,
            primaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
            lastPerformedAt: .now,
            completedSetCount: 1
        )
        let matchingLoggedExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue
        )
        matchingLoggedExercise.sets = [LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true)]
        let nonMatchingLoggedExercise = LoggedExercise(
            orderIndex: 1,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.dumbbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue
        )
        nonMatchingLoggedExercise.sets = [LoggedSet(orderIndex: 0, weight: 70, reps: 8, isCompleted: true)]
        let session = WorkoutSession(
            title: "Mixed Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            loggedExercises: [matchingLoggedExercise, nonMatchingLoggedExercise]
        )

        let groups = ExerciseHistorySessionGroup.makeGroups(from: [session], matching: summary)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.loggedExerciseEntries.count, 1)
        XCTAssertEqual(groups.first?.loggedExerciseEntries.first?.loggedExercise.exerciseSnapshotEquipmentRaw, "barbell")
    }

    func testExerciseHistoryGroupsSortTitleAscendingWhenStartedAtMatches() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Deadlift", category: .strength, equipment: .barbell, primaryMuscleGroup: .upperBack)
        let startedAt = Date(timeIntervalSince1970: 400)
        let bSession = WorkoutSession(title: "B Session", startedAt: startedAt, status: .completed, source: .blank)
        let aSession = WorkoutSession(title: "A Session", startedAt: startedAt, status: .completed, source: .blank)
        let bLoggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        bLoggedExercise.sets = [LoggedSet(orderIndex: 0, weight: 225, reps: 5, rpe: 7, isCompleted: true)]
        let aLoggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        aLoggedExercise.sets = [LoggedSet(orderIndex: 0, weight: 225, reps: 5, rpe: 7, isCompleted: true)]
        bSession.loggedExercises = [bLoggedExercise]
        aSession.loggedExercises = [aLoggedExercise]
        context.insert(exercise)
        context.insert(bSession)
        context.insert(aSession)
        try context.save()

        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [bSession, aSession]).first)
        let groups = ExerciseHistorySessionGroup.makeGroups(from: [bSession, aSession], matching: summary)

        XCTAssertEqual(groups.map(\.title), ["A Session", "B Session"])
    }

    func testExerciseHistoryGroupCarriesExerciseNotes() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let session = WorkoutSession(
            title: "Push Notes",
            startedAt: Date(timeIntervalSince1970: 500),
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            notes: "Elbow felt better with a closer grip."
        )
        loggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true)
        ]
        session.loggedExercises = [loggedExercise]
        context.insert(exercise)
        context.insert(session)
        try context.save()

        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [session]).first)
        let groups = ExerciseHistorySessionGroup.makeGroups(from: [session], matching: summary)

        XCTAssertEqual(groups.first?.exerciseNotes, "Elbow felt better with a closer grip.")
    }

    func testExerciseHistoryGroupPreservesNotesForDuplicateLoggedExercises() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let session = WorkoutSession(
            title: "Duplicate Bench",
            startedAt: Date(timeIntervalSince1970: 600),
            status: .completed,
            source: .blank
        )
        let firstLoggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            notes: ""
        )
        firstLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true)
        ]
        let secondLoggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            orderIndex: 1,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            notes: "Second bench note"
        )
        secondLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 195, reps: 3, rpe: 9, isCompleted: true)
        ]
        session.loggedExercises = [firstLoggedExercise, secondLoggedExercise]
        context.insert(exercise)
        context.insert(session)
        try context.save()

        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [session]).first)
        let group = try XCTUnwrap(ExerciseHistorySessionGroup.makeGroups(from: [session], matching: summary).first)

        XCTAssertEqual(group.loggedExerciseEntries.count, 2)
        XCTAssertEqual(group.loggedExerciseEntries.map { $0.loggedExercise.notes }, ["", "Second bench note"])
        XCTAssertEqual(group.loggedExerciseEntries.map(\.loggedExercise.id), [firstLoggedExercise.id, secondLoggedExercise.id])
        XCTAssertEqual(group.setEntries.map { $0.loggedExercise.id }, [firstLoggedExercise.id, secondLoggedExercise.id])
        XCTAssertEqual(group.loggedExerciseEntries.flatMap { entry in
            entry.setEntries.map { $0.loggedExercise.id }
        }, [firstLoggedExercise.id, secondLoggedExercise.id])
    }

    func testExerciseHistoryNoteBlockTreatsWhitespaceOnlyNotesAsAbsent() {
        XCTAssertNil(ExerciseHistoryNoteBlock.displayNote(from: " \n\t "))
    }

    func testExerciseHistoryNoteBlockPreservesMultilineDisplayText() {
        let note = "Line one\nLine two\n\nLine four"

        XCTAssertEqual(ExerciseHistoryNoteBlock.displayNote(from: note), note)
    }

    func testExerciseHistoryRoutePrefersExerciseID() throws {
        let exerciseID = UUID()
        let exercise = Exercise(id: exerciseID, name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: "Bench Snapshot")

        let route = ExerciseHistoryRoute(loggedExercise: loggedExercise)

        XCTAssertEqual(route.exerciseID, exerciseID)
        XCTAssertEqual(route.name, "Bench Snapshot")
    }

    func testExerciseHistoryRouteFallsBackToSnapshotName() throws {
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: nil, exerciseSnapshotName: "Incline DB Press")

        let route = ExerciseHistoryRoute(loggedExercise: loggedExercise)

        XCTAssertNil(route.exerciseID)
        XCTAssertEqual(route.name, "Incline DB Press")
        XCTAssertEqual(route.id, "snapshot-incline db press-other")
    }

    func testExerciseHistorySummaryCanBeFoundFromRoute() throws {
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let session = WorkoutSession(title: "Push", startedAt: .now, status: .completed, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: "Bench Press")
        loggedExercise.sets = [LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true)]
        session.loggedExercises = [loggedExercise]

        let route = ExerciseHistoryRoute(loggedExercise: loggedExercise)
        let summaries = ExerciseHistorySummary.makeSummaries(from: [session])

        XCTAssertEqual(ExerciseHistorySummary.find(in: summaries, matching: route)?.name, "Bench Press")
    }

    func testRecentExerciseHistoryGroupsCapToThreeNewestSessions() throws {
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let sessions = (1...4).map { index in
            let session = WorkoutSession(
                title: "Push \(index)",
                startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                status: .completed,
                source: .blank
            )
            let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
            loggedExercise.sets = [LoggedSet(orderIndex: 0, weight: Double(100 + index), reps: 5, rpe: 8, isCompleted: true)]
            session.loggedExercises = [loggedExercise]
            return session
        }
        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: sessions).first)

        let groups = ExerciseHistorySessionGroup.recentGroups(from: sessions, matching: summary, limit: 3)

        XCTAssertEqual(groups.map(\.title), ["Push 4", "Push 3", "Push 2"])
    }

    func testExerciseHistoryGroupExposesTrimmedExerciseNotes() throws {
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let session = WorkoutSession(title: "Push", startedAt: .now, status: .completed, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name, notes: "  Felt strong  ")
        loggedExercise.sets = [LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true)]
        session.loggedExercises = [loggedExercise]
        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [session]).first)

        let group = try XCTUnwrap(ExerciseHistorySessionGroup.makeGroups(from: [session], matching: summary).first)

        XCTAssertEqual(group.exerciseNotes, "Felt strong")
    }

    private func completedSessions(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.status == .completed && !$0.isDeleted }
    }
}
