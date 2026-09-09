import SwiftData
import XCTest
@testable import Baros

@MainActor
final class CompletedWorkoutDateEditTests: XCTestCase {
    func testDateOnlyCorrectionPreservesDurationAndSetsAndQueuesOnlyWorkout() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let originalStart = date("2026-09-06T21:30:17Z")
        let savedAt = date("2026-09-06T23:00:00Z")
        let set = LoggedSet(orderIndex: 0, reps: 5, isCompleted: true, completedAt: originalStart)
        let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Squat", sets: [set])
        let session = WorkoutSession(
            title: "Evening", startedAt: originalStart,
            endedAt: date("2026-09-06T22:24:24Z"), durationSeconds: 3_247,
            status: .completed, source: .blank, syncOwnerTokenIdentifier: "owner",
            loggedExercises: [exercise]
        )
        context.insert(session)
        try context.save()
        let originalCreatedAt = session.createdAt
        let exercisePayload = SyncPayloadMapper.loggedExercisePayload(from: exercise)
        let setPayload = SyncPayloadMapper.loggedSetPayload(from: set)

        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-05T00:00:00Z")
        XCTAssertEqual(session.startedAt, originalStart, "Selecting a date only changes the draft.")
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft, for: session, ownerTokenIdentifier: "owner", context: context, now: savedAt
        )

        XCTAssertEqual(session.startedAt, date("2026-09-05T21:30:17Z"))
        XCTAssertEqual(session.endedAt, date("2026-09-05T22:24:24Z"))
        XCTAssertEqual(session.durationSeconds, 3_247)
        XCTAssertEqual(session.createdAt, originalCreatedAt)
        XCTAssertEqual(session.updatedAt, savedAt)
        XCTAssertEqual(SyncPayloadMapper.loggedExercisePayload(from: exercise), exercisePayload)
        XCTAssertEqual(SyncPayloadMapper.loggedSetPayload(from: set), setPayload)
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.entityID, session.id)
        XCTAssertEqual(entries.first?.entityKind, .workoutSession)
    }

    func testCombinedDateAndDurationCorrectionUsesCorrectedStart() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let originalStart = date("2026-09-06T21:30:17Z")
        let session = WorkoutSession(
            title: "Evening",
            startedAt: originalStart,
            endedAt: date("2026-09-06T22:24:24Z"),
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner"
        )
        context.insert(session)
        try context.save()

        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-05T00:00:00Z")
        draft.durationSeconds = 5_400

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "owner",
            context: context,
            now: date("2026-09-06T23:00:00Z")
        )

        XCTAssertEqual(session.startedAt, date("2026-09-05T21:30:17Z"))
        XCTAssertEqual(session.durationSeconds, 5_400)
        XCTAssertEqual(session.endedAt, date("2026-09-05T23:00:17Z"))
    }

    func testReturningToOriginalDayPreservesOriginalRepeatedTimeAndFractionExactly() throws {
        let calendar = chicagoCalendar
        let original = try XCTUnwrap(calendar.date(
            bySettingHour: 1,
            minute: 30,
            second: 17,
            of: calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!,
            matchingPolicy: .strict,
            repeatedTimePolicy: .last,
            direction: .forward
        )?.addingTimeInterval(0.25))
        let session = WorkoutSession(title: "Fall back", startedAt: original, status: .completed, source: .blank)
        var draft = CompletedWorkoutEditDraft(session: session, calendar: calendar)
        draft.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        draft.date = calendar.startOfDay(for: original)

        XCTAssertEqual(try draft.resolvedStartedAt(now: date("2026-12-01T00:00:00Z")), original)
    }

    func testDateCorrectionAdvancesMissingSpringTimeAndChoosesFirstRepeatedTime() throws {
        let calendar = chicagoCalendar
        let springOriginal = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 2, minute: 30, second: 17))!
        let springSession = WorkoutSession(title: "Spring", startedAt: springOriginal, status: .completed, source: .blank)
        var springDraft = CompletedWorkoutEditDraft(session: springSession, calendar: calendar)
        springDraft.date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!

        let springResolved = try springDraft.resolvedStartedAt(now: date("2026-03-09T00:00:00Z"))
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour, .minute, .second], from: springResolved), DateComponents(month: 3, day: 8, hour: 3, minute: 30, second: 17))

        let fallOriginal = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 1, minute: 30, second: 17))!
        let fallSession = WorkoutSession(title: "Fall", startedAt: fallOriginal, status: .completed, source: .blank)
        var fallDraft = CompletedWorkoutEditDraft(session: fallSession, calendar: calendar)
        let fallDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        fallDraft.date = fallDay

        let firstOccurrence = try XCTUnwrap(calendar.date(
            bySettingHour: 1,
            minute: 30,
            second: 17,
            of: fallDay,
            matchingPolicy: .strict,
            repeatedTimePolicy: .first,
            direction: .forward
        ))
        XCTAssertEqual(try fallDraft.resolvedStartedAt(now: date("2026-11-02T00:00:00Z")), firstOccurrence)
    }

    func testDateCorrectionAdvancesAThirtyMinuteDSTGapPreservingMinutes() throws {
        let calendar = lordHoweCalendar
        let original = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 2, minute: 15, second: 17))!
        let session = WorkoutSession(title: "Thirty minute gap", startedAt: original, status: .completed, source: .blank)
        var draft = CompletedWorkoutEditDraft(session: session, calendar: calendar)
        draft.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4))!

        let resolved = try draft.resolvedStartedAt(now: date("2026-10-05T00:00:00Z"))
        XCTAssertEqual(
            calendar.dateComponents([.month, .day, .hour, .minute, .second], from: resolved),
            DateComponents(month: 10, day: 4, hour: 2, minute: 45, second: 17)
        )
    }

    func testFutureDateIsRejectedWithoutChangingPersistedWorkout() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let originalStart = date("2026-09-06T21:30:17Z")
        let session = WorkoutSession(
            title: "Evening",
            startedAt: originalStart,
            endedAt: date("2026-09-06T22:24:24Z"),
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner"
        )
        context.insert(session)
        try context.save()
        let originalUpdatedAt = session.updatedAt

        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.title = "Should not save"
        draft.date = date("2026-09-07T00:00:00Z")

        XCTAssertThrowsError(try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "owner",
            context: context,
            now: date("2026-09-06T23:00:00Z")
        )) { error in
            XCTAssertEqual(error as? WorkoutHistoryMutationError, .invalidWorkoutDate)
        }
        XCTAssertEqual(session.title, "Evening")
        XCTAssertEqual(session.startedAt, originalStart)
        XCTAssertEqual(session.updatedAt, originalUpdatedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testTodayIsAllowedWhenPreservedTimeAndEndAreLaterThanNow() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            title: "Night workout",
            startedAt: date("2026-09-05T23:30:00Z"),
            endedAt: date("2026-09-06T01:30:00Z"),
            durationSeconds: 7_200,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner"
        )
        context.insert(session)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-06T00:00:00Z")

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "owner",
            context: context,
            now: date("2026-09-06T01:00:00Z")
        )

        XCTAssertEqual(session.startedAt, date("2026-09-06T23:30:00Z"))
        XCTAssertEqual(session.endedAt, date("2026-09-07T01:30:00Z"))
    }

    func testDateCorrectionNormalizesLegacyDerivedDurationBeforeMovingStart() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let originalStart = date("2026-09-06T21:30:17Z")
        let session = WorkoutSession(
            title: "Legacy",
            startedAt: originalStart,
            endedAt: date("2026-09-06T22:24:24Z"),
            durationSeconds: 0,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner"
        )
        context.insert(session)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-05T00:00:00Z")

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "owner",
            context: context,
            now: date("2026-09-06T23:00:00Z")
        )

        XCTAssertEqual(session.durationSeconds, 3_247)
        XCTAssertEqual(session.startedAt, date("2026-09-05T21:30:17Z"))
        XCTAssertEqual(session.endedAt, date("2026-09-05T22:24:24Z"))
    }

    func testUnchangedFutureDatedWorkoutCanStillSaveAnUnrelatedEdit() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let futureStart = date("2026-09-07T21:30:17Z")
        let session = WorkoutSession(
            title: "Imported future record",
            startedAt: futureStart,
            endedAt: date("2026-09-07T22:24:24Z"),
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner"
        )
        context.insert(session)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.title = "Corrected title"

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "owner",
            context: context,
            now: date("2026-09-06T23:00:00Z")
        )

        XCTAssertEqual(session.title, "Corrected title")
        XCTAssertEqual(session.startedAt, futureStart)
    }

    func testUnchangedDateDoesNotOverwriteAConcurrentTimingUpdate() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            title: "Concurrent",
            startedAt: date("2026-09-05T21:30:17Z"),
            endedAt: date("2026-09-05T22:24:24Z"),
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner"
        )
        context.insert(session)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-05T12:00:00Z")
        XCTAssertFalse(draft.didEditDate)
        let concurrentlyUpdatedStart = date("2026-09-04T10:15:00Z")
        session.startedAt = concurrentlyUpdatedStart
        session.endedAt = date("2026-09-04T11:09:07Z")
        draft.title = "Corrected title"

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "owner",
            context: context,
            now: date("2026-09-06T23:00:00Z")
        )

        XCTAssertEqual(session.title, "Corrected title")
        XCTAssertEqual(session.startedAt, concurrentlyUpdatedStart)
        XCTAssertEqual(session.endedAt, date("2026-09-04T11:09:07Z"))
    }

    func testRestoringOriginalDayWinsAConcurrentTimingUpdateAfterDateEdit() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let originalStart = date("2026-09-05T21:30:17Z")
        let session = WorkoutSession(
            title: "Concurrent",
            startedAt: originalStart,
            endedAt: date("2026-09-05T22:24:24Z"),
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner"
        )
        context.insert(session)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-04T00:00:00Z")
        draft.date = date("2026-09-05T00:00:00Z")
        session.startedAt = date("2026-09-03T10:15:00Z")
        session.endedAt = date("2026-09-03T11:09:07Z")

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "owner",
            context: context,
            now: date("2026-09-06T23:00:00Z")
        )

        XCTAssertEqual(session.startedAt, originalStart)
        XCTAssertEqual(session.endedAt, date("2026-09-05T22:24:24Z"))
    }

    func testRestoringOriginalDayIsNoOpWithoutConcurrentTimingUpdate() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let originalStart = date("2026-09-05T21:30:17Z")
        let originalEnd = date("2026-09-05T22:24:24Z")
        let session = WorkoutSession(
            title: "Round trip",
            startedAt: originalStart,
            endedAt: originalEnd,
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner"
        )
        context.insert(session)
        try context.save()
        let originalUpdatedAt = session.updatedAt
        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-04T00:00:00Z")
        draft.date = date("2026-09-05T00:00:00Z")

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft,
            for: session,
            ownerTokenIdentifier: "owner",
            context: context,
            now: date("2026-09-06T23:00:00Z")
        )

        XCTAssertEqual(session.startedAt, originalStart)
        XCTAssertEqual(session.endedAt, originalEnd)
        XCTAssertEqual(session.updatedAt, originalUpdatedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testDateEditReopensFromDiskWithOriginalIDsAndSetCompletion() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarosDateEditTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Baros.store")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let sessionID: UUID
        let setID: UUID

        do {
            var container: ModelContainer? = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: storeURL)
            let context = try XCTUnwrap(container?.mainContext)
            let completedAt = date("2026-09-06T21:45:00Z")
            let set = LoggedSet(orderIndex: 0, reps: 5, isCompleted: true, completedAt: completedAt)
            let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Squat", sets: [set])
            let session = WorkoutSession(
                title: "Disk",
                startedAt: date("2026-09-06T21:30:17Z"),
                endedAt: date("2026-09-06T22:24:24Z"),
                durationSeconds: 3_247,
                status: .completed,
                source: .blank,
                syncOwnerTokenIdentifier: "owner",
                loggedExercises: [exercise]
            )
            sessionID = session.id
            setID = set.id
            context.insert(session)
            try context.save()
            var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
            draft.date = date("2026-09-05T00:00:00Z")
            try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
                draft, for: session, ownerTokenIdentifier: "owner", context: context, now: date("2026-09-06T23:00:00Z")
            )
            container = nil
        }

        let container = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: storeURL)
        let context = container.mainContext
        let reopened = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first)
        XCTAssertEqual(reopened.id, sessionID)
        XCTAssertEqual(reopened.startedAt, date("2026-09-05T21:30:17Z"))
        XCTAssertEqual(reopened.endedAt, date("2026-09-05T22:24:24Z"))
        XCTAssertEqual(reopened.sortedLoggedExercises.first?.sortedSets.first?.id, setID)
        XCTAssertEqual(reopened.sortedLoggedExercises.first?.sortedSets.first?.completedAt, date("2026-09-06T21:45:00Z"))
    }

    func testDateEditRejectsActiveAndMismatchedOwnerWithoutMutation() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let active = WorkoutSession(title: "Active", startedAt: date("2026-09-06T21:30:17Z"), status: .active, source: .blank)
        let owned = WorkoutSession(
            title: "Owned",
            startedAt: date("2026-09-06T21:30:17Z"),
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner-a"
        )
        context.insert(active)
        context.insert(owned)
        try context.save()
        var activeDraft = CompletedWorkoutEditDraft(session: active, calendar: utcCalendar)
        activeDraft.date = date("2026-09-05T00:00:00Z")
        var ownedDraft = CompletedWorkoutEditDraft(session: owned, calendar: utcCalendar)
        ownedDraft.date = date("2026-09-05T00:00:00Z")

        XCTAssertThrowsError(try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            activeDraft, for: active, ownerTokenIdentifier: nil, context: context, now: date("2026-09-06T23:00:00Z")
        )) { XCTAssertEqual($0 as? WorkoutHistoryMutationError, .cannotEditWorkout) }
        XCTAssertThrowsError(try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            ownedDraft, for: owned, ownerTokenIdentifier: "owner-b", context: context, now: date("2026-09-06T23:00:00Z")
        )) { XCTAssertEqual($0 as? WorkoutHistoryMutationError, .ownerMismatch) }
        XCTAssertEqual(active.startedAt, date("2026-09-06T21:30:17Z"))
        XCTAssertEqual(owned.startedAt, date("2026-09-06T21:30:17Z"))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testDateEditPreflightFailureDoesNotPartiallyMutateOrQueue() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let set = LoggedSet(orderIndex: 0, reps: 5, isCompleted: true)
        let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Squat", sets: [set])
        let session = WorkoutSession(
            title: "Failure",
            startedAt: date("2026-09-06T21:30:17Z"),
            endedAt: date("2026-09-06T22:24:24Z"),
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: "owner",
            loggedExercises: [exercise]
        )
        context.insert(session)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-05T00:00:00Z")
        session.loggedExercises = []

        XCTAssertThrowsError(try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft, for: session, ownerTokenIdentifier: "owner", context: context, now: date("2026-09-06T23:00:00Z")
        )) { XCTAssertEqual($0 as? WorkoutHistoryMutationError, .missingLoggedExercise) }
        XCTAssertEqual(session.startedAt, date("2026-09-06T21:30:17Z"))
        XCTAssertEqual(session.endedAt, date("2026-09-06T22:24:24Z"))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testDateEditKeepsOwnerlessOutboxBehaviorAndUpdatesChronologyProjection() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let correctedSet = LoggedSet(orderIndex: 0, reps: 5, isCompleted: true)
        let correctedExercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press", sets: [correctedSet])
        let corrected = WorkoutSession(
            title: "Corrected",
            startedAt: date("2026-09-06T21:30:17Z"),
            endedAt: date("2026-09-06T22:24:24Z"),
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            loggedExercises: [correctedExercise]
        )
        let stillRecent = WorkoutSession(
            title: "Recent",
            startedAt: date("2026-09-05T21:30:17Z"),
            status: .completed,
            source: .blank,
            loggedExercises: [LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench Press", sets: [LoggedSet(orderIndex: 0, reps: 5, isCompleted: true)])]
        )
        context.insert(corrected)
        context.insert(stillRecent)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: corrected, calendar: utcCalendar)
        draft.date = date("2026-09-04T00:00:00Z")

        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft, for: corrected, context: context, now: date("2026-09-06T23:00:00Z")
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
        XCTAssertEqual(ExerciseHistorySummary.makeSummaries(from: [corrected, stillRecent]).first?.lastPerformedAt, stillRecent.startedAt)
    }

    func testOwnedDateEditExportsAndSynchronizesCorrectedWorkoutOnly() async throws {
        let owner = "owner"
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let completedAt = date("2026-09-06T21:45:00Z")
        let set = LoggedSet(orderIndex: 0, reps: 5, isCompleted: true, completedAt: completedAt)
        let exercise = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Squat", sets: [set])
        let session = WorkoutSession(
            title: "Exported",
            startedAt: date("2026-09-06T21:30:17Z"),
            endedAt: date("2026-09-06T22:24:24Z"),
            durationSeconds: 3_247,
            status: .completed,
            source: .blank,
            syncOwnerTokenIdentifier: owner,
            loggedExercises: [exercise]
        )
        context.insert(session)
        try context.save()
        var draft = CompletedWorkoutEditDraft(session: session, calendar: utcCalendar)
        draft.date = date("2026-09-05T00:00:00Z")
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(
            draft, for: session, ownerTokenIdentifier: owner, context: context, now: date("2026-09-06T23:00:00Z")
        )

        let csv = WorkoutDataExportService().csv(for: [session], unit: .pounds, ownerTokenIdentifier: owner)
        let exportRow = try XCTUnwrap(csv.split(separator: "\n").dropFirst().first)
        let exportColumns = exportRow.split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertTrue(exportColumns[0].hasPrefix("2026-09-05T21:30:17"), csv)
        XCTAssertTrue(exportColumns[14].hasPrefix("2026-09-06T21:45:00"), csv)

        let client = FakeSyncClient()
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)
        XCTAssertEqual(client.upsertedWorkoutSessions.count, 1)
        XCTAssertEqual(client.upsertedWorkoutSessions.first?.startedAt, date("2026-09-05T21:30:17Z").timeIntervalSince1970)
        XCTAssertEqual(client.upsertedWorkoutSessions.first?.endedAt, date("2026-09-05T22:24:24Z").timeIntervalSince1970)
        XCTAssertEqual(client.upsertedWorkoutSessions.first?.durationSeconds, 3_247)

        let correctedPayload = try XCTUnwrap(client.upsertedWorkoutSessions.first)
        let pullClient = FakeSyncClient()
        pullClient.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [
                    WorkoutSessionSyncRecord(
                        clientId: correctedPayload.clientId,
                        createdAt: correctedPayload.createdAt,
                        updatedAt: correctedPayload.updatedAt,
                        deletedAt: correctedPayload.deletedAt,
                        serverUpdatedAt: 1,
                        title: correctedPayload.title,
                        startedAt: correctedPayload.startedAt,
                        endedAt: correctedPayload.endedAt,
                        durationSeconds: correctedPayload.durationSeconds,
                        notes: correctedPayload.notes,
                        referenceNotes: correctedPayload.referenceNotes,
                        statusRaw: correctedPayload.statusRaw,
                        sourceRaw: correctedPayload.sourceRaw,
                        sourceSessionID: correctedPayload.sourceSessionID,
                        healthLinkID: correctedPayload.healthLinkID
                    ),
                ],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 1),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]
        let pullContainer = try SwiftDataTestSupport.makeInMemoryContainer()
        try await SyncCoordinator(client: pullClient).run(ownerTokenIdentifier: owner, context: pullContainer.mainContext)
        let pulled = try XCTUnwrap(pullContainer.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(pulled.startedAt, session.startedAt)
        XCTAssertEqual(pulled.endedAt, session.endedAt)
        XCTAssertEqual(pulled.durationSeconds, session.durationSeconds)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var chicagoCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private var lordHoweCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Lord_Howe")!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
