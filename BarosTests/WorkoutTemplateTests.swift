import SwiftData
import XCTest
@testable import Baros

private let owner = "issuer|owner_a"

@MainActor
final class WorkoutTemplateTests: XCTestCase {
    // MARK: - Mutations

    func testCreateRecordsAnOwnedCreateAndNormalizesGrouping() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bench = makeExercise("Bench Press", owner: owner)
        context.insert(bench)
        let lone = UUID()

        let template = try WorkoutTemplateMutationService().createTemplate(
            name: "Upper Day",
            entries: [WorkoutTemplateEntry(exercise: bench, supersetGroupID: lone)],
            ownerTokenIdentifier: owner,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(template.syncOwnerTokenIdentifier, owner)
        XCTAssertNil(template.entries[0].supersetGroupID, "a group of one is not a superset")
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(entries.map(\.entityKind), [.workoutTemplate])
        XCTAssertEqual(entries.map(\.operation), [.create])
        XCTAssertEqual(entries.first?.ownerTokenIdentifier, owner)
    }

    func testUpdateWithoutChangesRecordsNothing() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bench = makeExercise("Bench Press", owner: owner)
        context.insert(bench)
        let service = WorkoutTemplateMutationService()
        let template = try service.createTemplate(
            name: "Upper Day", entries: [WorkoutTemplateEntry(exercise: bench)],
            ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 100)
        )
        try deleteOutbox(context)

        try service.updateTemplate(
            template, name: "Upper Day", entries: template.entries,
            ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(template.updatedAt, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testDeleteTombstonesAndRecordsADelete() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let service = WorkoutTemplateMutationService()
        let template = try service.createTemplate(
            name: "Upper Day", entries: [], ownerTokenIdentifier: owner,
            context: context, now: Date(timeIntervalSince1970: 100)
        )
        try deleteOutbox(context)

        try service.deleteTemplate(template, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(template.deletedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).map(\.operation), [.delete])
    }

    func testAnotherOwnersTemplateCannotBeEdited() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "Theirs", syncOwnerTokenIdentifier: "issuer|owner_b")
        context.insert(template)

        XCTAssertThrowsError(try WorkoutTemplateMutationService().updateTemplate(
            template, name: "Mine", entries: [], ownerTokenIdentifier: owner, context: context
        ))
        XCTAssertEqual(template.name, "Theirs")
    }

    // MARK: - Sync

    func testPushUploadsEntriesInOrderWithGrouping() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        let bench = makeExercise("Bench Press", owner: owner)
        let row = makeExercise("Row", owner: owner)
        context.insert(bench)
        context.insert(row)
        let group = UUID()
        let template = try WorkoutTemplateMutationService().createTemplate(
            name: "Upper Day",
            entries: [
                WorkoutTemplateEntry(exercise: bench, supersetGroupID: group),
                WorkoutTemplateEntry(exercise: row, supersetGroupID: group),
            ],
            ownerTokenIdentifier: owner,
            context: context
        )
        let client = FakeSyncClient()

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let payload = try XCTUnwrap(client.upsertedWorkoutTemplates.first)
        XCTAssertEqual(payload.clientId, template.id.uuidString.lowercased())
        XCTAssertEqual(payload.name, "Upper Day")
        XCTAssertEqual(payload.entries.map(\.exerciseClientId), [bench.id, row.id].map { $0.uuidString.lowercased() })
        XCTAssertEqual(payload.entries.map(\.supersetGroupID), Array(repeating: group.uuidString.lowercased(), count: 2))
        XCTAssertEqual(client.fetchRequests.first?.cursors.workoutTemplates, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testPullInsertsUpdatesAndTombstonesTemplates() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let templateID = UUID()
        let exerciseID = UUID()
        let entryID = UUID()
        let client = FakeSyncClient()
        client.fetchResponses = [
            response(templates: [record(id: templateID, name: "Upper Day", updatedAt: 20, serverUpdatedAt: 40, entries: [
                entryPayload(id: entryID, exerciseID: exerciseID, name: "Bench Press"),
            ])]),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        let template = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutTemplate>()).first)
        XCTAssertEqual(template.id, templateID)
        XCTAssertEqual(template.syncOwnerTokenIdentifier, owner)
        XCTAssertEqual(template.entries.map(\.id), [entryID])
        XCTAssertEqual(template.entries.first?.exerciseID, exerciseID, "kept even though the exercise hasn't arrived yet")
        let state = try SyncCursorState.state(for: owner, context: context)
        XCTAssertEqual(state.workoutTemplatesCursor, 40)

        client.fetchResponses = [
            response(templates: [record(id: templateID, name: "Upper Day", updatedAt: 30, deletedAt: 30, serverUpdatedAt: 50, entries: [])]),
        ]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.fetchRequests.last?.cursors.workoutTemplates, 40)
        XCTAssertEqual(template.deletedAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(state.workoutTemplatesCursor, 50)
    }

    func testPullKeepsANewerLocalEdit() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(
            name: "Local Name", syncOwnerTokenIdentifier: owner,
            createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(template)
        let client = FakeSyncClient()
        client.fetchResponses = [
            response(templates: [record(id: template.id, name: "Remote Name", updatedAt: 50, serverUpdatedAt: 60, entries: [])]),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(template.name, "Local Name")
    }

    func testSignInClaimsTemplatesMadeWhileSignedOut() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let template = try WorkoutTemplateMutationService().createTemplate(
            name: "Planned", entries: [], ownerTokenIdentifier: nil, context: context
        )
        let client = FakeSyncClient()

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(template.syncOwnerTokenIdentifier, owner)
        XCTAssertEqual(client.upsertedWorkoutTemplates.map(\.clientId), [template.id.uuidString.lowercased()])
    }

    func testMergingADuplicateSeedRepointsTemplateEntries() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(SyncCursorState(
            ownerTokenIdentifier: owner,
            hasBootstrappedSettingsExercises: true,
            hasBootstrappedWorkoutGraph: true
        ))
        let canonical = makeExercise("Back Squat", owner: owner, seedIdentifier: "back-squat")
        let duplicate = makeExercise("Back Squat", owner: nil, seedIdentifier: "back-squat")
        context.insert(canonical)
        context.insert(duplicate)
        let template = try WorkoutTemplateMutationService().createTemplate(
            name: "Legs", entries: [WorkoutTemplateEntry(exercise: duplicate)],
            ownerTokenIdentifier: nil, context: context
        )
        let client = FakeSyncClient()

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(template.entries.map(\.exerciseID), [canonical.id])
        XCTAssertEqual(
            client.upsertedWorkoutTemplates.last?.entries.map(\.exerciseClientId),
            [canonical.id.uuidString.lowercased()]
        )
    }

    func testAdoptingARemoteSeedRepointsTemplateEntries() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let localBench = makeExercise("Bench Press", owner: nil, seedIdentifier: "bench-press")
        context.insert(localBench)
        let localID = localBench.id
        let template = try WorkoutTemplateMutationService().createTemplate(
            name: "Push", entries: [WorkoutTemplateEntry(exercise: localBench)],
            ownerTokenIdentifier: nil, context: context
        )
        let remoteID = UUID()
        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [ExerciseSyncRecord(
                    clientId: remoteID.uuidString.lowercased(),
                    createdAt: 10, updatedAt: 20, deletedAt: nil, serverUpdatedAt: 30,
                    seedIdentifier: "bench-press", name: "Bench Press", categoryRaw: "strength",
                    equipmentRaw: "barbell", primaryMuscleRaw: "Chest", primaryMuscleGroupRaw: "chest",
                    notes: "", isArchived: false, isSeeded: true
                )],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [],
                cursors: SyncChangeCursors(userSettings: 0, exercises: 30),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            ),
        ]

        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(localBench.id, remoteID)
        XCTAssertNotEqual(localID, remoteID)
        XCTAssertEqual(template.entries.map(\.exerciseID), [remoteID])
        XCTAssertEqual(
            client.upsertedWorkoutTemplates.last?.entries.map(\.exerciseClientId),
            [remoteID.uuidString.lowercased()]
        )
    }

    // MARK: - Starting a workout

    func testStartingFromATemplateCopiesExercisesWithFreshGroups() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bench = makeExercise("Bench Press", owner: owner)
        let row = makeExercise("Row", owner: owner)
        let curl = makeExercise("Curl", owner: owner)
        [bench, row, curl].forEach(context.insert)
        let group = UUID()
        let template = WorkoutTemplate(
            name: "Upper Day",
            entries: [
                WorkoutTemplateEntry(exercise: bench),
                WorkoutTemplateEntry(exercise: row, supersetGroupID: group),
                WorkoutTemplateEntry(exercise: curl, supersetGroupID: group),
            ],
            syncOwnerTokenIdentifier: owner
        )
        context.insert(template)

        let session = try ActiveWorkoutEngine().startWorkout(fromTemplate: template, ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(session.title, "Upper Day")
        XCTAssertEqual(session.source, .template)
        XCTAssertNil(session.sourceSessionID)
        XCTAssertEqual(session.status, .active)
        let exercises = session.sortedLoggedExercises
        XCTAssertEqual(exercises.map(\.exerciseSnapshotName), ["Bench Press", "Row", "Curl"])
        XCTAssertEqual(exercises.map { $0.exercise?.id }, [bench.id, row.id, curl.id])
        XCTAssertNil(exercises[0].supersetGroupID)
        XCTAssertNotNil(exercises[1].supersetGroupID)
        XCTAssertEqual(exercises[1].supersetGroupID, exercises[2].supersetGroupID)
        XCTAssertNotEqual(exercises[1].supersetGroupID, group, "the workout gets its own group id")
        XCTAssertEqual(exercises.map { $0.sortedSets.map(\.kind) }, Array(repeating: [.working], count: 3))
        XCTAssertEqual(template.entries[1].supersetGroupID, group, "starting never changes the template")
    }

    func testStartingFromATemplateUsesSetKindsFromHistory() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bench = makeExercise("Bench Press", owner: owner)
        context.insert(bench)
        let past = WorkoutSession(
            title: "Old Push", startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100, status: .completed, source: .blank, syncOwnerTokenIdentifier: owner
        )
        let pastExercise = LoggedExercise(orderIndex: 0, exercise: bench)
        pastExercise.session = past
        past.loggedExercises.append(pastExercise)
        context.insert(past)
        context.insert(pastExercise)
        for (index, kind) in [SetKind.warmup, .working, .working].enumerated() {
            let set = LoggedSet(orderIndex: index, weight: 100, reps: 5, kind: kind, isCompleted: true)
            set.loggedExercise = pastExercise
            pastExercise.sets.append(set)
            context.insert(set)
        }
        let template = WorkoutTemplate(name: "Push", entries: [WorkoutTemplateEntry(exercise: bench)], syncOwnerTokenIdentifier: owner)
        context.insert(template)

        let session = try ActiveWorkoutEngine().startWorkout(fromTemplate: template, ownerTokenIdentifier: owner, context: context)

        let sets = try XCTUnwrap(session.sortedLoggedExercises.first?.sortedSets)
        XCTAssertEqual(sets.map(\.kind), [.warmup, .working, .working])
        XCTAssertTrue(sets.allSatisfy { $0.weight == nil && $0.reps == nil && !$0.isCompleted })
    }

    func testAnEntryWhoseExerciseIsGoneKeepsItsName() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(
            name: "Legs",
            entries: [WorkoutTemplateEntry(
                exerciseID: UUID(),
                exerciseSnapshotName: "Hack Squat",
                exerciseSnapshotEquipmentRaw: ExerciseEquipment.machine.rawValue,
                exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.quads.rawValue
            )],
            syncOwnerTokenIdentifier: owner
        )
        context.insert(template)

        let session = try ActiveWorkoutEngine().startWorkout(fromTemplate: template, ownerTokenIdentifier: owner, context: context)

        let exercise = try XCTUnwrap(session.sortedLoggedExercises.first)
        XCTAssertNil(exercise.exercise)
        XCTAssertEqual(exercise.exerciseSnapshotName, "Hack Squat")
        XCTAssertEqual(exercise.exerciseSnapshotEquipmentRaw, ExerciseEquipment.machine.rawValue)
        XCTAssertEqual(exercise.sortedSets.map(\.kind), [.working])
    }

    func testDeletedOrOtherOwnersTemplatesCannotStart() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let deleted = WorkoutTemplate(name: "Old", syncOwnerTokenIdentifier: owner, deletedAt: .now)
        let theirs = WorkoutTemplate(name: "Theirs", syncOwnerTokenIdentifier: "issuer|owner_b")
        context.insert(deleted)
        context.insert(theirs)
        let engine = ActiveWorkoutEngine()

        for template in [deleted, theirs] {
            XCTAssertThrowsError(try engine.startWorkout(fromTemplate: template, ownerTokenIdentifier: owner, context: context)) {
                XCTAssertEqual($0 as? ActiveWorkoutEngineError, .templateUnavailable)
            }
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
    }

    // MARK: - Helpers

    private func makeExercise(_ name: String, owner: String?, seedIdentifier: String? = nil) -> Exercise {
        Exercise(
            seedIdentifier: seedIdentifier,
            name: name,
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: seedIdentifier != nil,
            syncOwnerTokenIdentifier: owner
        )
    }

    private func deleteOutbox(_ context: ModelContext) throws {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>()).forEach(context.delete)
        try context.save()
    }

    private func entryPayload(id: UUID, exerciseID: UUID?, name: String, group: UUID? = nil) -> WorkoutTemplateEntrySyncPayload {
        WorkoutTemplateEntrySyncPayload(
            id: id.uuidString.lowercased(),
            exerciseClientId: exerciseID?.uuidString.lowercased(),
            exerciseSnapshotName: name,
            exerciseSnapshotEquipmentRaw: "barbell",
            exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
            supersetGroupID: group?.uuidString.lowercased()
        )
    }

    private func record(
        id: UUID, name: String, updatedAt: Double, deletedAt: Double? = nil,
        serverUpdatedAt: Double, entries: [WorkoutTemplateEntrySyncPayload]
    ) -> WorkoutTemplateSyncRecord {
        WorkoutTemplateSyncRecord(
            clientId: id.uuidString.lowercased(), createdAt: 10, updatedAt: updatedAt,
            deletedAt: deletedAt, serverUpdatedAt: serverUpdatedAt, name: name, entries: entries
        )
    }

    private func response(templates: [WorkoutTemplateSyncRecord]) -> SyncFetchChangesResponse {
        SyncFetchChangesResponse(
            userSettings: [],
            exercises: [],
            workoutSessions: [],
            loggedExercises: [],
            loggedSets: [],
            workoutTemplates: templates,
            cursors: SyncChangeCursors(
                userSettings: 0, exercises: 0,
                workoutTemplates: templates.map(\.serverUpdatedAt).max() ?? 0
            ),
            hasMore: SyncHasMore(userSettings: false, exercises: false, workoutTemplates: false)
        )
    }
}
