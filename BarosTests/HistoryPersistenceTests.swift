import SwiftData
import XCTest
@testable import Baros

@MainActor
final class HistoryPersistenceTests: XCTestCase {
    func testCompletedWorkoutEditDraftKeepsExerciseNotesIndependentFromSavedWorkout() throws {
        let firstOccurrence = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            notes: "Pause on the chest"
        )
        let secondOccurrence = LoggedExercise(
            orderIndex: 1,
            exerciseSnapshotName: "Bench Press",
            notes: "Close-grip finisher"
        )
        let session = WorkoutSession(
            title: "Push",
            startedAt: .now,
            status: .completed,
            source: .blank
        )
        session.loggedExercises = [firstOccurrence, secondOccurrence]

        var draft = CompletedWorkoutEditDraft(session: session)

        XCTAssertEqual(draft.exercises.map(\.notes), ["Pause on the chest", "Close-grip finisher"])

        draft.exercises[0].notes = "Edited in the draft"

        XCTAssertEqual(firstOccurrence.notes, "Pause on the chest")
        XCTAssertEqual(secondOccurrence.notes, "Close-grip finisher")
    }

    func testCompletedWorkoutExerciseNoteSurvivesDiskBackedReopen() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarosExerciseNoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appendingPathComponent("Baros.store")
        let sessionID: UUID

        do {
            var container: ModelContainer? = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: storeURL)
            let context = try XCTUnwrap(container?.mainContext)
            let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true)
            let exercise = LoggedExercise(
                orderIndex: 0,
                exerciseSnapshotName: "Bench Press",
                notes: "Original note",
                sets: [set]
            )
            let noteOnlyExercise = LoggedExercise(
                orderIndex: 1,
                exerciseSnapshotName: "Bench Press",
                notes: "Original no-set note"
            )
            let session = WorkoutSession(
                title: "Push",
                startedAt: Date(timeIntervalSince1970: 1_000),
                status: .completed,
                source: .blank,
                loggedExercises: [exercise, noteOnlyExercise]
            )
            sessionID = session.id
            context.insert(session)
            try context.save()

            var draft = CompletedWorkoutEditDraft(session: session)
            draft.exercises[0].notes = "Persisted correction"
            draft.exercises[1].notes = "Persisted no-set correction"
            try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
                draft,
                for: session,
                context: context,
                now: Date(timeIntervalSince1970: 2_000)
            )
            container = nil
        }

        do {
            var container: ModelContainer? = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: storeURL)
            let context = try XCTUnwrap(container?.mainContext)
            let targetSessionID = sessionID
            let descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.id == targetSessionID }
            )
            let reopenedSession = try XCTUnwrap(context.fetch(descriptor).first)
            let reopenedExercises = reopenedSession.sortedLoggedExercises
            let reopenedExercise = try XCTUnwrap(reopenedExercises.first)

            XCTAssertEqual(reopenedExercise.notes, "Persisted correction")
            XCTAssertEqual(reopenedExercises.map(\.notes), ["Persisted correction", "Persisted no-set correction"])

            let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [reopenedSession]).first)
            let group = try XCTUnwrap(
                ExerciseHistorySessionGroup.makeGroups(from: [reopenedSession], matching: summary).first
            )
            XCTAssertEqual(group.loggedExerciseEntries.first?.exerciseNotes, "Persisted correction")
            XCTAssertEqual(group.loggedExerciseEntries.map(\.loggedExercise.id), [reopenedExercise.id])
            container = nil
        }
    }

    func testCompletedWorkoutEditDraftRecoversOutOfPolicyNumericValues() throws {
        let set = LoggedSet(orderIndex: 0, weight: 10_001, reps: 1_001, rpe: 10.1, isCompleted: true)
        let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press", sets: [set])
        let session = WorkoutSession(
            title: "Push",
            startedAt: .now,
            status: .completed,
            source: .blank,
            loggedExercises: [exercise]
        )

        let draftSet = try XCTUnwrap(CompletedWorkoutEditDraft(session: session).exercises.first?.sets.first)

        XCTAssertNil(draftSet.weight)
        XCTAssertNil(draftSet.reps)
        XCTAssertNil(draftSet.rpe)
    }

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
        XCTAssertTrue(summaries.first?.historyDetailSummaryLabel.hasSuffix("· 1 workout · 1 set") == true)
    }

    func testExerciseHistoryCountsOnePerformancePerCompletedWorkoutWithDuplicateExerciseRows() throws {
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let firstLoggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name
        )
        firstLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true)
        ]
        let secondLoggedExercise = LoggedExercise(
            orderIndex: 1,
            exercise: exercise,
            exerciseSnapshotName: exercise.name
        )
        secondLoggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 195, reps: 3, isCompleted: true)
        ]
        let session = WorkoutSession(
            title: "Duplicate Bench",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank
        )
        session.loggedExercises = [firstLoggedExercise, secondLoggedExercise]

        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [session]).first)

        XCTAssertEqual(summary.performanceCount, 1)
        XCTAssertEqual(summary.completedSetCount, 2)
        XCTAssertTrue(summary.historyDetailSummaryLabel.hasSuffix("· 1 workout · 2 sets"))
    }

    func testExerciseHistoryReconcilesLinkedAndSnapshotPerformancesIntoOneSummary() throws {
        let fixture = try makeReconciledHistoryFixture()

        let summaries = ExerciseHistorySummary.makeSummaries(
            from: [fixture.linkedSession, fixture.snapshotSession]
        )

        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summary.exerciseID, fixture.exercise.id)
        XCTAssertEqual(summary.performanceCount, 2)
        XCTAssertEqual(summary.completedSetCount, 2)
        XCTAssertTrue(summary.historyDetailSummaryLabel.hasSuffix("· 2 workouts · 2 sets"))
        XCTAssertEqual(summary.lastPerformedAt, fixture.snapshotSession.startedAt)
        XCTAssertEqual(
            ExerciseHistorySummary.find(
                in: summaries,
                matching: ExerciseHistoryRoute(loggedExercise: fixture.snapshotExercise)
            )?.id,
            summary.id
        )
    }

    func testAmbiguousSnapshotHistoryRemainsSeparateFromLinkedExerciseDetails() throws {
        let firstExercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let secondExercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let firstSession = WorkoutSession(
            title: "First Linked Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            loggedExercises: [
                LoggedExercise(
                    orderIndex: 0,
                    exercise: firstExercise,
                    exerciseSnapshotName: "Bench Press",
                    sets: [LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true)]
                ),
            ]
        )
        let secondSession = WorkoutSession(
            title: "Second Linked Push",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            loggedExercises: [
                LoggedExercise(
                    orderIndex: 0,
                    exercise: secondExercise,
                    exerciseSnapshotName: "Bench Press",
                    sets: [LoggedSet(orderIndex: 0, weight: 195, reps: 5, isCompleted: true)]
                ),
            ]
        )
        let snapshotExercise = LoggedExercise(
            orderIndex: 0,
            exercise: nil,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
            sets: [LoggedSet(orderIndex: 0, weight: 205, reps: 3, isCompleted: true)]
        )
        let snapshotSession = WorkoutSession(
            title: "Ambiguous Snapshot Push",
            startedAt: Date(timeIntervalSince1970: 300),
            status: .completed,
            source: .blank,
            loggedExercises: [snapshotExercise]
        )
        let sessions = [firstSession, secondSession, snapshotSession]

        let summaries = ExerciseHistorySummary.makeSummaries(from: sessions)

        let firstSummary = try XCTUnwrap(summaries.first { $0.exerciseID == firstExercise.id })
        let secondSummary = try XCTUnwrap(summaries.first { $0.exerciseID == secondExercise.id })
        let snapshotSummary = try XCTUnwrap(summaries.first { $0.exerciseID == nil })
        XCTAssertEqual(summaries.count, 3)
        XCTAssertEqual(firstSummary.performanceCount, 1)
        XCTAssertEqual(secondSummary.performanceCount, 1)
        XCTAssertEqual(snapshotSummary.performanceCount, 1)
        XCTAssertEqual(
            ExerciseHistorySessionGroup.makeGroups(
                from: sessions,
                matching: firstSummary
            ).map(\.title),
            ["First Linked Push"]
        )
        XCTAssertEqual(
            ExerciseHistorySessionGroup.makeGroups(
                from: sessions,
                matching: secondSummary
            ).map(\.title),
            ["Second Linked Push"]
        )
        XCTAssertEqual(
            ExerciseHistorySessionGroup.makeGroups(
                from: sessions,
                matching: snapshotSummary
            ).map(\.title),
            ["Ambiguous Snapshot Push"]
        )
        XCTAssertEqual(
            ExerciseHistorySummary.find(
                in: summaries,
                matching: ExerciseHistoryRoute(loggedExercise: snapshotExercise)
            )?.id,
            snapshotSummary.id
        )
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
        XCTAssertEqual(summary.performanceCount, 1)
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

    func testReconciledExerciseHistoryGroupsIncludeLinkedAndSnapshotSessions() throws {
        let fixture = try makeReconciledHistoryFixture()
        let summary = try XCTUnwrap(
            ExerciseHistorySummary.makeSummaries(
                from: [fixture.linkedSession, fixture.snapshotSession]
            ).first
        )

        let groups = ExerciseHistorySessionGroup.makeGroups(
            from: [fixture.linkedSession, fixture.snapshotSession],
            matching: summary
        )

        XCTAssertEqual(groups.map(\.title), ["Snapshot Push", "Linked Push"])
        XCTAssertEqual(groups.map(\.completedSetCount), [1, 1])
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
            completedSetCount: 1,
            performanceSessionIDs: [session.id],
            snapshotFallbackIdentities: [
                ExerciseHistorySnapshotIdentity(
                    name: "incline db press",
                    equipmentRaw: ExerciseEquipment.other.rawValue
                ),
            ]
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
        let summary = ExerciseHistorySummary(
            id: "snapshot-bench press-barbell",
            exerciseID: nil,
            name: "Bench Press",
            equipmentRaw: ExerciseEquipment.barbell.rawValue,
            primaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
            lastPerformedAt: session.startedAt,
            completedSetCount: 1,
            performanceSessionIDs: [session.id],
            snapshotFallbackIdentities: [
                ExerciseHistorySnapshotIdentity(
                    name: "Bench Press",
                    equipmentRaw: ExerciseEquipment.barbell.rawValue
                ),
            ]
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

    func testExerciseHistoryEntryOnlyShowsIdentityForDifferingHistoricalSnapshot() {
        let headingIdentity = ExerciseHistoryDisplayIdentity(
            name: "Competition Bench Press",
            metadataDisplayText: "Barbell • Chest"
        )
        let matchingExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Competition Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue
        )
        let renamedExercise = LoggedExercise(
            orderIndex: 1,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue
        )
        let changedEquipmentExercise = LoggedExercise(
            orderIndex: 2,
            exerciseSnapshotName: "Competition Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.dumbbell.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue
        )

        XCTAssertFalse(
            ExerciseHistoryLoggedExerciseEntry(
                loggedExercise: matchingExercise,
                setEntries: []
            ).showsIdentity(comparedTo: headingIdentity)
        )
        XCTAssertTrue(
            ExerciseHistoryLoggedExerciseEntry(
                loggedExercise: renamedExercise,
                setEntries: []
            ).showsIdentity(comparedTo: headingIdentity)
        )
        XCTAssertTrue(
            ExerciseHistoryLoggedExerciseEntry(
                loggedExercise: changedEquipmentExercise,
                setEntries: []
            ).showsIdentity(comparedTo: headingIdentity)
        )
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

        let visibility = ExerciseHistoryVisibilityScope(
            exercises: [exercise],
            ownerTokenIdentifier: nil
        )
        let snapshotRoute = ExerciseHistoryRoute(
            exerciseID: nil,
            name: loggedExercise.exerciseSnapshotName,
            equipmentRaw: loggedExercise.resolvedSnapshotEquipmentRaw
        )
        XCTAssertEqual(
            ExerciseHistorySummary.makeIndex(from: [session])
                .resolved(for: visibility)
                .summary(for: snapshotRoute)?
                .exerciseID,
            exercise.id
        )
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

    func testExerciseHistoryViewSnapshotResolvesHistoryOnceForAllConsumers() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        var resolutionCount = 0
        var resolutionTime = TimeInterval.zero
        let snapshot = ExerciseHistoryViewSnapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ) { sessions, exercises, ownerTokenIdentifier in
            resolutionCount += 1
            let startedAt = ProcessInfo.processInfo.systemUptime
            defer {
                resolutionTime += ProcessInfo.processInfo.systemUptime - startedAt
            }
            return ExerciseHistorySummary.makeResolvedHistory(
                from: sessions,
                exercises: exercises,
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        }

        XCTAssertFalse(snapshot.resolvedHistory.summaries.isEmpty)
        let summaries = snapshot.resolvedHistory.summaries
        XCTAssertEqual(summaries.count, fixture.exercises.count)
        for index in summaries.indices {
            XCTAssertEqual(
                index < snapshot.resolvedHistory.summaries.count - 1,
                index < summaries.count - 1
            )
        }
        let firstSummary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(
            snapshot.resolvedHistory.summary(
                for: ExerciseHistoryRoute(summary: firstSummary)
            )?.id,
            firstSummary.id
        )

        print(
            "HISTORY_VIEW_UPDATE_METRICS "
                + "sessions=\(fixture.sessions.count) "
                + "exercises=\(fixture.exercises.count) "
                + "completedSets=\(fixture.completedSetCount) "
                + "resolutions=\(resolutionCount) "
                + "resolutionTimeMilliseconds=\(resolutionTime * 1_000)"
        )
        XCTAssertEqual(resolutionCount, 1)
    }

    func testExerciseHistoryViewStateIgnoresActiveWorkoutAndNoOpSyncChanges() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let activeSession = WorkoutSession(
            title: "Active",
            startedAt: Date(timeIntervalSince1970: 500),
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: fixture.ownerTokenIdentifier
        )
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        let sessions = fixture.sessions + [activeSession]

        XCTAssertEqual(
            state.snapshot(
                sessions: sessions,
                exercises: fixture.exercises,
                ownerTokenIdentifier: fixture.ownerTokenIdentifier,
                syncCompletion: nil
            ).resolvedHistory.summaries.count,
            fixture.exercises.count
        )

        activeSession.title = "Renamed Active"
        activeSession.touch(now: Date(timeIntervalSince1970: 600))
        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: Date(timeIntervalSince1970: 700)
        ).resolvedHistory

        XCTAssertEqual(resolutionCounter.count, 1)
    }

    func testExerciseHistoryViewStateIgnoresActiveSetAndExerciseChanges() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let activeSession = WorkoutSession(
            title: "Active",
            startedAt: Date(timeIntervalSince1970: 500),
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: fixture.ownerTokenIdentifier
        )
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        let sessions = fixture.sessions + [activeSession]

        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory

        let exercise = try XCTUnwrap(fixture.exercises.first)
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            sets: [LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: false)]
        )
        loggedExercise.session = activeSession
        activeSession.loggedExercises.append(loggedExercise)
        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory

        loggedExercise.sets.append(
            LoggedSet(orderIndex: 1, weight: 195, reps: 5, isCompleted: true)
        )
        activeSession.loggedExercises.removeAll()
        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory

        XCTAssertEqual(resolutionCounter.count, 1)
    }

    func testExerciseHistoryViewStateRebuildsWhenCompletedContributionChanges() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        let firstSnapshot = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        )
        let initialCompletedSetCount = firstSnapshot.resolvedHistory.summaries
            .reduce(0) { $0 + $1.completedSetCount }
        let set = try XCTUnwrap(fixture.sessions.first?.sortedLoggedExercises.first?.sortedSets.first)

        set.isCompleted = false
        set.touch(now: Date(timeIntervalSince1970: 800))
        let updatedCompletedSetCount = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory.summaries.reduce(0) { $0 + $1.completedSetCount }

        XCTAssertEqual(updatedCompletedSetCount, initialCompletedSetCount - 1)
        XCTAssertEqual(resolutionCounter.count, 2)
    }

    func testExerciseHistoryViewStateRebuildsExactlyForCompletedWorkoutContributionChanges() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        let session = try XCTUnwrap(fixture.sessions.first)
        let set = try XCTUnwrap(session.sortedLoggedExercises.first?.sortedSets.first)

        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory

        session.title = "Irrelevant completed title edit"
        set.weight = (set.weight ?? 0) + 5
        set.reps = (set.reps ?? 0) + 1
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 1)

        session.startedAt = session.startedAt.addingTimeInterval(60)
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 2)

        session.markDeleted(now: Date(timeIntervalSince1970: 1_200))
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 3)

        session.restoreFromDeletion(now: Date(timeIntervalSince1970: 1_300))
        session.status = .active
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory
        XCTAssertEqual(
            resolutionCounter.count,
            3,
            "Restoring a workout as active does not restore a completed-history contribution"
        )

        session.status = .completed
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 4)
    }

    func testExerciseHistoryViewStateRebuildsWhenLoggedExerciseOrderChangesResolvedMetadata() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let session = try XCTUnwrap(fixture.sessions.first)
        let exercise = try XCTUnwrap(fixture.exercises.first)
        let first = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: "First Snapshot",
            sets: [LoggedSet(orderIndex: 0, isCompleted: true)]
        )
        let second = LoggedExercise(
            orderIndex: 1,
            exercise: exercise,
            exerciseSnapshotName: "Second Snapshot",
            sets: [LoggedSet(orderIndex: 0, isCompleted: true)]
        )
        first.session = session
        second.session = session
        session.loggedExercises = [first, second]
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)

        let firstName = try XCTUnwrap(
            state.snapshot(
                sessions: [session],
                exercises: [exercise],
                ownerTokenIdentifier: fixture.ownerTokenIdentifier,
                syncCompletion: nil
            ).resolvedHistory.summary(for: exercise)
        ).name

        first.orderIndex = 1
        second.orderIndex = 0
        let secondName = try XCTUnwrap(
            state.snapshot(
                sessions: [session],
                exercises: [exercise],
                ownerTokenIdentifier: fixture.ownerTokenIdentifier,
                syncCompletion: nil
            ).resolvedHistory.summary(for: exercise)
        ).name

        XCTAssertEqual(firstName, "First Snapshot")
        XCTAssertEqual(secondName, "Second Snapshot")
        XCTAssertEqual(resolutionCounter.count, 2)
    }

    func testExerciseHistoryViewStateRebuildsWhenTiedSessionOrderChangesResolvedMetadata() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let exercise = try XCTUnwrap(fixture.exercises.first)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        func makeSession(id: UUID, snapshotName: String) -> WorkoutSession {
            WorkoutSession(
                id: id,
                title: snapshotName,
                startedAt: startedAt,
                status: .completed,
                source: .blank,
                syncOwnerTokenIdentifier: fixture.ownerTokenIdentifier,
                loggedExercises: [
                    LoggedExercise(
                        orderIndex: 0,
                        exercise: exercise,
                        exerciseSnapshotName: snapshotName,
                        sets: [LoggedSet(orderIndex: 0, isCompleted: true)]
                    )
                ]
            )
        }

        let firstSession = makeSession(
            id: UUID(),
            snapshotName: "First Session Snapshot"
        )
        let secondSession = makeSession(
            id: UUID(),
            snapshotName: "Second Session Snapshot"
        )
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)

        let firstName = try XCTUnwrap(
            state.snapshot(
                sessions: [firstSession, secondSession],
                exercises: [exercise],
                ownerTokenIdentifier: fixture.ownerTokenIdentifier,
                syncCompletion: nil
            ).resolvedHistory.summary(for: exercise)
        ).name
        let secondName = try XCTUnwrap(
            state.snapshot(
                sessions: [secondSession, firstSession],
                exercises: [exercise],
                ownerTokenIdentifier: fixture.ownerTokenIdentifier,
                syncCompletion: nil
            ).resolvedHistory.summary(for: exercise)
        ).name

        XCTAssertEqual(firstName, "First Session Snapshot")
        XCTAssertEqual(secondName, "Second Session Snapshot")
        XCTAssertEqual(resolutionCounter.count, 2)
    }

    func testExerciseHistoryViewStateRebuildsForExerciseDefinitionAndCurrentOwnerChanges() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)

        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory

        let exercise = try XCTUnwrap(fixture.exercises.first)
        exercise.name = "Renamed Performance Exercise"
        exercise.touch(now: Date(timeIntervalSince1970: 900))
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            syncCompletion: nil
        ).resolvedHistory
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: nil,
            syncCompletion: nil
        ).resolvedHistory

        XCTAssertEqual(resolutionCounter.count, 3)
    }

    func testExerciseHistoryViewStateRebuildsAfterSynchronizedCompletedWorkoutArrives() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let context = fixture.container.mainContext
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        let initialPerformanceCount = try XCTUnwrap(
            state.snapshot(
                sessions: fixture.sessions,
                exercises: fixture.exercises,
                ownerTokenIdentifier: fixture.ownerTokenIdentifier,
                syncCompletion: nil
            ).resolvedHistory.summaries.first
        ).performanceCount
        let exercise = try XCTUnwrap(fixture.exercises.first)
        let synchronizedSession = WorkoutSession(
            title: "Synchronized Workout",
            startedAt: Date(timeIntervalSince1970: 1_000),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: fixture.ownerTokenIdentifier,
            loggedExercises: [
                LoggedExercise(
                    orderIndex: 0,
                    exercise: exercise,
                    exerciseSnapshotName: exercise.name,
                    sets: [LoggedSet(orderIndex: 0, weight: 225, reps: 5, isCompleted: true)]
                )
            ]
        )
        context.insert(synchronizedSession)
        try context.save()
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        let updatedSummary = try XCTUnwrap(
            state.snapshot(
                sessions: sessions,
                exercises: fixture.exercises,
                ownerTokenIdentifier: fixture.ownerTokenIdentifier,
                syncCompletion: Date(timeIntervalSince1970: 1_100)
            ).resolvedHistory.summary(for: exercise)
        )

        XCTAssertEqual(updatedSummary.performanceCount, initialPerformanceCount + 1)
        XCTAssertEqual(resolutionCounter.count, 2)
    }

    private func makeReconciledHistoryFixture() throws -> (
        container: ModelContainer,
        exercise: Exercise,
        snapshotExercise: LoggedExercise,
        linkedSession: WorkoutSession,
        snapshotSession: WorkoutSession
    ) {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let linkedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            sets: [LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true)]
        )
        let linkedSession = WorkoutSession(
            title: "Linked Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            loggedExercises: [linkedExercise]
        )
        let snapshotExercise = LoggedExercise(
            orderIndex: 0,
            exercise: nil,
            exerciseSnapshotName: exercise.name,
            exerciseSnapshotEquipmentRaw: exercise.equipmentRaw,
            exerciseSnapshotPrimaryMuscleGroupRaw: exercise.primaryMuscleGroupRaw,
            sets: [LoggedSet(orderIndex: 0, weight: 195, reps: 3, isCompleted: true)]
        )
        let snapshotSession = WorkoutSession(
            title: "Snapshot Push",
            startedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank,
            loggedExercises: [snapshotExercise]
        )
        context.insert(exercise)
        context.insert(linkedSession)
        context.insert(snapshotSession)
        try context.save()

        return (
            container,
            exercise,
            snapshotExercise,
            linkedSession,
            snapshotSession
        )
    }

    private func makeExerciseHistoryViewState(
        resolutionCounter: ExerciseHistoryResolutionCounter
    ) -> ExerciseHistoryViewState {
        ExerciseHistoryViewState { sessions, exercises, ownerTokenIdentifier in
            resolutionCounter.count += 1
            return ExerciseHistorySummary.makeResolvedHistory(
                from: sessions,
                exercises: exercises,
                ownerTokenIdentifier: ownerTokenIdentifier
            )
        }
    }

    private final class ExerciseHistoryResolutionCounter {
        var count = 0
    }

    private func makeHistoryViewPerformanceFixture() throws -> (
        container: ModelContainer,
        sessions: [WorkoutSession],
        exercises: [Exercise],
        ownerTokenIdentifier: String,
        completedSetCount: Int
    ) {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|history_performance_owner"
        let exercises = (0..<20).map { index in
            Exercise(
                name: "Performance Exercise \(index)",
                category: .strength,
                equipment: index.isMultiple(of: 2) ? .barbell : .dumbbell,
                primaryMuscleGroup: index.isMultiple(of: 2) ? .chest : .upperBack,
                syncOwnerTokenIdentifier: ownerTokenIdentifier
            )
        }
        for exercise in exercises {
            context.insert(exercise)
        }

        let sessions = (0..<100).map { sessionIndex in
            let loggedExercises = (0..<10).map { exerciseOffset in
                let exercise = exercises[(sessionIndex + exerciseOffset) % exercises.count]
                return LoggedExercise(
                    orderIndex: exerciseOffset,
                    exercise: exercise,
                    exerciseSnapshotName: exercise.name,
                    sets: (0..<3).map { setIndex in
                        LoggedSet(
                            orderIndex: setIndex,
                            weight: Double(100 + sessionIndex + setIndex),
                            reps: 5 + setIndex,
                            rpe: 8,
                            isCompleted: true
                        )
                    }
                )
            }
            return WorkoutSession(
                title: "Performance Workout \(sessionIndex)",
                startedAt: Date(timeIntervalSince1970: TimeInterval(sessionIndex)),
                status: .completed,
                source: .blank,
                syncOwnerTokenIdentifier: ownerTokenIdentifier,
                loggedExercises: loggedExercises
            )
        }
        for session in sessions {
            context.insert(session)
        }
        try context.save()

        return (
            container,
            try context.fetch(FetchDescriptor<WorkoutSession>()),
            try context.fetch(FetchDescriptor<Exercise>()),
            ownerTokenIdentifier,
            100 * 10 * 3
        )
    }

    private func completedSessions(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.status == .completed && !$0.isDeleted }
    }
}
