import CoreData
import SwiftData
import XCTest
@testable import BarosCore

/// Exercises logged by time instead of reps.
@MainActor
final class TimedExerciseTests: XCTestCase {
    // MARK: Entry and display

    func testZeroAndOutOfRangeTimesAreNotRecorded() {
        XCTAssertNil(WorkoutNumericInputPolicy.validatedDuration(0))
        XCTAssertNil(WorkoutNumericInputPolicy.validatedDuration(-5))
        XCTAssertNil(WorkoutNumericInputPolicy.validatedDuration(3_600), "The picker stops at 59:59")
        XCTAssertEqual(WorkoutNumericInputPolicy.validatedDuration(1), 1)
        XCTAssertEqual(WorkoutNumericInputPolicy.validatedDuration(3_599), 3_599)
    }

    func testSetTimesDisplayWithoutLeadingZeroMinutes() {
        XCTAssertEqual(WorkoutFormatters.setDuration(45), "0:45")
        XCTAssertEqual(WorkoutFormatters.setDuration(90), "1:30")
        XCTAssertEqual(WorkoutFormatters.setDuration(600), "10:00")
        XCTAssertEqual(WorkoutFormatters.setDuration(3_900), "1:05:00")
        XCTAssertEqual(WorkoutFormatters.setDurationAccessibilityDescription(90), "1 minute, 30 seconds")
        XCTAssertEqual(WorkoutFormatters.setDurationAccessibilityDescription(3_601), "1 hour, 1 second")
    }

    func testAPickedTimeReplacesOnlyTheTime() {
        let stored = ActiveWorkoutSetInput.Values(weight: 45, durationSeconds: 60)
        XCTAssertEqual(stored.settingDuration(90), .init(weight: 45, durationSeconds: 90))
        XCTAssertEqual(stored.settingDuration(nil), .init(weight: 45), "Clearing removes the time")
        XCTAssertEqual(stored.settingDuration(0), .init(weight: 45), "Zero is no time")
    }

    func testATypedWeightKeepsTheStoredTime() {
        var input = ActiveWorkoutSetInput()
        let stored = ActiveWorkoutSetInput.Values(durationSeconds: 90)
        input.update("45", for: .weight, isFocused: true)
        XCTAssertEqual(input.commit(current: stored, weightUnit: .pounds),
                       .init(values: .init(weight: 45, durationSeconds: 90), shouldPersist: true))
        XCTAssertEqual(input.text(for: .duration, values: stored, weightUnit: .pounds), "1:30")
    }

    func testCompletingAnEmptyTimedSetFillsFromTheSetAboveThenLastTime() {
        let previous = PreviousSetPerformance(weight: 25, reps: nil, durationSeconds: 60, trackingMethod: .duration)
        var input = ActiveWorkoutSetInput()
        XCTAssertEqual(
            input.preparedValuesForSetAction(
                current: .init(), weightUnit: .pounds, completesSet: true, isCompleted: false,
                previous: previous, suggestions: .init(durationSeconds: 75)
            ),
            .init(weight: 25, durationSeconds: 75)
        )
        XCTAssertEqual(input.suggestionText(for: .duration, current: .init(), suggestions: .init(durationSeconds: 75),
                                            weightUnit: .pounds), "1:15")
    }

    func testSuggestionsCarryTimeDownTheSets() {
        XCTAssertEqual(ActiveWorkoutSetSuggestions.resolve(for: [
            .init(weight: 25, durationSeconds: 60), .init(), .init(durationSeconds: 45), .init(),
        ]), [
            .init(), .init(weight: 25, durationSeconds: 60),
            .init(weight: 25, durationSeconds: 60), .init(weight: 25, durationSeconds: 45),
        ])
    }

    func testPreviousColumnShowsTimeAndOmitsAMissingWeight() {
        func text(_ weight: Double?, _ seconds: Int?) -> String {
            PreviousSetPerformance(weight: weight, reps: nil, durationSeconds: seconds, trackingMethod: .duration)
                .displayText(weightUnit: .pounds)
        }
        XCTAssertEqual(text(nil, 90), "1:30")
        XCTAssertEqual(text(70, 90), "70 × 1:30")
        XCTAssertEqual(text(70, nil), "70 × -")
        XCTAssertEqual(text(nil, nil), "—")
        XCTAssertEqual(PreviousSetPerformance(weight: nil, reps: 8).displayText(weightUnit: .pounds), "- × 8")
    }

    // MARK: Tracking method

    func testExercisesAndWorkoutsFromBeforeTimedExercisesAreRepBased() throws {
        let exercise = Exercise(name: "Bench", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        XCTAssertNil(exercise.trackingMethodRaw)
        XCTAssertEqual(exercise.trackingMethod, .reps)
        let logged = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench")
        XCTAssertNil(logged.trackingMethodRaw)
        XCTAssertEqual(logged.trackingMethod, .reps)
        XCTAssertEqual(ExerciseTrackingMethod(storedRawValue: "distance"), .reps, "An unknown method reads as reps")
    }

    func testEditingAnExerciseStoresAMethodOnlyWhenItChanges() throws {
        let context = try makeContext()
        let service = ExerciseMutationService()
        let exercise = try service.createExercise(
            name: "Plank", category: .strength, equipment: .bodyweight, primaryMuscle: "Core",
            trackingMethod: .duration, notes: "", context: context
        )
        XCTAssertEqual(exercise.trackingMethodRaw, "duration")

        let legacy = Exercise(name: "Bench", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(legacy)
        try service.updateExercise(
            legacy, name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest",
            trackingMethod: .reps, notes: "", context: context
        )
        XCTAssertNil(legacy.trackingMethodRaw, "Renaming doesn't claim a method nobody chose")

        try service.updateExercise(
            legacy, name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest",
            trackingMethod: .duration, notes: "", context: context
        )
        XCTAssertEqual(legacy.trackingMethodRaw, "duration")
        try service.updateExercise(
            legacy, name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest",
            trackingMethod: .reps, notes: "", context: context
        )
        XCTAssertEqual(legacy.trackingMethodRaw, "reps")
    }

    func testAddingAnExerciseSnapshotsItsMethodAndALaterLibraryEditLeavesTheWorkoutAlone() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let logged = try engine.addExercise(plank, to: session, context: context)
        XCTAssertEqual(logged.trackingMethod, .duration)

        plank.trackingMethod = .reps
        XCTAssertEqual(logged.trackingMethod, .duration)
        XCTAssertEqual(logged.sortedSets.first?.trackingMethod, .duration)
    }

    func testSwappingTakesTheNewExercisesMethod() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let bench = try insertExercise("Bench", .reps, into: context)
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let logged = try engine.addExercise(bench, to: session, context: context)
        let replacement = try engine.swapLoggedExercise(logged, with: plank, context: context)
        XCTAssertEqual(replacement.trackingMethod, .duration)
    }

    func testStartingFromATemplateUsesTheExercisesCurrentMethod() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let template = WorkoutTemplate(name: "Core", entries: [WorkoutTemplateEntry(exercise: plank)])
        context.insert(template)
        try context.save()
        let session = try ActiveWorkoutEngine().startWorkout(fromTemplate: template, context: context)
        XCTAssertEqual(session.sortedLoggedExercises.map(\.trackingMethod), [.duration])
    }

    // MARK: Logging

    func testATimedSetStoresSecondsAndNeverReps() throws {
        let (context, engine, logged) = try makeTimedWorkout()
        let set = try XCTUnwrap(logged.sortedSets.first)
        try engine.toggleSetCompletion(set, preparedValues: .init(weight: 45, durationSeconds: 90), context: context)

        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.durationSeconds, 90)
        XCTAssertEqual(set.weight, 45)
        XCTAssertNil(set.reps)
        XCTAssertEqual(set.completedVolume, 0, "Time is not lifting volume")
        let metrics = WorkoutMetrics(session: try XCTUnwrap(logged.session))
        XCTAssertEqual(metrics.completedSetCount, 1)
        XCTAssertEqual(metrics.completedVolume, 0)
    }

    func testTimeOnlySetsNeedNoWeight() throws {
        let (context, engine, logged) = try makeTimedWorkout()
        let set = try XCTUnwrap(logged.sortedSets.first)
        XCTAssertTrue(try engine.commitActiveSetDraft(set, values: .init(durationSeconds: 60), context: context))
        XCTAssertEqual(set.durationSeconds, 60)
        XCTAssertNil(set.weight)
        XCTAssertFalse(try engine.commitActiveSetDraft(set, values: .init(durationSeconds: 60), context: context),
                       "An unchanged time is not saved again")
        XCTAssertTrue(try engine.commitActiveSetDraft(set, values: .init(), context: context))
        XCTAssertNil(set.durationSeconds)
    }

    func testAFailedSaveRestoresTheTime() throws {
        let (context, engine, logged) = try makeTimedWorkout()
        let set = try XCTUnwrap(logged.sortedSets.first)
        try engine.commitActiveSetDraft(set, values: .init(durationSeconds: 60), context: context)
        XCTAssertThrowsError(try engine.toggleSetCompletion(
            set, preparedValues: .init(durationSeconds: 90), context: context,
            save: { _ in throw CocoaError(.fileWriteUnknown) }
        ))
        XCTAssertEqual(set.durationSeconds, 60)
        XCTAssertFalse(set.isCompleted)
    }

    func testPreviousValuesCarryOnlyTheMeasureTheExerciseIsLoggedBy() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let past = try insertCompletedWorkout(of: plank, sets: [(nil, 60), (10, 75)], into: context)
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 5_000))
        let logged = try engine.addExercise(plank, to: session, context: context)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        let previous = PreviousSetPerformance.lastCompletedSets(for: logged, in: sessions, ownerTokenIdentifier: nil)
        XCTAssertEqual(previous.map { $0.displayText(weightUnit: .pounds) }, ["1:00", "10 × 1:15"])

        let set = try XCTUnwrap(logged.sortedSets.first)
        try engine.fillSetFromPrevious(set, previous: previous[1], context: context)
        XCTAssertEqual(set.durationSeconds, 75)
        XCTAssertEqual(set.weight, 10)
        XCTAssertNil(set.reps)

        // The exercise is switched to reps: its timed history offers no reps to fill.
        plank.trackingMethod = .reps
        let repLogged = try engine.swapLoggedExercise(
            logged, with: try insertExercise("Other", .reps, into: context), context: context
        )
        XCTAssertEqual(repLogged.trackingMethod, .reps)
        let pastLogged = try XCTUnwrap(past.sortedLoggedExercises.first)
        XCTAssertEqual(pastLogged.trackingMethod, .duration, "History keeps how it was logged")
    }

    func testRepeatingAPastWorkoutKeepsItsMethodAndTimedPreviousValues() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let past = try insertCompletedWorkout(of: plank, sets: [(nil, 60)], into: context)
        plank.trackingMethod = .reps
        try context.save()

        let engine = ActiveWorkoutEngine()
        let session = try engine.startWorkout(fromPast: past, context: context)
        let logged = try XCTUnwrap(session.sortedLoggedExercises.first)
        XCTAssertEqual(logged.trackingMethod, .duration)
        XCTAssertNil(logged.sortedSets.first?.durationSeconds, "Values are not copied, only offered")

        let previous = PreviousSetPerformance.lastCompletedSets(
            for: logged, in: try context.fetch(FetchDescriptor<WorkoutSession>()),
            ownerTokenIdentifier: nil, sourceSessionID: past.id
        )
        XCTAssertEqual(previous.map(\.durationSeconds), [60])
    }

    func testASupersetRoundFillsATimedPartnerFromItsOwnHistory() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let bench = try insertExercise("Bench", .reps, into: context)
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let benchLogged = try engine.addExercise(bench, to: session, context: context)
        let plankLogged = try engine.addExercise(plank, to: session, context: context)
        let group = UUID()
        benchLogged.supersetGroupID = group
        plankLogged.supersetGroupID = group
        engine.previousSetsByLoggedExerciseID[plankLogged.id] = [
            PreviousSetPerformance(weight: nil, reps: nil, durationSeconds: 60, trackingMethod: .duration)
        ]

        try engine.toggleSetCompletion(
            try XCTUnwrap(benchLogged.sortedSets.first), preparedValues: .init(weight: 135, reps: 8), context: context
        )
        let plankSet = try XCTUnwrap(plankLogged.sortedSets.first)
        XCTAssertTrue(plankSet.isCompleted)
        XCTAssertEqual(plankSet.durationSeconds, 60)
        XCTAssertNil(plankSet.reps)
    }

    // MARK: Completed workout edits, history, export

    func testEditingACompletedWorkoutChangesAndAddsTimedSets() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let session = try insertCompletedWorkout(of: plank, sets: [(nil, 60)], into: context)
        var draft = CompletedWorkoutEditDraft(session: session)
        XCTAssertEqual(draft.exercises[0].trackingMethod, .duration)
        XCTAssertEqual(draft.exercises[0].sets[0].durationSeconds, 60)

        draft.exercises[0].sets[0].durationSeconds = 95
        draft.exercises[0].sets.append(CompletedWorkoutEditSetDraft(orderIndex: 1, durationSeconds: 30, isCompleted: true))
        draft.exercises[0].sets.append(CompletedWorkoutEditSetDraft(orderIndex: 2))
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(draft, for: session, context: context)

        let sets = session.sortedLoggedExercises[0].sortedSets
        XCTAssertEqual(sets.map(\.durationSeconds), [95, 30], "An empty new row is not saved")
        XCTAssertEqual(sets.map(\.reps), [nil, nil])
    }

    func testAnOutOfRangeEditedTimeIsDropped() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let session = try insertCompletedWorkout(of: plank, sets: [(nil, 60)], into: context)
        var draft = CompletedWorkoutEditDraft(session: session)
        draft.exercises[0].sets.append(
            CompletedWorkoutEditSetDraft(orderIndex: 1, durationSeconds: 900_000, isCompleted: true)
        )
        try WorkoutHistoryMutationService().saveCompletedWorkoutEdit(draft, for: session, context: context)
        XCTAssertEqual(session.sortedLoggedExercises[0].sortedSets.map(\.durationSeconds), [60, nil])
    }

    func testAnExerciseLoggedByTimeHasNoStrengthRecords() throws {
        let context = try makeContext()
        let carry = try insertExercise("Farmer Carry", .duration, equipment: .dumbbell, into: context)
        _ = try insertCompletedWorkout(of: carry, sets: [(70, 60)], into: context)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let summary = try XCTUnwrap(
            ExerciseHistorySummary.makeSummaries(from: sessions, ownerTokenIdentifier: nil).first
        )
        let groups = ExerciseHistorySessionGroup.makeGroups(from: sessions, matching: summary, ownerTokenIdentifier: nil)
        XCTAssertEqual(groups.first?.completedSetCount, 1)
        XCTAssertNil(ExerciseHistoryRecords.make(from: groups, equipmentRaw: summary.equipmentRaw))
    }

    func testCSVAddsTimeInSecondsAsTheLastColumn() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let session = try insertCompletedWorkout(of: plank, sets: [(nil, 90), (25, 2_700)], into: context)
        let lines = WorkoutDataExportService().csv(for: [session], unit: .pounds)
            .split(separator: "\n").map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertEqual(lines[0].last, "duration_seconds")
        XCTAssertEqual(lines[0].firstIndex(of: "reps"), 10, "Existing columns keep their positions")
        XCTAssertEqual(lines.dropFirst().map { $0[10] }, ["", ""])
        XCTAssertEqual(lines.dropFirst().map(\.last), ["90", "2700"])
        XCTAssertEqual(lines.dropFirst().map { $0[9] }, ["", "25"])
    }

    // MARK: Sync

    func testUploadsCarryTheMethodAndTimeOnceThisDeviceKnowsThem() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let session = try insertCompletedWorkout(of: plank, sets: [(nil, 90), (nil, nil)], into: context)
        let logged = session.sortedLoggedExercises[0]

        XCTAssertEqual(SyncPayloadMapper.exercisePayload(from: plank).trackingMethodRaw, "duration")
        XCTAssertEqual(SyncPayloadMapper.loggedExercisePayload(from: logged).trackingMethodRaw, "duration")
        let timed = SyncPayloadMapper.loggedSetPayload(from: logged.sortedSets[0])
        XCTAssertEqual(timed.durationSeconds, 90)
        XCTAssertTrue(timed.sendsDurationSeconds)
        XCTAssertNil(timed.reps)
        let cleared = SyncPayloadMapper.loggedSetPayload(from: logged.sortedSets[1])
        XCTAssertNil(cleared.durationSeconds)
        XCTAssertTrue(cleared.sendsDurationSeconds, "A known timed set uploads an explicit null")
    }

    func testASetWhoseTimeThisDeviceNeverSawDoesNotClearItOnUpload() throws {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let session = try insertCompletedWorkout(of: plank, sets: [(nil, nil)], into: context)
        let set = session.sortedLoggedExercises[0].sortedSets[0]
        // The row was saved by a build without durations; only its exercise
        // has since been pulled with the method.
        set.knowsDuration = nil
        set.weight = 25

        XCTAssertFalse(SyncPayloadMapper.loggedSetPayload(from: set).sendsDurationSeconds)
        set.durationSeconds = 60
        XCTAssertTrue(SyncPayloadMapper.loggedSetPayload(from: set).sendsDurationSeconds)
    }

    func testRowsFromBeforeTimedExercisesUploadWithoutTheNewFields() throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(bench)
        let logged = LoggedExercise(orderIndex: 0, exerciseSnapshotName: "Bench",
                                    sets: [LoggedSet(orderIndex: 0, weight: 135, reps: 8, isCompleted: true)])
        context.insert(logged)

        XCTAssertNil(SyncPayloadMapper.exercisePayload(from: bench).trackingMethodRaw)
        XCTAssertNil(SyncPayloadMapper.loggedExercisePayload(from: logged).trackingMethodRaw)
        let payload = SyncPayloadMapper.loggedSetPayload(from: logged.sets[0])
        XCTAssertFalse(payload.sendsDurationSeconds, "The server keeps a time this device may never have seen")
        XCTAssertNil(payload.durationSeconds)
    }

    func testOutOfRangeStoredTimeIsNotUploaded() throws {
        let set = LoggedSet(orderIndex: 0, durationSeconds: 900_000)
        XCTAssertNil(SyncPayloadMapper.loggedSetPayload(from: set).durationSeconds)
    }

    func testDownloadsDecodeWithAndWithoutTheNewFields() throws {
        func decode<Record: Decodable>(_ type: Record.Type, _ json: String) throws -> Record {
            try JSONDecoder().decode(type, from: Data(json.utf8))
        }
        let setJSON = """
        "clientId":"x","createdAt":1,"updatedAt":2,"deletedAt":null,"serverUpdatedAt":3,
        "loggedExerciseClientId":"e","orderIndex":0,"weight":null,"reps":null,"rpe":null,"kindRaw":"working",
        "isCompleted":true,"completedAt":2,"notes":"","healthLinkID":null,"sourceLoggedSetID":null
        """
        XCTAssertNil(try decode(LoggedSetSyncRecord.self, "{\(setJSON)}").durationSeconds)
        XCTAssertNil(try decode(LoggedSetSyncRecord.self, "{\(setJSON),\"durationSeconds\":null}").durationSeconds)
        XCTAssertEqual(try decode(LoggedSetSyncRecord.self, "{\(setJSON),\"durationSeconds\":90}").durationSeconds, 90)

        let exerciseJSON = """
        "clientId":"x","createdAt":1,"updatedAt":2,"deletedAt":null,"serverUpdatedAt":3,"seedIdentifier":null,
        "name":"Plank","categoryRaw":"strength","equipmentRaw":"bodyweight","primaryMuscleRaw":"Core",
        "primaryMuscleGroupRaw":"core","notes":"","isArchived":false,"isSeeded":false
        """
        XCTAssertNil(try decode(ExerciseSyncRecord.self, "{\(exerciseJSON)}").trackingMethodRaw)
        XCTAssertEqual(
            try decode(ExerciseSyncRecord.self, "{\(exerciseJSON),\"trackingMethodRaw\":\"duration\"}").trackingMethodRaw,
            "duration"
        )
    }

    func testPullAppliesTheServersMethodAndTime() async throws {
        let owner = "issuer|owner"
        let context = try makeContext()
        let plank = try insertExercise("Plank", nil, owner: owner, into: context)
        let session = try insertCompletedWorkout(of: plank, sets: [(nil, nil)], owner: owner, into: context)
        let logged = session.sortedLoggedExercises[0]
        let set = logged.sortedSets[0]
        XCTAssertEqual(logged.trackingMethod, .reps)

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [
                    ExerciseSyncRecord(
                        clientId: plank.id.uuidString.lowercased(), createdAt: 1,
                        updatedAt: plank.updatedAt.timeIntervalSince1970 + 10, deletedAt: nil, serverUpdatedAt: 50,
                        seedIdentifier: nil, name: "Plank", categoryRaw: "strength", equipmentRaw: "bodyweight",
                        primaryMuscleRaw: "Core", primaryMuscleGroupRaw: "core", notes: "", isArchived: false,
                        isSeeded: false, trackingMethodRaw: "duration"
                    )
                ],
                workoutSessions: [],
                loggedExercises: [
                    LoggedExerciseSyncRecord(
                        clientId: logged.id.uuidString.lowercased(), createdAt: 1,
                        updatedAt: logged.updatedAt.timeIntervalSince1970 + 10, deletedAt: nil, serverUpdatedAt: 51,
                        sessionClientId: session.id.uuidString.lowercased(),
                        exerciseClientId: plank.id.uuidString.lowercased(), orderIndex: 0,
                        exerciseSnapshotName: "Plank", exerciseSnapshotEquipmentRaw: "bodyweight",
                        exerciseSnapshotPrimaryMuscleGroupRaw: "core", hasSnapshotMetadata: true, notes: "",
                        referenceNotes: nil, sourceLoggedExerciseID: nil, trackingMethodRaw: "duration"
                    )
                ],
                loggedSets: [
                    LoggedSetSyncRecord(
                        clientId: set.id.uuidString.lowercased(), createdAt: 1,
                        updatedAt: set.updatedAt.timeIntervalSince1970 + 10, deletedAt: nil, serverUpdatedAt: 52,
                        loggedExerciseClientId: logged.id.uuidString.lowercased(), orderIndex: 0, weight: nil,
                        reps: nil, rpe: nil, kindRaw: "working", isCompleted: true, completedAt: 2, notes: "",
                        healthLinkID: nil, sourceLoggedSetID: nil, durationSeconds: 90
                    )
                ],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 50, workoutSessions: 0,
                                           loggedExercises: 51, loggedSets: 52),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]
        _ = try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(plank.trackingMethod, .duration)
        XCTAssertEqual(logged.trackingMethod, .duration)
        XCTAssertEqual(set.durationSeconds, 90)
    }

    // MARK: Persistence

    func testTimeAndMethodSurviveRelaunch() throws {
        let url = try makeStoreURL("test.store")
        do {
            let container = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: url)
            let context = container.mainContext
            let plank = try insertExercise("Plank", .duration, into: context)
            _ = try insertCompletedWorkout(of: plank, sets: [(nil, 90)], into: context)
        }
        let relaunched = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: url)
        containers.append(relaunched)
        let logged = try XCTUnwrap(relaunched.mainContext.fetch(FetchDescriptor<LoggedExercise>()).first)
        XCTAssertEqual(logged.trackingMethod, .duration)
        XCTAssertEqual(logged.exercise?.trackingMethod, .duration)
        XCTAssertEqual(logged.sortedSets.map(\.durationSeconds), [90])
    }

    /// A store written before timed exercises opens with its history intact and rep-based.
    func testStoreFromBeforeTimedExercisesUpgradesAsRepBased() throws {
        let url = try makeStoreURL("legacy.store")
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: BarosSchema.models))
        let legacy = try XCTUnwrap(model.copy() as? NSManagedObjectModel)
        let added = ["Exercise": "trackingMethodRaw", "LoggedExercise": "trackingMethodRaw", "LoggedSet": "durationSeconds"]
        for (entityName, attribute) in added {
            let entity = try XCTUnwrap(legacy.entitiesByName[entityName])
            entity.properties.removeAll { $0.name == attribute }
            XCTAssertNil(entity.attributesByName[attribute])
        }

        let setID = UUID()
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: legacy)
            let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
            let context = NSManagedObjectContext(.mainQueue)
            context.persistentStoreCoordinator = coordinator
            var rows: [String: NSManagedObject] = [:]
            for entityName in added.keys {
                let entity = try XCTUnwrap(legacy.entitiesByName[entityName])
                let row = NSManagedObject(entity: entity, insertInto: context)
                for attribute in entity.attributesByName.values where !attribute.isOptional && attribute.defaultValue == nil {
                    row.setValue(Self.placeholder(for: attribute.attributeType), forKey: attribute.name)
                }
                rows[entityName] = row
            }
            rows["Exercise"]?.setValue("Plank", forKey: "name")
            rows["LoggedExercise"]?.setValue("Plank", forKey: "exerciseSnapshotName")
            rows["LoggedExercise"]?.setValue(rows["Exercise"], forKey: "exercise")
            rows["LoggedSet"]?.setValue(setID, forKey: "id")
            rows["LoggedSet"]?.setValue(60, forKey: "reps")
            rows["LoggedSet"]?.setValue(true, forKey: "isCompleted")
            rows["LoggedSet"]?.setValue(rows["LoggedExercise"], forKey: "loggedExercise")
            try context.save()
            try coordinator.remove(store)
        }

        let container = try SwiftDataTestSupport.makeDiskBackedContainer(storeURL: url)
        containers.append(container)
        let set = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<LoggedSet>()).first)
        XCTAssertEqual(set.id, setID)
        XCTAssertEqual(set.reps, 60, "Old seconds-as-reps history is left exactly as logged")
        XCTAssertNil(set.durationSeconds)
        let logged = try XCTUnwrap(set.loggedExercise)
        XCTAssertEqual(logged.exerciseSnapshotName, "Plank")
        XCTAssertNil(logged.trackingMethodRaw)
        XCTAssertEqual(logged.trackingMethod, .reps)
        XCTAssertEqual(logged.exercise?.trackingMethod, .reps)
        XCTAssertFalse(SyncPayloadMapper.loggedSetPayload(from: set).sendsDurationSeconds)

        logged.exercise?.trackingMethod = .duration
        set.durationSeconds = 45
        try container.mainContext.save()
    }

    // MARK: Helpers

    private var containers: [ModelContainer] = []
    private var directories: [URL] = []

    override func tearDown() {
        containers = []
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        containers.append(container)
        return container.mainContext
    }

    private func makeStoreURL(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        return directory.appendingPathComponent(name)
    }

    private func insertExercise(
        _ name: String,
        _ method: ExerciseTrackingMethod?,
        equipment: ExerciseEquipment = .bodyweight,
        owner: String? = nil,
        into context: ModelContext
    ) throws -> Exercise {
        let exercise = Exercise(
            name: name, category: .strength, equipment: equipment, primaryMuscleGroup: .core,
            trackingMethod: method, syncOwnerTokenIdentifier: owner
        )
        context.insert(exercise)
        try context.save()
        return exercise
    }

    private func makeTimedWorkout() throws -> (ModelContext, ActiveWorkoutEngine, LoggedExercise) {
        let context = try makeContext()
        let plank = try insertExercise("Plank", .duration, into: context)
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        return (context, engine, try engine.addExercise(plank, to: session, context: context))
    }

    /// One completed workout of `exercise`, each set given as (weight, seconds).
    private func insertCompletedWorkout(
        of exercise: Exercise,
        sets: [(Double?, Int?)],
        owner: String? = nil,
        into context: ModelContext
    ) throws -> WorkoutSession {
        let start = Date(timeIntervalSince1970: 100)
        let session = WorkoutSession(
            title: "Workout", startedAt: start, endedAt: start.addingTimeInterval(60), status: .completed,
            source: .blank, createdAt: start, updatedAt: start, syncOwnerTokenIdentifier: owner
        )
        context.insert(session)
        let logged = LoggedExercise(orderIndex: 0, exercise: exercise, createdAt: start, updatedAt: start)
        context.insert(logged)
        logged.session = session
        session.loggedExercises.append(logged)
        for (index, values) in sets.enumerated() {
            let set = LoggedSet(orderIndex: index, weight: values.0, durationSeconds: values.1, isCompleted: true,
                                completedAt: start, createdAt: start, updatedAt: start)
            context.insert(set)
            set.loggedExercise = logged
            logged.sets.append(set)
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
}
