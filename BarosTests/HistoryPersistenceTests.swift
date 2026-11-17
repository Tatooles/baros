import SwiftData
import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class HistoryPersistenceTests: XCTestCase {
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

    func testSavedWorkoutSummaryCountsEveryRowWhileVolumeAndRecordsUseCompletedSets() throws {
        let scenarios: [(completed: [Bool], totalLabel: String, completedVolume: Double)] = [
            ([true, false, false], "3 sets", 500),
            ([true, true, true], "3 sets", 1_500),
            ([true], "1 set", 500),
        ]
        for scenario in scenarios {
            let container = try SwiftDataTestSupport.makeInMemoryContainer()
            let context = container.mainContext
            let session = WorkoutSession(title: "Push", startedAt: .now, status: .completed, source: .blank)
            let loggedExercise = LoggedExercise(
                orderIndex: 0,
                exerciseSnapshotName: "Bench Press",
                exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue
            )
            loggedExercise.sets = scenario.completed.enumerated().map { index, isCompleted in
                // Unfinished rows are heavier so any leak into volume or records is visible.
                LoggedSet(orderIndex: index, weight: isCompleted ? 100 : 400, reps: 5, isCompleted: isCompleted)
            }
            session.loggedExercises = [loggedExercise]
            context.insert(session)
            try context.save()

            let metrics = WorkoutMetrics(session: session)
            XCTAssertEqual(WorkoutFormatters.setCount(metrics.totalSetCount), scenario.totalLabel)
            XCTAssertEqual(
                WorkoutFormatters.setCount(session.sortedLoggedExercises[0].sortedSets.count),
                scenario.totalLabel
            )
            XCTAssertEqual(metrics.completedSetCount, scenario.completed.filter { $0 }.count)
            XCTAssertEqual(metrics.completedVolume, scenario.completedVolume)

            let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [session]).first)
            XCTAssertEqual(summary.completedSetCount, scenario.completed.filter { $0 }.count)
            let groups = ExerciseHistorySessionGroup.makeGroups(from: [session], matching: summary)
            let records = try XCTUnwrap(ExerciseHistoryRecords.make(from: groups, equipmentRaw: summary.equipmentRaw))
            XCTAssertEqual(records.heaviestRep?.value, 100)
        }
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

    func testExerciseHistoryNoteBlockTreatsWhitespaceOnlyNotesAsAbsent() {
        XCTAssertNil(ExerciseHistoryNoteBlock.displayNote(from: " \n\t "))
    }

    func testExerciseHistoryNoteBlockPreservesMultilineDisplayText() {
        let note = "Line one\nLine two\n\nLine four"

        XCTAssertEqual(ExerciseHistoryNoteBlock.displayNote(from: note), note)
    }

    func testExerciseHistoryViewSnapshotResolvesHistoryOnceForAllConsumers() throws {
        // The one deliberately large history: 100 workouts and 3,000 completed sets.
        let fixture = try makeHistoryViewPerformanceFixture(
            sessionCount: 100,
            exerciseCount: 20,
            loggedExercisesPerSession: 10,
            setsPerLoggedExercise: 3
        )
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
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
            ).resolvedHistory.summaries.count,
            fixture.exercises.count
        )

        activeSession.title = "Renamed Active"
        activeSession.touch(now: Date(timeIntervalSince1970: 600))
        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
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
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
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
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory

        loggedExercise.sets.append(
            LoggedSet(orderIndex: 1, weight: 195, reps: 5, isCompleted: true)
        )
        activeSession.loggedExercises.removeAll()
        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
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
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        )
        let initialCompletedSetCount = firstSnapshot.resolvedHistory.summaries
            .reduce(0) { $0 + $1.completedSetCount }
        let set = try XCTUnwrap(fixture.sessions.first?.sortedLoggedExercises.first?.sortedSets.first)

        set.isCompleted = false
        set.touch(now: Date(timeIntervalSince1970: 800))
        let updatedCompletedSetCount = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
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
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory

        session.title = "Irrelevant completed title edit"
        set.weight = (set.weight ?? 0) + 5
        set.reps = (set.reps ?? 0) + 1
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 1)

        session.startedAt = session.startedAt.addingTimeInterval(60)
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 2)

        session.markDeleted(now: Date(timeIntervalSince1970: 1_200))
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 3)

        session.restoreFromDeletion(now: Date(timeIntervalSince1970: 1_300))
        session.status = .active
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
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
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
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
        let context = fixture.container.mainContext
        try context.save()
        let saves = HistorySaveNotificationCapture(context: context)
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)

        let firstName = try XCTUnwrap(
            state.snapshot(
                sessions: [session],
                exercises: [exercise],
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
            ).resolvedHistory.summary(for: exercise)
        ).name

        // A synced reorder updates the logged exercises without touching the session.
        first.orderIndex = 1
        second.orderIndex = 0
        try context.save()
        XCTAssertEqual(saves.deliver(to: state, in: context), 1)
        let secondName = try XCTUnwrap(
            state.snapshot(
                sessions: [session],
                exercises: [exercise],
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
            ).resolvedHistory.summary(for: exercise)
        ).name

        XCTAssertEqual(firstName, "First Snapshot")
        XCTAssertEqual(secondName, "Second Snapshot")
        XCTAssertEqual(resolutionCounter.count, 2)
    }

    func testExerciseHistoryViewStateRebuildsWhenAnOldWorkoutSetIsUncheckedInHistory() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let context = fixture.container.mainContext
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        let oldestSession = try XCTUnwrap(fixture.sessions.min { $0.startedAt < $1.startedAt })
        let initialCompletedSetCount = completedSetCount(
            in: state.snapshot(
                sessions: fixture.sessions,
                exercises: fixture.exercises,
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
            )
        )

        var draft = CompletedWorkoutEditDraft(session: oldestSession)
        draft.exercises[0].sets[0].isCompleted = false
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: oldestSession,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier,
            context: context,
            now: Date(timeIntervalSince1970: 5_000)
        )

        // No save is routed here: a History edit reaches the key through its session.
        let updatedCompletedSetCount = completedSetCount(
            in: state.snapshot(
                sessions: fixture.sessions,
                exercises: fixture.exercises,
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
            )
        )
        XCTAssertEqual(updatedCompletedSetCount, initialCompletedSetCount - 1)
        XCTAssertEqual(resolutionCounter.count, 2)
    }

    func testExerciseHistoryViewStateRebuildsWhenSyncUnchecksAnOldWorkoutSet() async throws {
        let fixture = try makeSyncedHistoryFixture()
        let saves = HistorySaveNotificationCapture(context: fixture.context)
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        XCTAssertEqual(completedSetCount(in: try fixture.snapshot(from: state)), 1)

        try await fixture.pull(loggedSet: fixture.set.id, isCompleted: false)

        XCTAssertFalse(fixture.set.isCompleted)
        XCTAssertEqual(fixture.session.updatedAt, fixture.savedAt, "Sync applies the set without touching its session")
        XCTAssertGreaterThan(saves.deliver(to: state, in: fixture.context), 0)
        XCTAssertEqual(completedSetCount(in: try fixture.snapshot(from: state)), 0)
        XCTAssertEqual(resolutionCounter.count, 2)
    }

    func testExerciseHistoryViewStateRebuildsWhenSyncAddsASetToAnOldWorkout() async throws {
        let fixture = try makeSyncedHistoryFixture()
        let saves = HistorySaveNotificationCapture(context: fixture.context)
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        XCTAssertEqual(completedSetCount(in: try fixture.snapshot(from: state)), 1)

        try await fixture.pull(loggedSet: UUID(), isCompleted: true)

        XCTAssertEqual(fixture.loggedExercise.sortedSets.count, 2)
        XCTAssertEqual(fixture.session.updatedAt, fixture.savedAt, "Sync inserts the set without touching its session")
        XCTAssertGreaterThan(saves.deliver(to: state, in: fixture.context), 0)
        XCTAssertEqual(completedSetCount(in: try fixture.snapshot(from: state)), 2)
        XCTAssertEqual(resolutionCounter.count, 2)
    }

    func testWorkoutSearchIndexSurvivesUnrelatedUpdatesAndRefreshesAfterSavedHistoryChanges() throws {
        let fixture = try makeSyncedHistoryFixture()
        let state = makeExerciseHistoryViewState(resolutionCounter: ExerciseHistoryResolutionCounter())
        _ = try fixture.snapshot(from: state)
        let originalIndex = state.workoutSearchIndex
        originalIndex.prepare()
        let originalName = fixture.loggedExercise.exerciseSnapshotName
        XCTAssertEqual(originalIndex.sessions(from: [fixture.session], matching: originalName).map(\.id), [fixture.session.id])

        _ = try fixture.snapshot(from: state)
        XCTAssertTrue(state.workoutSearchIndex === originalIndex, "Unrelated updates keep the prepared index")

        let saves = HistorySaveNotificationCapture(context: fixture.context)
        fixture.loggedExercise.exerciseSnapshotName = "Renamed Synced Exercise"
        try fixture.context.save()
        XCTAssertEqual(saves.deliver(to: state, in: fixture.context), 1)
        _ = try fixture.snapshot(from: state)
        XCTAssertFalse(state.workoutSearchIndex === originalIndex)
        XCTAssertEqual(
            state.workoutSearchIndex.sessions(from: [fixture.session], matching: "Renamed Synced").map(\.id),
            [fixture.session.id]
        )
        XCTAssertTrue(state.workoutSearchIndex.sessions(from: [fixture.session], matching: originalName).isEmpty)

        _ = state.snapshot(sessions: [fixture.session], exercises: [], ownerTokenIdentifier: "issuer|another_owner")
        XCTAssertTrue(state.workoutSearchIndex.sessions(from: [fixture.session], matching: "Renamed Synced").isEmpty)
    }

    func testExerciseHistoryViewStateRebuildsForChildInsertsAndDeletesSavedToDisk() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarosHistorySaveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let fixture = try makeSyncedHistoryFixture(storeURL: storeDirectory.appendingPathComponent("Baros.store"))
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        let forwarder = ImmediateHistorySaveForwarder(state: state, context: fixture.context)
        XCTAssertEqual(completedSetCount(in: try fixture.snapshot(from: state)), 1)

        let insertedSetID = UUID()
        try await fixture.pull(loggedSet: insertedSetID, isCompleted: true)
        XCTAssertEqual(fixture.session.updatedAt, fixture.savedAt, "Sync inserts the set without touching its session")
        XCTAssertEqual(completedSetCount(in: try fixture.snapshot(from: state)), 2, "Set inserted by sync")
        XCTAssertEqual(resolutionCounter.count, 2)

        try await fixture.pull(loggedSet: fixture.set.id, isCompleted: true, deletedAt: 30)
        XCTAssertEqual(fixture.session.updatedAt, fixture.savedAt, "Sync deletes the set without touching its session")
        XCTAssertEqual(completedSetCount(in: try fixture.snapshot(from: state)), 1, "Set deleted by sync")
        XCTAssertEqual(resolutionCounter.count, 3)

        let insertedSet = try XCTUnwrap(fixture.loggedExercise.sets.first { $0.id == insertedSetID })
        fixture.context.delete(insertedSet)
        try fixture.context.save()
        XCTAssertEqual(completedSetCount(in: try fixture.snapshot(from: state)), 0, "Set removed from the store")
        XCTAssertEqual(resolutionCounter.count, 4)
        XCTAssertGreaterThan(forwarder.deliveredCount, 0)
    }

    func testExerciseHistoryViewStateIgnoresSavesConfinedToAnActiveWorkout() throws {
        let fixture = try makeHistoryViewPerformanceFixture()
        let context = fixture.container.mainContext
        let saves = HistorySaveNotificationCapture(context: context)
        let resolutionCounter = ExerciseHistoryResolutionCounter()
        let state = makeExerciseHistoryViewState(resolutionCounter: resolutionCounter)
        let activeSession = WorkoutSession(
            title: "Active",
            startedAt: Date(timeIntervalSince1970: 500),
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: fixture.ownerTokenIdentifier
        )
        let sessions = fixture.sessions + [activeSession]
        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory

        context.insert(activeSession)
        try context.save()
        let set = LoggedSet(orderIndex: 0)
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: try XCTUnwrap(fixture.exercises.first),
            sets: [set]
        )
        loggedExercise.session = activeSession
        activeSession.loggedExercises.append(loggedExercise)
        activeSession.touch()
        try context.save()
        set.weight = 225
        set.reps = 5
        set.isCompleted = true
        set.touchActiveDraft()
        try context.save()
        _ = try SyncCursorState.state(for: fixture.ownerTokenIdentifier, context: context)
        try context.save()

        XCTAssertEqual(saves.deliver(to: state, in: context), 4)
        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 1)

        try ActiveWorkoutEngine().discardWorkout(activeSession, context: context)
        XCTAssertEqual(saves.deliver(to: state, in: context), 1)
        _ = state.snapshot(
            sessions: sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory
        XCTAssertEqual(resolutionCounter.count, 1, "Discarding an active workout does not change completed history")
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
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
            ).resolvedHistory.summary(for: exercise)
        ).name
        let secondName = try XCTUnwrap(
            state.snapshot(
                sessions: [secondSession, firstSession],
                exercises: [exercise],
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
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
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory

        let exercise = try XCTUnwrap(fixture.exercises.first)
        exercise.name = "Renamed Performance Exercise"
        exercise.touch(now: Date(timeIntervalSince1970: 900))
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: fixture.ownerTokenIdentifier
        ).resolvedHistory
        _ = state.snapshot(
            sessions: fixture.sessions,
            exercises: fixture.exercises,
            ownerTokenIdentifier: nil
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
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
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
                ownerTokenIdentifier: fixture.ownerTokenIdentifier
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

    private func completedSetCount(in snapshot: ExerciseHistoryViewSnapshot) -> Int {
        snapshot.resolvedHistory.summaries.reduce(0) { $0 + $1.completedSetCount }
    }

    /// One completed, owned workout with a single completed set, saved before sync runs.
    @MainActor
    private struct SyncedHistoryFixture {
        let container: ModelContainer
        let context: ModelContext
        let owner: String
        let savedAt: Date
        let session: WorkoutSession
        let loggedExercise: LoggedExercise
        let set: LoggedSet

        func snapshot(from state: ExerciseHistoryViewState) throws -> ExerciseHistoryViewSnapshot {
            state.snapshot(
                sessions: try context.fetch(FetchDescriptor<WorkoutSession>()),
                exercises: [],
                ownerTokenIdentifier: owner
            )
        }

        /// Pulls one remote set record for the fixture's logged exercise.
        func pull(loggedSet id: UUID, isCompleted: Bool, deletedAt: Double? = nil) async throws {
            let client = FakeSyncClient()
            client.fetchResponses = [
                SyncFetchChangesResponse(
                    userSettings: [],
                    exercises: [],
                    workoutSessions: [],
                    loggedExercises: [],
                    loggedSets: [
                        LoggedSetSyncRecord(
                            clientId: id.uuidString.lowercased(),
                            createdAt: 10,
                            updatedAt: 20,
                            deletedAt: deletedAt,
                            serverUpdatedAt: 50,
                            loggedExerciseClientId: loggedExercise.id.uuidString.lowercased(),
                            orderIndex: id == set.id ? 0 : 1,
                            weight: 185,
                            reps: 5,
                            rpe: nil,
                            kindRaw: "working",
                            isCompleted: isCompleted,
                            completedAt: nil,
                            notes: "",
                            healthLinkID: nil,
                            sourceLoggedSetID: nil
                        )
                    ],
                    cursors: SyncChangeCursors(userSettings: 0, exercises: 0, loggedSets: 50),
                    hasMore: SyncHasMore(userSettings: false, exercises: false)
                )
            ]
            try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)
        }
    }

    /// With a store URL, the fixture is saved to disk and reopened in a fresh
    /// container, so History starts from faults as it does after a cold launch.
    private func makeSyncedHistoryFixture(storeURL: URL? = nil) throws -> SyncedHistoryFixture {
        let container = try storeURL.map(SwiftDataTestSupport.makeDiskBackedContainer(storeURL:))
            ?? SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let owner = "issuer|history_sync_owner"
        let savedAt = Date(timeIntervalSince1970: 10)
        let set = LoggedSet(
            orderIndex: 0,
            weight: 185,
            reps: 5,
            isCompleted: true,
            createdAt: savedAt,
            updatedAt: savedAt
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press",
            createdAt: savedAt,
            updatedAt: savedAt,
            sets: [set]
        )
        let session = WorkoutSession(
            title: "Push",
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            source: .blank,
            createdAt: savedAt,
            updatedAt: savedAt,
            syncOwnerTokenIdentifier: owner,
            loggedExercises: [loggedExercise]
        )
        context.insert(session)
        try context.save()
        guard let storeURL else {
            return SyncedHistoryFixture(
                container: container,
                context: context,
                owner: owner,
                savedAt: savedAt,
                session: session,
                loggedExercise: loggedExercise,
                set: set
            )
        }

        let sessionID = session.id
        let reopenedContainer = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: storeURL)
        let reopenedContext = reopenedContainer.mainContext
        let reopenedSession = try XCTUnwrap(
            reopenedContext.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first
        )
        let reopenedLoggedExercise = try XCTUnwrap(reopenedSession.loggedExercises.first)
        return SyncedHistoryFixture(
            container: reopenedContainer,
            context: reopenedContext,
            owner: owner,
            savedAt: savedAt,
            session: reopenedSession,
            loggedExercise: reopenedLoggedExercise,
            set: try XCTUnwrap(reopenedLoggedExercise.sets.first)
        )
    }

    /// Routes each save to the state while it is being posted, as `HistoryView`'s
    /// `onReceive` does, instead of replaying saves after sync returns.
    @MainActor
    private final class ImmediateHistorySaveForwarder {
        private(set) var deliveredCount = 0
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        init(state: ExerciseHistoryViewState, context: ModelContext) {
            nonisolated(unsafe) let context = context
            observer = NotificationCenter.default.addObserver(
                forName: ModelContext.didSave,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                // Production saves post on the main thread, so this runs synchronously.
                nonisolated(unsafe) let notification = notification
                MainActor.assumeIsolated {
                    state.recordSave(notification, in: context)
                    self?.deliveredCount += 1
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    /// Collects a context's saves so a test can route them to the state, as
    /// `HistoryView` does.
    private final class HistorySaveNotificationCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var notifications: [Notification] = []
        private var observer: NSObjectProtocol?

        init(context: ModelContext) {
            observer = NotificationCenter.default.addObserver(
                forName: ModelContext.didSave,
                object: context,
                queue: nil
            ) { [weak self] notification in
                guard let self else { return }
                lock.withLock { notifications.append(notification) }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        /// Returns how many saves were delivered.
        @MainActor
        func deliver(to state: ExerciseHistoryViewState, in context: ModelContext) -> Int {
            let pending = lock.withLock {
                defer { notifications.removeAll() }
                return notifications
            }
            for notification in pending {
                state.recordSave(notification, in: context)
            }
            return pending.count
        }
    }

    /// Completed, owned history in which every exercise has the same number of
    /// performances, provided `sessionCount` is a multiple of `exerciseCount`.
    /// The defaults are the smallest history the cache tests need; only a test
    /// about scale should ask for more.
    private func makeHistoryViewPerformanceFixture(
        sessionCount: Int = 4,
        exerciseCount: Int = 4,
        loggedExercisesPerSession: Int = 2,
        setsPerLoggedExercise: Int = 2
    ) throws -> (
        container: ModelContainer,
        sessions: [WorkoutSession],
        exercises: [Exercise],
        ownerTokenIdentifier: String,
        completedSetCount: Int
    ) {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let ownerTokenIdentifier = "issuer|history_performance_owner"
        let exercises = (0..<exerciseCount).map { index in
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

        let sessions = (0..<sessionCount).map { sessionIndex in
            let loggedExercises = (0..<loggedExercisesPerSession).map { exerciseOffset in
                let exercise = exercises[(sessionIndex + exerciseOffset) % exercises.count]
                return LoggedExercise(
                    orderIndex: exerciseOffset,
                    exercise: exercise,
                    exerciseSnapshotName: exercise.name,
                    sets: (0..<setsPerLoggedExercise).map { setIndex in
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
            sessionCount * loggedExercisesPerSession * setsPerLoggedExercise
        )
    }
}
