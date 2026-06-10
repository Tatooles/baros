# Workout Graph Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync completed workout sessions, logged exercises, and logged sets through the existing outbox and Convex sync pipeline while keeping active workouts local-only.

**Architecture:** Rename the settings/exercise-specific sync types to generic sync names, then extend the existing per-entity sync coordinator rather than adding a parallel workout coordinator. Workout graph sync uses stable client UUIDs, dependency-ordered pushes and pulls, per-table cursors, remote-first bootstrap, and tombstones for completed workout deletion.

**Tech Stack:** Swift 6, SwiftData, XCTest, XCUITest, Convex, ConvexMobile, TypeScript, Vitest, `convex-test`, `pnpm`.

---

## File Structure

- Rename `LiftingLog/Core/Sync/SettingsExerciseSyncCoordinator.swift` to `LiftingLog/Core/Sync/SyncCoordinator.swift`.
  - Responsibility: orchestration for bootstrap, owner claiming, outbox push, remote pull, cursor persistence, retry state, and conflict application for all v1 synced entities.
- Rename `LiftingLog/Core/Sync/SettingsExerciseSyncClient.swift` to `LiftingLog/Core/Sync/SyncClient.swift`.
  - Responsibility: protocol boundary for all Convex sync operations used by the coordinator.
- Rename `LiftingLog/Core/Sync/ConvexSettingsExerciseSyncClient.swift` to `LiftingLog/Core/Sync/ConvexSyncClient.swift`.
  - Responsibility: ConvexMobile adapter and argument mapper for sync API calls.
- Modify `LiftingLog/Core/Sync/SyncPayloads.swift`.
  - Responsibility: Codable payload and remote record types plus SwiftData-to-payload mapping.
- Modify `LiftingLog/Core/Sync/SyncCursorState.swift`.
  - Responsibility: persistent per-owner sync cursors and bootstrap flags.
- Modify `LiftingLog/Core/Sync/SyncOutboxRecorder.swift`.
  - Responsibility: local sync intent coalescing, including workout graph create/delete behavior.
- Modify `LiftingLog/Core/Sync/SyncScheduler.swift`.
  - Responsibility: use renamed `SyncCoordinator` and keep bootstrap-sensitive seed behavior.
- Modify `LiftingLog/App/LiftingLogApp.swift`.
  - Responsibility: construct renamed sync client/coordinator.
- Modify `LiftingLog/Features/Workout/ActiveWorkoutEngine.swift`.
  - Responsibility: ensure only visible completed graph records get finish-time create intent.
- Modify `LiftingLog/Features/History/WorkoutHistoryDetailView.swift`.
  - Responsibility: request sync after completed workout deletion if a scheduler is present.
- Rename `LiftingLogTests/SettingsExerciseSyncCoordinatorTests.swift` to `LiftingLogTests/SyncCoordinatorTests.swift`.
  - Responsibility: coordinator tests and `FakeSyncClient`.
- Modify `LiftingLogTests/SyncPayloadMappingTests.swift`.
  - Responsibility: payload mapper unit tests.
- Modify `LiftingLogTests/ConvexSyncArgumentMapperTests.swift`.
  - Responsibility: Convex argument mapper unit tests.
- Modify `LiftingLogTests/SyncCursorStateTests.swift`.
  - Responsibility: cursor state defaults and persistence tests.
- Modify `LiftingLogTests/SyncOutboxRecorderTests.swift` and `LiftingLogTests/SyncOutboxIntegrationTests.swift`.
  - Responsibility: outbox coalescing and local mutation intent tests.
- Modify `LiftingLogUITests/LiftingLogUITests.swift`.
  - Responsibility: local finish-to-history and delete-from-history UI coverage.
- Modify `convex/sync.test.ts`.
  - Responsibility: backend workout graph API, cursors, tombstones, and owner isolation tests.
- Modify `LiftingLog.xcodeproj/project.pbxproj`.
  - Responsibility: Xcode file references after Swift file/test rename.

## Verification Commands

Use these commands throughout the plan:

```bash
pnpm run convex:test
pnpm run convex:typecheck
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17'
```

If the simulator name is unavailable locally, list destinations with:

```bash
xcodebuild -scheme LiftingLog -showdestinations
```

Then rerun the same test command with an available iPhone simulator destination.

---

### Task 1: Mechanical Sync Type Rename

**Files:**
- Rename: `LiftingLog/Core/Sync/SettingsExerciseSyncCoordinator.swift` -> `LiftingLog/Core/Sync/SyncCoordinator.swift`
- Rename: `LiftingLog/Core/Sync/SettingsExerciseSyncClient.swift` -> `LiftingLog/Core/Sync/SyncClient.swift`
- Rename: `LiftingLog/Core/Sync/ConvexSettingsExerciseSyncClient.swift` -> `LiftingLog/Core/Sync/ConvexSyncClient.swift`
- Rename: `LiftingLogTests/SettingsExerciseSyncCoordinatorTests.swift` -> `LiftingLogTests/SyncCoordinatorTests.swift`
- Modify: `LiftingLog.xcodeproj/project.pbxproj`
- Modify: `LiftingLog/App/LiftingLogApp.swift`
- Modify: `LiftingLog/Core/Sync/SyncScheduler.swift`
- Modify: `LiftingLogTests/SyncOutboxIntegrationTests.swift`

- [ ] **Step 1: Rename files on disk**

Run:

```bash
git mv LiftingLog/Core/Sync/SettingsExerciseSyncCoordinator.swift LiftingLog/Core/Sync/SyncCoordinator.swift
git mv LiftingLog/Core/Sync/SettingsExerciseSyncClient.swift LiftingLog/Core/Sync/SyncClient.swift
git mv LiftingLog/Core/Sync/ConvexSettingsExerciseSyncClient.swift LiftingLog/Core/Sync/ConvexSyncClient.swift
git mv LiftingLogTests/SettingsExerciseSyncCoordinatorTests.swift LiftingLogTests/SyncCoordinatorTests.swift
```

Expected: files are renamed and `git status --short` shows four renames or delete/add pairs.

- [ ] **Step 2: Replace type names**

Apply these global substitutions in Swift files and `project.pbxproj`:

```text
SettingsExerciseSyncCoordinator -> SyncCoordinator
SettingsExerciseSyncClient -> SyncClient
ConvexSettingsExerciseSyncClient -> ConvexSyncClient
FakeSettingsExerciseSyncClient -> FakeSyncClient
SettingsExerciseSyncCoordinatorTests -> SyncCoordinatorTests
SettingsExerciseSyncCoordinatorError -> SyncCoordinatorError
ConvexSettingsExerciseSyncClientError -> ConvexSyncClientError
```

Expected concrete examples:

```swift
final class SyncCoordinator {
    private let client: any SyncClient & Sendable
}
```

```swift
protocol SyncClient {
    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult
    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult
    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult
    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse
}
```

```swift
struct ConvexSyncClient: SyncClient, @unchecked Sendable {
    private let client: ConvexClientWithAuth<String>
}
```

- [ ] **Step 3: Update app construction**

In `LiftingLog/App/LiftingLogApp.swift`, update `configureSyncIfNeeded()` to use renamed types:

```swift
private func configureSyncIfNeeded() {
    guard syncAuthTask == nil else { return }

    let syncClient = ConvexSyncClient(client: convexClient)
    let coordinator = SyncCoordinator(client: syncClient)
    syncScheduler.configure(coordinator: coordinator, modelContext: modelContainer.mainContext)

    syncAuthTask = Task { @MainActor in
        for await state in convexClient.authState.values {
            switch state {
            case .loading:
                break
            case .unauthenticated:
                syncScheduler.currentOwnerTokenIdentifier = nil
                syncScheduler.seedDefaultsForLocalMode()
            case .authenticated:
                syncScheduler.currentOwnerTokenIdentifier = await resolveOwnerTokenIdentifier()
                syncScheduler.seedDefaultsForCurrentOwner()
                syncScheduler.requestSync()
            }
        }
    }
}
```

- [ ] **Step 4: Update scheduler type signatures**

In `LiftingLog/Core/Sync/SyncScheduler.swift`, update stored properties and methods:

```swift
private var coordinator: SyncCoordinator?

init(coordinator: SyncCoordinator? = nil, modelContext: ModelContext? = nil) {
    self.coordinator = coordinator
    self.modelContext = modelContext
}

func configure(coordinator: SyncCoordinator, modelContext: ModelContext) {
    self.coordinator = coordinator
    self.modelContext = modelContext
}

private func startSyncTask(coordinator: SyncCoordinator, modelContext: ModelContext) {
    syncTask = Task { @MainActor in
        while true {
            needsSync = false
            do {
                try await coordinator.run(ownerTokenIdentifier: currentOwnerTokenIdentifier, context: modelContext)
            } catch is CancellationError {
                break
            } catch {
                break
            }
            if Task.isCancelled {
                break
            }
            guard needsSync else { break }
        }

        let shouldStartQueuedSync = needsSync && currentOwnerTokenIdentifier != nil
        needsSync = false
        syncTask = nil
        if shouldStartQueuedSync {
            startSyncTask(coordinator: coordinator, modelContext: modelContext)
        }
    }
}
```

- [ ] **Step 5: Verify no stale names remain outside the design spec**

Run:

```bash
rg -n "SettingsExerciseSync|ConvexSettingsExerciseSync|FakeSettingsExerciseSync" LiftingLog LiftingLogTests LiftingLog.xcodeproj
```

Expected: no matches.

- [ ] **Step 6: Build/test the mechanical rename**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCursorStateTests
```

Expected: test target builds and selected tests pass. If destination is unavailable, use an available simulator from `xcodebuild -scheme LiftingLog -showdestinations`.

- [ ] **Step 7: Commit the rename**

Run:

```bash
git add LiftingLog/Core/Sync/SyncCoordinator.swift LiftingLog/Core/Sync/SyncClient.swift LiftingLog/Core/Sync/ConvexSyncClient.swift LiftingLogTests/SyncCoordinatorTests.swift LiftingLog.xcodeproj/project.pbxproj LiftingLog/App/LiftingLogApp.swift LiftingLog/Core/Sync/SyncScheduler.swift LiftingLogTests/SyncOutboxIntegrationTests.swift
git commit -m "Rename sync coordinator types"
```

Expected: commit succeeds.

---

### Task 2: Add Workout Payloads, Records, and Argument Mapping

**Files:**
- Modify: `LiftingLog/Core/Sync/SyncPayloads.swift`
- Modify: `LiftingLog/Core/Sync/ConvexSyncClient.swift`
- Modify: `LiftingLogTests/SyncPayloadMappingTests.swift`
- Modify: `LiftingLogTests/ConvexSyncArgumentMapperTests.swift`

- [ ] **Step 1: Add failing payload mapper tests**

Append tests to `LiftingLogTests/SyncPayloadMappingTests.swift`:

```swift
func testWorkoutSessionPayloadMapsCompletedSessionFields() throws {
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000004001")!
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000004099")!
    let healthID = UUID(uuidString: "00000000-0000-0000-0000-000000004098")!
    let session = WorkoutSession(
        id: sessionID,
        title: "Push Day",
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 220),
        durationSeconds: 120,
        notes: "Felt strong",
        status: .completed,
        source: .pastWorkout,
        sourceSessionID: sourceID,
        referenceNotes: "Repeat this",
        createdAt: Date(timeIntervalSince1970: 90),
        updatedAt: Date(timeIntervalSince1970: 230),
        deletedAt: nil,
        healthLinkID: healthID
    )

    let payload = SyncPayloadMapper.workoutSessionPayload(from: session)

    XCTAssertEqual(payload.clientId, sessionID.uuidString.lowercased())
    XCTAssertEqual(payload.title, "Push Day")
    XCTAssertEqual(payload.startedAt, 100)
    XCTAssertEqual(payload.endedAt, 220)
    XCTAssertEqual(payload.durationSeconds, 120)
    XCTAssertEqual(payload.notes, "Felt strong")
    XCTAssertEqual(payload.referenceNotes, "Repeat this")
    XCTAssertEqual(payload.statusRaw, "completed")
    XCTAssertEqual(payload.sourceRaw, "pastWorkout")
    XCTAssertEqual(payload.sourceSessionID, sourceID.uuidString.lowercased())
    XCTAssertEqual(payload.healthLinkID, healthID.uuidString.lowercased())
    XCTAssertEqual(payload.createdAt, 90)
    XCTAssertEqual(payload.updatedAt, 230)
    XCTAssertNil(payload.deletedAt)
}

func testLoggedExercisePayloadMapsParentAndSnapshotFields() throws {
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000004101")!
    let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000004102")!
    let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000004103")!
    let exercise = Exercise(
        id: exerciseID,
        name: "Bench Press",
        category: .strength,
        equipment: .barbell,
        primaryMuscleGroup: .chest
    )
    let session = WorkoutSession(title: "Push", startedAt: Date(timeIntervalSince1970: 50), status: .completed, source: .blank)
    session.id = sessionID
    let loggedExercise = LoggedExercise(
        id: loggedExerciseID,
        orderIndex: 2,
        exercise: exercise,
        exerciseSnapshotName: "Snapshot Bench",
        exerciseSnapshotEquipmentRaw: "smithMachine",
        exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
        notes: "Paused",
        referenceNotes: "Old notes",
        createdAt: Date(timeIntervalSince1970: 60),
        updatedAt: Date(timeIntervalSince1970: 70),
        deletedAt: Date(timeIntervalSince1970: 80)
    )
    loggedExercise.session = session

    let payload = SyncPayloadMapper.loggedExercisePayload(from: loggedExercise)

    XCTAssertEqual(payload.clientId, loggedExerciseID.uuidString.lowercased())
    XCTAssertEqual(payload.sessionClientId, sessionID.uuidString.lowercased())
    XCTAssertEqual(payload.exerciseClientId, exerciseID.uuidString.lowercased())
    XCTAssertEqual(payload.orderIndex, 2)
    XCTAssertEqual(payload.exerciseSnapshotName, "Snapshot Bench")
    XCTAssertEqual(payload.exerciseSnapshotEquipmentRaw, "smithMachine")
    XCTAssertEqual(payload.exerciseSnapshotPrimaryMuscleGroupRaw, "chest")
    XCTAssertTrue(payload.hasSnapshotMetadata)
    XCTAssertEqual(payload.notes, "Paused")
    XCTAssertEqual(payload.referenceNotes, "Old notes")
    XCTAssertEqual(payload.createdAt, 60)
    XCTAssertEqual(payload.updatedAt, 70)
    XCTAssertEqual(payload.deletedAt, 80)
}

func testLoggedSetPayloadMapsParentAndLiftFields() throws {
    let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000004201")!
    let setID = UUID(uuidString: "00000000-0000-0000-0000-000000004202")!
    let healthID = UUID(uuidString: "00000000-0000-0000-0000-000000004203")!
    let loggedExercise = LoggedExercise(id: loggedExerciseID, orderIndex: 0)
    let set = LoggedSet(
        id: setID,
        orderIndex: 3,
        weight: 185,
        reps: 5,
        rpe: 8.5,
        placeholderWeight: 175,
        placeholderReps: 6,
        placeholderRPE: 7.5,
        kind: .working,
        isCompleted: true,
        completedAt: Date(timeIntervalSince1970: 125),
        notes: "Solid",
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 130),
        deletedAt: nil,
        healthLinkID: healthID
    )
    set.loggedExercise = loggedExercise

    let payload = SyncPayloadMapper.loggedSetPayload(from: set)

    XCTAssertEqual(payload.clientId, setID.uuidString.lowercased())
    XCTAssertEqual(payload.loggedExerciseClientId, loggedExerciseID.uuidString.lowercased())
    XCTAssertEqual(payload.orderIndex, 3)
    XCTAssertEqual(payload.weight, 185)
    XCTAssertEqual(payload.reps, 5)
    XCTAssertEqual(payload.rpe, 8.5)
    XCTAssertEqual(payload.placeholderWeight, 175)
    XCTAssertEqual(payload.placeholderReps, 6)
    XCTAssertEqual(payload.placeholderRPE, 7.5)
    XCTAssertEqual(payload.kindRaw, "working")
    XCTAssertTrue(payload.isCompleted)
    XCTAssertEqual(payload.completedAt, 125)
    XCTAssertEqual(payload.notes, "Solid")
    XCTAssertEqual(payload.healthLinkID, healthID.uuidString.lowercased())
    XCTAssertEqual(payload.createdAt, 100)
    XCTAssertEqual(payload.updatedAt, 130)
    XCTAssertNil(payload.deletedAt)
}
```

- [ ] **Step 2: Run mapper tests and verify they fail**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncPayloadMappingTests
```

Expected: fail with missing `WorkoutSessionSyncPayload`, `LoggedExerciseSyncPayload`, `LoggedSetSyncPayload`, or mapper methods.

- [ ] **Step 3: Add payload and record types**

In `LiftingLog/Core/Sync/SyncPayloads.swift`, add:

```swift
struct WorkoutSessionSyncPayload: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let title: String
    let startedAt: Double
    let endedAt: Double?
    let durationSeconds: Int
    let notes: String
    let referenceNotes: String?
    let statusRaw: String
    let sourceRaw: String
    let sourceSessionID: String?
    let healthLinkID: String?
}

struct LoggedExerciseSyncPayload: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let sessionClientId: String
    let exerciseClientId: String?
    let orderIndex: Int
    let exerciseSnapshotName: String
    let exerciseSnapshotEquipmentRaw: String
    let exerciseSnapshotPrimaryMuscleGroupRaw: String
    let hasSnapshotMetadata: Bool
    let notes: String
    let referenceNotes: String?
}

struct LoggedSetSyncPayload: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let loggedExerciseClientId: String
    let orderIndex: Int
    let weight: Double?
    let reps: Int?
    let rpe: Double?
    let placeholderWeight: Double?
    let placeholderReps: Int?
    let placeholderRPE: Double?
    let kindRaw: String
    let isCompleted: Bool
    let completedAt: Double?
    let notes: String
    let healthLinkID: String?
}

struct WorkoutSessionSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let title: String
    let startedAt: Double
    let endedAt: Double?
    let durationSeconds: Int
    let notes: String
    let referenceNotes: String?
    let statusRaw: String
    let sourceRaw: String
    let sourceSessionID: String?
    let healthLinkID: String?
}

struct LoggedExerciseSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let sessionClientId: String
    let exerciseClientId: String?
    let orderIndex: Int
    let exerciseSnapshotName: String
    let exerciseSnapshotEquipmentRaw: String
    let exerciseSnapshotPrimaryMuscleGroupRaw: String
    let hasSnapshotMetadata: Bool
    let notes: String
    let referenceNotes: String?
}

struct LoggedSetSyncRecord: Codable, Equatable {
    let clientId: String
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
    let serverUpdatedAt: Double
    let loggedExerciseClientId: String
    let orderIndex: Int
    let weight: Double?
    let reps: Int?
    let rpe: Double?
    let placeholderWeight: Double?
    let placeholderReps: Int?
    let placeholderRPE: Double?
    let kindRaw: String
    let isCompleted: Bool
    let completedAt: Double?
    let notes: String
    let healthLinkID: String?
}
```

Update `SyncFetchChangesResponse`:

```swift
struct SyncFetchChangesResponse: Codable, Equatable {
    let userSettings: [UserSettingsSyncRecord]
    let exercises: [ExerciseSyncRecord]
    let workoutSessions: [WorkoutSessionSyncRecord]
    let loggedExercises: [LoggedExerciseSyncRecord]
    let loggedSets: [LoggedSetSyncRecord]
    let cursors: SyncChangeCursors
    let hasMore: SyncHasMore
}
```

- [ ] **Step 4: Add mapper methods**

In `SyncPayloadMapper`, add:

```swift
static func workoutSessionPayload(from session: WorkoutSession) -> WorkoutSessionSyncPayload {
    WorkoutSessionSyncPayload(
        clientId: session.id.uuidString.lowercased(),
        createdAt: session.createdAt.timeIntervalSince1970,
        updatedAt: session.updatedAt.timeIntervalSince1970,
        deletedAt: session.deletedAt?.timeIntervalSince1970,
        title: session.title,
        startedAt: session.startedAt.timeIntervalSince1970,
        endedAt: session.endedAt?.timeIntervalSince1970,
        durationSeconds: session.durationSeconds,
        notes: session.notes,
        referenceNotes: session.referenceNotes,
        statusRaw: session.statusRaw,
        sourceRaw: session.sourceRaw,
        sourceSessionID: session.sourceSessionID?.uuidString.lowercased(),
        healthLinkID: session.healthLinkID?.uuidString.lowercased()
    )
}

static func loggedExercisePayload(from loggedExercise: LoggedExercise) -> LoggedExerciseSyncPayload {
    LoggedExerciseSyncPayload(
        clientId: loggedExercise.id.uuidString.lowercased(),
        createdAt: loggedExercise.createdAt.timeIntervalSince1970,
        updatedAt: loggedExercise.updatedAt.timeIntervalSince1970,
        deletedAt: loggedExercise.deletedAt?.timeIntervalSince1970,
        sessionClientId: loggedExercise.session?.id.uuidString.lowercased() ?? "",
        exerciseClientId: loggedExercise.exercise?.id.uuidString.lowercased(),
        orderIndex: loggedExercise.orderIndex,
        exerciseSnapshotName: loggedExercise.exerciseSnapshotName,
        exerciseSnapshotEquipmentRaw: loggedExercise.effectiveSnapshotEquipmentRaw,
        exerciseSnapshotPrimaryMuscleGroupRaw: loggedExercise.effectiveSnapshotPrimaryMuscleGroupRaw,
        hasSnapshotMetadata: loggedExercise.hasSnapshotMetadata,
        notes: loggedExercise.notes,
        referenceNotes: loggedExercise.referenceNotes
    )
}

static func loggedSetPayload(from set: LoggedSet) -> LoggedSetSyncPayload {
    LoggedSetSyncPayload(
        clientId: set.id.uuidString.lowercased(),
        createdAt: set.createdAt.timeIntervalSince1970,
        updatedAt: set.updatedAt.timeIntervalSince1970,
        deletedAt: set.deletedAt?.timeIntervalSince1970,
        loggedExerciseClientId: set.loggedExercise?.id.uuidString.lowercased() ?? "",
        orderIndex: set.orderIndex,
        weight: set.weight,
        reps: set.reps,
        rpe: set.rpe,
        placeholderWeight: set.placeholderWeight,
        placeholderReps: set.placeholderReps,
        placeholderRPE: set.placeholderRPE,
        kindRaw: set.kindRaw,
        isCompleted: set.isCompleted,
        completedAt: set.completedAt?.timeIntervalSince1970,
        notes: set.notes,
        healthLinkID: set.healthLinkID?.uuidString.lowercased()
    )
}
```

- [ ] **Step 5: Add failing Convex argument mapper tests**

Append to `LiftingLogTests/ConvexSyncArgumentMapperTests.swift`:

```swift
func testWorkoutSessionArgsEncodeIntegersAsDoubleAndUUIDsAsStrings() throws {
    let payload = WorkoutSessionSyncPayload(
        clientId: "session-1",
        createdAt: 1,
        updatedAt: 2,
        deletedAt: nil,
        title: "Push",
        startedAt: 3,
        endedAt: 4,
        durationSeconds: 60,
        notes: "",
        referenceNotes: nil,
        statusRaw: "completed",
        sourceRaw: "pastWorkout",
        sourceSessionID: "source-1",
        healthLinkID: nil
    )

    let record = ConvexSyncArgumentMapper.workoutSessionRecord(payload)

    XCTAssertEqual(try XCTUnwrap(record["durationSeconds"] as? Double), 60)
    XCTAssertEqual(try XCTUnwrap(record["sourceSessionID"] as? String), "source-1")
    XCTAssertNil(record["healthLinkID"]!)
}

func testLoggedExerciseArgsEncodeOrderIndexAsDouble() throws {
    let payload = LoggedExerciseSyncPayload(
        clientId: "logged-exercise-1",
        createdAt: 1,
        updatedAt: 2,
        deletedAt: nil,
        sessionClientId: "session-1",
        exerciseClientId: "exercise-1",
        orderIndex: 7,
        exerciseSnapshotName: "Bench",
        exerciseSnapshotEquipmentRaw: "barbell",
        exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
        hasSnapshotMetadata: true,
        notes: "",
        referenceNotes: nil
    )

    let record = ConvexSyncArgumentMapper.loggedExerciseRecord(payload)

    XCTAssertEqual(try XCTUnwrap(record["orderIndex"] as? Double), 7)
    XCTAssertEqual(try XCTUnwrap(record["sessionClientId"] as? String), "session-1")
}

func testLoggedSetArgsEncodeNullableAndIntegerFields() throws {
    let payload = LoggedSetSyncPayload(
        clientId: "set-1",
        createdAt: 1,
        updatedAt: 2,
        deletedAt: nil,
        loggedExerciseClientId: "logged-exercise-1",
        orderIndex: 1,
        weight: 185,
        reps: 5,
        rpe: nil,
        placeholderWeight: nil,
        placeholderReps: 8,
        placeholderRPE: nil,
        kindRaw: "working",
        isCompleted: true,
        completedAt: 3,
        notes: "",
        healthLinkID: nil
    )

    let record = ConvexSyncArgumentMapper.loggedSetRecord(payload)

    XCTAssertEqual(try XCTUnwrap(record["orderIndex"] as? Double), 1)
    XCTAssertEqual(try XCTUnwrap(record["reps"] as? Double), 5)
    XCTAssertNil(record["rpe"]!)
    XCTAssertNil(record["healthLinkID"]!)
}
```

- [ ] **Step 6: Implement argument mapping and client protocol methods**

In `SyncClient`, add:

```swift
func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult
func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult
func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult
```

In `ConvexSyncClient`, add:

```swift
func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult {
    try await client.mutation(
        "sync:upsertWorkoutSession",
        with: ConvexSyncArgumentMapper.upsertWorkoutSessionArgs(record)
    )
}

func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult {
    try await client.mutation(
        "sync:upsertLoggedExercise",
        with: ConvexSyncArgumentMapper.upsertLoggedExerciseArgs(record)
    )
}

func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult {
    try await client.mutation(
        "sync:upsertLoggedSet",
        with: ConvexSyncArgumentMapper.upsertLoggedSetArgs(record)
    )
}
```

Change the fetch subscription target:

```swift
let publisher = client.subscribe(
    to: "sync:fetchChanges",
    with: ConvexSyncArgumentMapper.fetchChangesArgs(cursors: cursors, limit: limit),
    yielding: SyncFetchChangesResponse.self
)
```

Add mapper helpers:

```swift
static func upsertWorkoutSessionArgs(_ record: WorkoutSessionSyncPayload) -> [String: ConvexEncodable?] {
    ["record": workoutSessionRecord(record)]
}

static func upsertLoggedExerciseArgs(_ record: LoggedExerciseSyncPayload) -> [String: ConvexEncodable?] {
    ["record": loggedExerciseRecord(record)]
}

static func upsertLoggedSetArgs(_ record: LoggedSetSyncPayload) -> [String: ConvexEncodable?] {
    ["record": loggedSetRecord(record)]
}

static func workoutSessionRecord(_ record: WorkoutSessionSyncPayload) -> [String: ConvexEncodable?] {
    [
        "clientId": record.clientId,
        "createdAt": record.createdAt,
        "updatedAt": record.updatedAt,
        "deletedAt": record.deletedAt,
        "title": record.title,
        "startedAt": record.startedAt,
        "endedAt": record.endedAt,
        "durationSeconds": Double(record.durationSeconds),
        "notes": record.notes,
        "referenceNotes": record.referenceNotes,
        "statusRaw": record.statusRaw,
        "sourceRaw": record.sourceRaw,
        "sourceSessionID": record.sourceSessionID,
        "healthLinkID": record.healthLinkID,
    ]
}

static func loggedExerciseRecord(_ record: LoggedExerciseSyncPayload) -> [String: ConvexEncodable?] {
    [
        "clientId": record.clientId,
        "createdAt": record.createdAt,
        "updatedAt": record.updatedAt,
        "deletedAt": record.deletedAt,
        "sessionClientId": record.sessionClientId,
        "exerciseClientId": record.exerciseClientId,
        "orderIndex": Double(record.orderIndex),
        "exerciseSnapshotName": record.exerciseSnapshotName,
        "exerciseSnapshotEquipmentRaw": record.exerciseSnapshotEquipmentRaw,
        "exerciseSnapshotPrimaryMuscleGroupRaw": record.exerciseSnapshotPrimaryMuscleGroupRaw,
        "hasSnapshotMetadata": record.hasSnapshotMetadata,
        "notes": record.notes,
        "referenceNotes": record.referenceNotes,
    ]
}

static func loggedSetRecord(_ record: LoggedSetSyncPayload) -> [String: ConvexEncodable?] {
    [
        "clientId": record.clientId,
        "createdAt": record.createdAt,
        "updatedAt": record.updatedAt,
        "deletedAt": record.deletedAt,
        "loggedExerciseClientId": record.loggedExerciseClientId,
        "orderIndex": Double(record.orderIndex),
        "weight": record.weight,
        "reps": record.reps.map(Double.init),
        "rpe": record.rpe,
        "placeholderWeight": record.placeholderWeight,
        "placeholderReps": record.placeholderReps.map(Double.init),
        "placeholderRPE": record.placeholderRPE,
        "kindRaw": record.kindRaw,
        "isCompleted": record.isCompleted,
        "completedAt": record.completedAt,
        "notes": record.notes,
        "healthLinkID": record.healthLinkID,
    ]
}
```

- [ ] **Step 7: Update fake client to compile**

In `SyncCoordinatorTests.swift`, extend `FakeSyncClient`:

```swift
var upsertedWorkoutSessions: [WorkoutSessionSyncPayload] = []
var upsertedLoggedExercises: [LoggedExerciseSyncPayload] = []
var upsertedLoggedSets: [LoggedSetSyncPayload] = []
var workoutSessionMutationResults: [SyncMutationResult] = []
var loggedExerciseMutationResults: [SyncMutationResult] = []
var loggedSetMutationResults: [SyncMutationResult] = []

func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult {
    if let error { throw error }
    upsertedWorkoutSessions.append(record)
    if !workoutSessionMutationResults.isEmpty {
        return workoutSessionMutationResults.removeFirst()
    }
    return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
}

func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult {
    if let error { throw error }
    upsertedLoggedExercises.append(record)
    if !loggedExerciseMutationResults.isEmpty {
        return loggedExerciseMutationResults.removeFirst()
    }
    return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
}

func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult {
    if let error { throw error }
    upsertedLoggedSets.append(record)
    if !loggedSetMutationResults.isEmpty {
        return loggedSetMutationResults.removeFirst()
    }
    return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
}
```

Update default `SyncFetchChangesResponse` initializers in tests to include empty workout arrays:

```swift
SyncFetchChangesResponse(
    userSettings: [],
    exercises: [],
    workoutSessions: [],
    loggedExercises: [],
    loggedSets: [],
    cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
    hasMore: SyncHasMore(userSettings: false, exercises: false)
)
```

- [ ] **Step 8: Run mapper tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncPayloadMappingTests -only-testing:LiftingLogTests/ConvexSyncArgumentMapperTests
```

Expected: tests pass.

- [ ] **Step 9: Commit payload work**

Run:

```bash
git add LiftingLog/Core/Sync/SyncPayloads.swift LiftingLog/Core/Sync/SyncClient.swift LiftingLog/Core/Sync/ConvexSyncClient.swift LiftingLogTests/SyncPayloadMappingTests.swift LiftingLogTests/ConvexSyncArgumentMapperTests.swift LiftingLogTests/SyncCoordinatorTests.swift
git commit -m "Add workout sync payload mapping"
```

Expected: commit succeeds.

---

### Task 3: Add Workout Cursor State

**Files:**
- Modify: `LiftingLog/Core/Sync/SyncCursorState.swift`
- Modify: `LiftingLogTests/SyncCursorStateTests.swift`
- Modify: `LiftingLogTests/SyncPayloadMappingTests.swift`

- [ ] **Step 1: Add failing cursor tests**

In `LiftingLogTests/SyncCursorStateTests.swift`, add:

```swift
func testWorkoutCursorDefaultsStartAtZeroAndBootstrapIsFalse() throws {
    let state = SyncCursorState(ownerTokenIdentifier: "issuer|owner_a")

    XCTAssertEqual(state.userSettingsCursor, 0)
    XCTAssertEqual(state.exercisesCursor, 0)
    XCTAssertEqual(state.workoutSessionsCursor, 0)
    XCTAssertEqual(state.loggedExercisesCursor, 0)
    XCTAssertEqual(state.loggedSetsCursor, 0)
    XCTAssertFalse(state.hasBootstrappedWorkoutGraph)
}

func testWorkoutCursorsPersistInSwiftData() throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let state = SyncCursorState(
        ownerTokenIdentifier: "issuer|owner_a",
        userSettingsCursor: 1,
        exercisesCursor: 2,
        workoutSessionsCursor: 3,
        loggedExercisesCursor: 4,
        loggedSetsCursor: 5,
        hasBootstrappedSettingsExercises: true,
        hasBootstrappedWorkoutGraph: true
    )
    context.insert(state)
    try context.save()

    let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)

    XCTAssertEqual(fetched.workoutSessionsCursor, 3)
    XCTAssertEqual(fetched.loggedExercisesCursor, 4)
    XCTAssertEqual(fetched.loggedSetsCursor, 5)
    XCTAssertTrue(fetched.hasBootstrappedWorkoutGraph)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCursorStateTests
```

Expected: fail because the workout cursor fields do not exist.

- [ ] **Step 3: Add cursor properties and initializer parameters**

Update `LiftingLog/Core/Sync/SyncCursorState.swift`:

```swift
@Model
final class SyncCursorState: Identifiable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique)
    var ownerTokenIdentifier: String
    var userSettingsCursor: Double
    var exercisesCursor: Double
    var workoutSessionsCursor: Double
    var loggedExercisesCursor: Double
    var loggedSetsCursor: Double
    var hasBootstrappedSettingsExercises: Bool = false
    var hasBootstrappedWorkoutGraph: Bool = false

    init(
        id: UUID = UUID(),
        ownerTokenIdentifier: String,
        userSettingsCursor: Double = 0,
        exercisesCursor: Double = 0,
        workoutSessionsCursor: Double = 0,
        loggedExercisesCursor: Double = 0,
        loggedSetsCursor: Double = 0,
        hasBootstrappedSettingsExercises: Bool = false,
        hasBootstrappedWorkoutGraph: Bool = false
    ) {
        self.id = id
        self.ownerTokenIdentifier = ownerTokenIdentifier
        self.userSettingsCursor = userSettingsCursor
        self.exercisesCursor = exercisesCursor
        self.workoutSessionsCursor = workoutSessionsCursor
        self.loggedExercisesCursor = loggedExercisesCursor
        self.loggedSetsCursor = loggedSetsCursor
        self.hasBootstrappedSettingsExercises = hasBootstrappedSettingsExercises
        self.hasBootstrappedWorkoutGraph = hasBootstrappedWorkoutGraph
    }
}
```

Keep the existing `state(for:context:)` method unchanged except for using the expanded initializer defaults.

- [ ] **Step 4: Update cursor DTO helper test**

In `SyncPayloadMappingTests`, replace `testFetchChangesRequestIncludesZeroWorkoutGraphCursors` with:

```swift
func testFetchChangesRequestCarriesWorkoutGraphCursors() throws {
    let cursors = SyncChangeCursors(
        userSettings: 10,
        exercises: 20,
        workoutSessions: 30,
        loggedExercises: 40,
        loggedSets: 50
    )

    XCTAssertEqual(cursors.userSettings, 10)
    XCTAssertEqual(cursors.exercises, 20)
    XCTAssertEqual(cursors.workoutSessions, 30)
    XCTAssertEqual(cursors.loggedExercises, 40)
    XCTAssertEqual(cursors.loggedSets, 50)
}
```

- [ ] **Step 5: Run cursor and payload tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCursorStateTests -only-testing:LiftingLogTests/SyncPayloadMappingTests
```

Expected: tests pass.

- [ ] **Step 6: Commit cursor state**

Run:

```bash
git add LiftingLog/Core/Sync/SyncCursorState.swift LiftingLogTests/SyncCursorStateTests.swift LiftingLogTests/SyncPayloadMappingTests.swift
git commit -m "Add workout sync cursors"
```

Expected: commit succeeds.

---

### Task 4: Harden Outbox Finish/Delete Behavior

**Files:**
- Modify: `LiftingLog/Core/Sync/SyncOutboxRecorder.swift`
- Modify: `LiftingLog/Features/Workout/ActiveWorkoutEngine.swift`
- Modify: `LiftingLog/Core/Domain/WorkoutHistoryMutationService.swift`
- Modify: `LiftingLog/Features/History/WorkoutHistoryDetailView.swift`
- Modify: `LiftingLogTests/SyncOutboxRecorderTests.swift`
- Modify: `LiftingLogTests/SyncOutboxIntegrationTests.swift`

- [ ] **Step 1: Add failing test for deleting a freshly finished workout before sync**

In `LiftingLogTests/SyncOutboxIntegrationTests.swift`, add:

```swift
func testDeletingUnattemptedFinishedWorkoutRemovesCreateIntentInsteadOfTombstoning() throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let exercise = Exercise(
        name: "Bench Press",
        category: .strength,
        equipment: .barbell,
        primaryMuscle: "Chest"
    )
    context.insert(exercise)
    try context.save()

    let engine = ActiveWorkoutEngine()
    let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
    let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
    let set = try XCTUnwrap(loggedExercise.sets.first)
    try engine.updateSet(set, weight: 185, reps: 5, rpe: 8, context: context)
    try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 200))

    XCTAssertEqual(try fetchEntries(context).count, 3)

    try WorkoutHistoryMutationService().deleteWorkoutHistory(
        session,
        context: context,
        now: Date(timeIntervalSince1970: 250)
    )

    XCTAssertTrue(session.isDeleted)
    XCTAssertTrue(try fetchEntries(context).isEmpty)
}
```

- [ ] **Step 2: Add failing test for attempted creates becoming tombstones**

In `SyncOutboxIntegrationTests.swift`, add:

```swift
func testDeletingAttemptedFinishedWorkoutKeepsGraphDeleteIntent() throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let exercise = Exercise(
        name: "Bench Press",
        category: .strength,
        equipment: .barbell,
        primaryMuscle: "Chest"
    )
    context.insert(exercise)
    try context.save()

    let engine = ActiveWorkoutEngine()
    let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
    let loggedExercise = try engine.addExercise(exercise, to: session, context: context)
    let set = try XCTUnwrap(loggedExercise.sets.first)
    try engine.finishWorkout(session, context: context, now: Date(timeIntervalSince1970: 200))

    let recorder = SyncOutboxRecorder()
    for entry in try fetchEntries(context) {
        recorder.markInFlight(entry, now: Date(timeIntervalSince1970: 225))
    }

    try WorkoutHistoryMutationService().deleteWorkoutHistory(
        session,
        context: context,
        now: Date(timeIntervalSince1970: 250)
    )

    let entries = try fetchEntries(context)
    XCTAssertEqual(entries.count, 3)
    assertEntry(entries, kind: .workoutSession, id: session.id, operation: .delete)
    assertEntry(entries, kind: .loggedExercise, id: loggedExercise.id, operation: .delete)
    assertEntry(entries, kind: .loggedSet, id: set.id, operation: .delete)
}
```

- [ ] **Step 3: Run tests and verify behavior**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncOutboxIntegrationTests/testDeletingUnattemptedFinishedWorkoutRemovesCreateIntentInsteadOfTombstoning -only-testing:LiftingLogTests/SyncOutboxIntegrationTests/testDeletingAttemptedFinishedWorkoutKeepsGraphDeleteIntent
```

Expected: first test may fail if graph delete creates tombstone entries after unattempted creates are removed; second should pass or identify coalescing gaps.

- [ ] **Step 4: Make delete service rely on recorder coalescing and request sync from UI**

Keep `WorkoutHistoryMutationService.deleteWorkoutHistory` service-level behavior focused on data mutation and outbox recording:

```swift
func deleteWorkoutHistory(
    _ session: WorkoutSession,
    ownerTokenIdentifier: String? = nil,
    context: ModelContext,
    now: Date = .now
) throws {
    session.markDeletedCascade(now: now)
    try recorder.recordDelete(
        entityKind: .workoutSession,
        entityID: session.id,
        ownerTokenIdentifier: ownerTokenIdentifier,
        context: context,
        now: now
    )

    for loggedExercise in session.loggedExercises {
        try recorder.recordDelete(
            entityKind: .loggedExercise,
            entityID: loggedExercise.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )

        for set in loggedExercise.sets {
            try recorder.recordDelete(
                entityKind: .loggedSet,
                entityID: set.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }
    }

    try context.save()
}
```

In `WorkoutHistoryDetailView`, add scheduler environment:

```swift
@Environment(SyncScheduler.self) private var syncScheduler
```

Then pass owner and request sync after deletion:

```swift
try WorkoutHistoryMutationService().deleteWorkoutHistory(
    session,
    ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
    context: modelContext
)
syncScheduler.requestSync()
deleteErrorMessage = nil
dismiss()
```

- [ ] **Step 5: Ensure finish records only visible completed graph entries**

In `ActiveWorkoutEngine.finishWorkout`, keep create intent scoped to visible children:

```swift
try recorder.recordCreate(
    entityKind: .workoutSession,
    entityID: session.id,
    ownerTokenIdentifier: nil,
    context: context,
    now: now
)
for loggedExercise in session.sortedLoggedExercises {
    try recorder.recordCreate(
        entityKind: .loggedExercise,
        entityID: loggedExercise.id,
        ownerTokenIdentifier: nil,
        context: context,
        now: now
    )
    for set in loggedExercise.sortedSets {
        try recorder.recordCreate(
            entityKind: .loggedSet,
            entityID: set.id,
            ownerTokenIdentifier: nil,
            context: context,
            now: now
        )
    }
}
```

This matches the existing intended behavior; change it only if current code includes deleted draft children.

- [ ] **Step 6: Run outbox tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncOutboxRecorderTests -only-testing:LiftingLogTests/SyncOutboxIntegrationTests
```

Expected: tests pass.

- [ ] **Step 7: Commit outbox behavior**

Run:

```bash
git add LiftingLog/Core/Sync/SyncOutboxRecorder.swift LiftingLog/Features/Workout/ActiveWorkoutEngine.swift LiftingLog/Core/Domain/WorkoutHistoryMutationService.swift LiftingLog/Features/History/WorkoutHistoryDetailView.swift LiftingLogTests/SyncOutboxRecorderTests.swift LiftingLogTests/SyncOutboxIntegrationTests.swift
git commit -m "Harden workout graph outbox intent"
```

Expected: commit succeeds.

---

### Task 5: Extend Coordinator Push Path

**Files:**
- Modify: `LiftingLog/Core/Sync/SyncCoordinator.swift`
- Modify: `LiftingLogTests/SyncCoordinatorTests.swift`

- [ ] **Step 1: Add failing push-order test**

In `SyncCoordinatorTests.swift`, add:

```swift
func testRunPushesCompletedWorkoutGraphInParentFirstOrder() async throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let exercise = Exercise(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000005001")!,
        name: "Bench Press",
        category: .strength,
        equipment: .barbell,
        primaryMuscle: "Chest",
        syncOwnerTokenIdentifier: owner
    )
    let session = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000005002")!,
        title: "Push",
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 200),
        durationSeconds: 100,
        status: .completed,
        source: .blank,
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let loggedExercise = LoggedExercise(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000005003")!,
        orderIndex: 0,
        exercise: exercise,
        createdAt: Date(timeIntervalSince1970: 110),
        updatedAt: Date(timeIntervalSince1970: 210)
    )
    let set = LoggedSet(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000005004")!,
        orderIndex: 0,
        weight: 185,
        reps: 5,
        kind: .working,
        isCompleted: true,
        createdAt: Date(timeIntervalSince1970: 120),
        updatedAt: Date(timeIntervalSince1970: 220)
    )
    loggedExercise.session = session
    set.loggedExercise = loggedExercise
    loggedExercise.sets.append(set)
    session.loggedExercises.append(loggedExercise)
    context.insert(exercise)
    context.insert(session)
    context.insert(loggedExercise)
    context.insert(set)
    let recorder = SyncOutboxRecorder()
    try recorder.recordCreate(entityKind: .loggedSet, entityID: set.id, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 300))
    try recorder.recordCreate(entityKind: .loggedExercise, entityID: loggedExercise.id, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 301))
    try recorder.recordCreate(entityKind: .workoutSession, entityID: session.id, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 302))
    try context.save()

    let client = FakeSyncClient()
    try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

    XCTAssertEqual(client.operationLog, [
        "upsertWorkoutSession:\(session.id.uuidString.lowercased())",
        "upsertLoggedExercise:\(loggedExercise.id.uuidString.lowercased())",
        "upsertLoggedSet:\(set.id.uuidString.lowercased())",
    ])
    XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
}
```

Add `operationLog` appends in `FakeSyncClient` methods:

```swift
var operationLog: [String] = []
```

In each fake upsert:

```swift
operationLog.append("upsertWorkoutSession:\(record.clientId)")
operationLog.append("upsertLoggedExercise:\(record.clientId)")
operationLog.append("upsertLoggedSet:\(record.clientId)")
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCoordinatorTests/testRunPushesCompletedWorkoutGraphInParentFirstOrder
```

Expected: fail because workout entries are filtered out or ignored.

- [ ] **Step 3: Sort pending entries by entity dependency before push**

In `SyncCoordinator.pushPendingEntries`, replace the settings/exercises filter with all current-owner v1 entries and dependency ordering:

```swift
let entries = try recorder.pendingEntries(context: context)
    .filter { entry in
        entry.ownerTokenIdentifier == ownerTokenIdentifier
    }
    .sorted { lhs, rhs in
        let lhsRank = syncPushRank(for: lhs.entityKind)
        let rhsRank = syncPushRank(for: rhs.entityKind)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.updatedAt < rhs.updatedAt
    }
```

Add:

```swift
private func syncPushRank(for entityKind: SyncEntityKind?) -> Int {
    switch entityKind {
    case .some(.userSettings): 0
    case .some(.exercise): 1
    case .some(.workoutSession): 2
    case .some(.loggedExercise): 3
    case .some(.loggedSet): 4
    default: 999
    }
}
```

- [ ] **Step 4: Add lookup helpers**

In `SyncCoordinator`, add:

```swift
private func findWorkoutSession(id: UUID, context: ModelContext) throws -> WorkoutSession? {
    try context.fetch(FetchDescriptor<WorkoutSession>())
        .first { $0.id == id }
}

private func findLoggedExercise(id: UUID, context: ModelContext) throws -> LoggedExercise? {
    try context.fetch(FetchDescriptor<LoggedExercise>())
        .first { $0.id == id }
}

private func findLoggedSet(id: UUID, context: ModelContext) throws -> LoggedSet? {
    try context.fetch(FetchDescriptor<LoggedSet>())
        .first { $0.id == id }
}
```

- [ ] **Step 5: Add workout push cases**

Extend `push(entry:ownerTokenIdentifier:fallbackTimestamp:context:)`:

```swift
case (.workoutSession, .create), (.workoutSession, .update):
    guard let session = try findWorkoutSession(id: entry.entityID, context: context) else {
        return try await client.tombstone(entityKind: .workoutSession, clientId: entry.entityID, deletedAt: fallbackTimestamp)
    }
    guard session.status != .active else { return nil }
    guard session.syncOwnerTokenIdentifier == nil || session.syncOwnerTokenIdentifier == ownerTokenIdentifier else {
        throw SyncCoordinatorError.ownerMismatch(entityKind: .workoutSession, entityID: entry.entityID)
    }
    return try await client.upsertWorkoutSession(SyncPayloadMapper.workoutSessionPayload(from: session))
case (.loggedExercise, .create), (.loggedExercise, .update):
    guard let loggedExercise = try findLoggedExercise(id: entry.entityID, context: context) else {
        return try await client.tombstone(entityKind: .loggedExercise, clientId: entry.entityID, deletedAt: fallbackTimestamp)
    }
    guard loggedExercise.session?.status != .active else { return nil }
    return try await client.upsertLoggedExercise(SyncPayloadMapper.loggedExercisePayload(from: loggedExercise))
case (.loggedSet, .create), (.loggedSet, .update):
    guard let set = try findLoggedSet(id: entry.entityID, context: context) else {
        return try await client.tombstone(entityKind: .loggedSet, clientId: entry.entityID, deletedAt: fallbackTimestamp)
    }
    guard set.loggedExercise?.session?.status != .active else { return nil }
    return try await client.upsertLoggedSet(SyncPayloadMapper.loggedSetPayload(from: set))
case (.workoutSession, .delete):
    let session = try findWorkoutSession(id: entry.entityID, context: context)
    let deletedAt = session?.deletedAt ?? fallbackTimestamp
    return try await client.tombstone(entityKind: .workoutSession, clientId: entry.entityID, deletedAt: deletedAt)
case (.loggedExercise, .delete):
    let loggedExercise = try findLoggedExercise(id: entry.entityID, context: context)
    let deletedAt = loggedExercise?.deletedAt ?? fallbackTimestamp
    return try await client.tombstone(entityKind: .loggedExercise, clientId: entry.entityID, deletedAt: deletedAt)
case (.loggedSet, .delete):
    let set = try findLoggedSet(id: entry.entityID, context: context)
    let deletedAt = set?.deletedAt ?? fallbackTimestamp
    return try await client.tombstone(entityKind: .loggedSet, clientId: entry.entityID, deletedAt: deletedAt)
```

If `WorkoutSession`, `LoggedExercise`, and `LoggedSet` do not have owner fields, owner is enforced through the outbox entry owner and parent graph ownership. Do not add owner fields to these models in this issue unless tests prove owner mismatch cannot be handled safely without them.

- [ ] **Step 6: Extend stale cursor rewind**

In `rewindCursorForIgnoredStaleResult`, add:

```swift
case .some(.workoutSession):
    state.workoutSessionsCursor = min(state.workoutSessionsCursor, refetchCursor)
case .some(.loggedExercise):
    state.loggedExercisesCursor = min(state.loggedExercisesCursor, refetchCursor)
case .some(.loggedSet):
    state.loggedSetsCursor = min(state.loggedSetsCursor, refetchCursor)
```

- [ ] **Step 7: Add active-session exclusion push test**

Add:

```swift
func testRunSkipsActiveWorkoutSessionOutboxEntry() async throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let session = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000005101")!,
        title: "Active",
        startedAt: Date(timeIntervalSince1970: 100),
        status: .active,
        source: .blank
    )
    context.insert(session)
    try SyncOutboxRecorder().recordCreate(
        entityKind: .workoutSession,
        entityID: session.id,
        ownerTokenIdentifier: owner,
        context: context,
        now: Date(timeIntervalSince1970: 200)
    )
    try context.save()

    let client = FakeSyncClient()
    try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

    XCTAssertTrue(client.upsertedWorkoutSessions.isEmpty)
    XCTAssertTrue(client.tombstones.isEmpty)
}
```

- [ ] **Step 8: Run coordinator push tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCoordinatorTests/testRunPushesCompletedWorkoutGraphInParentFirstOrder -only-testing:LiftingLogTests/SyncCoordinatorTests/testRunSkipsActiveWorkoutSessionOutboxEntry
```

Expected: tests pass.

- [ ] **Step 9: Commit push path**

Run:

```bash
git add LiftingLog/Core/Sync/SyncCoordinator.swift LiftingLogTests/SyncCoordinatorTests.swift
git commit -m "Push workout graph sync entries"
```

Expected: commit succeeds.

---

### Task 6: Extend Coordinator Pull Path

**Files:**
- Modify: `LiftingLog/Core/Sync/SyncCoordinator.swift`
- Modify: `LiftingLogTests/SyncCoordinatorTests.swift`

- [ ] **Step 1: Add failing full graph pull test**

In `SyncCoordinatorTests.swift`, add:

```swift
func testRunPullsFullWorkoutGraphIntoEmptyStore() async throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006001")!
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000006002")!
    let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000006003")!
    let setID = UUID(uuidString: "00000000-0000-0000-0000-000000006004")!
    let client = FakeSyncClient()
    client.fetchResponses = [
        SyncFetchChangesResponse(
            userSettings: [],
            exercises: [
                ExerciseSyncRecord(
                    clientId: exerciseID.uuidString.lowercased(),
                    createdAt: 10,
                    updatedAt: 20,
                    deletedAt: nil,
                    serverUpdatedAt: 30,
                    seedIdentifier: nil,
                    name: "Bench Press",
                    categoryRaw: "strength",
                    equipmentRaw: "barbell",
                    primaryMuscleRaw: "Chest",
                    primaryMuscleGroupRaw: "chest",
                    notes: "",
                    isArchived: false,
                    isSeeded: false
                )
            ],
            workoutSessions: [
                WorkoutSessionSyncRecord(
                    clientId: sessionID.uuidString.lowercased(),
                    createdAt: 11,
                    updatedAt: 21,
                    deletedAt: nil,
                    serverUpdatedAt: 31,
                    title: "Push",
                    startedAt: 100,
                    endedAt: 200,
                    durationSeconds: 100,
                    notes: "Good",
                    referenceNotes: nil,
                    statusRaw: "completed",
                    sourceRaw: "blank",
                    sourceSessionID: nil,
                    healthLinkID: nil
                )
            ],
            loggedExercises: [
                LoggedExerciseSyncRecord(
                    clientId: loggedExerciseID.uuidString.lowercased(),
                    createdAt: 12,
                    updatedAt: 22,
                    deletedAt: nil,
                    serverUpdatedAt: 32,
                    sessionClientId: sessionID.uuidString.lowercased(),
                    exerciseClientId: exerciseID.uuidString.lowercased(),
                    orderIndex: 0,
                    exerciseSnapshotName: "Bench Press",
                    exerciseSnapshotEquipmentRaw: "barbell",
                    exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
                    hasSnapshotMetadata: true,
                    notes: "Paused",
                    referenceNotes: nil
                )
            ],
            loggedSets: [
                LoggedSetSyncRecord(
                    clientId: setID.uuidString.lowercased(),
                    createdAt: 13,
                    updatedAt: 23,
                    deletedAt: nil,
                    serverUpdatedAt: 33,
                    loggedExerciseClientId: loggedExerciseID.uuidString.lowercased(),
                    orderIndex: 0,
                    weight: 185,
                    reps: 5,
                    rpe: 8,
                    placeholderWeight: nil,
                    placeholderReps: nil,
                    placeholderRPE: nil,
                    kindRaw: "working",
                    isCompleted: true,
                    completedAt: 190,
                    notes: "",
                    healthLinkID: nil
                )
            ],
            cursors: SyncChangeCursors(
                userSettings: 0,
                exercises: 30,
                workoutSessions: 31,
                loggedExercises: 32,
                loggedSets: 33
            ),
            hasMore: SyncHasMore(userSettings: false, exercises: false)
        )
    ]

    try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

    let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
    let session = try XCTUnwrap(sessions.first { $0.id == sessionID })
    XCTAssertEqual(session.title, "Push")
    XCTAssertEqual(session.status, .completed)
    XCTAssertEqual(session.sortedLoggedExercises.count, 1)
    let loggedExercise = try XCTUnwrap(session.sortedLoggedExercises.first)
    XCTAssertEqual(loggedExercise.id, loggedExerciseID)
    XCTAssertEqual(loggedExercise.exercise?.id, exerciseID)
    XCTAssertEqual(loggedExercise.sortedSets.map(\.id), [setID])
    XCTAssertEqual(loggedExercise.sortedSets.first?.weight, 185)

    let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
    XCTAssertEqual(state.exercisesCursor, 30)
    XCTAssertEqual(state.workoutSessionsCursor, 31)
    XCTAssertEqual(state.loggedExercisesCursor, 32)
    XCTAssertEqual(state.loggedSetsCursor, 33)
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCoordinatorTests/testRunPullsFullWorkoutGraphIntoEmptyStore
```

Expected: fail because workout records are not applied.

- [ ] **Step 3: Fetch full cursors**

In `pullChanges`, call:

```swift
let response = try await client.fetchChanges(
    cursors: SyncChangeCursors(
        userSettings: state.userSettingsCursor,
        exercises: state.exercisesCursor,
        workoutSessions: state.workoutSessionsCursor,
        loggedExercises: state.loggedExercisesCursor,
        loggedSets: state.loggedSetsCursor
    ),
    limit: 100
)
```

Update loop continuation:

```swift
hasMore = response.hasMore.userSettings
    || response.hasMore.exercises
    || response.hasMore.workoutSessions
    || response.hasMore.loggedExercises
    || response.hasMore.loggedSets
```

- [ ] **Step 4: Apply workout session records**

Add:

```swift
private func apply(
    workoutSessionRecords records: [WorkoutSessionSyncRecord],
    ownerTokenIdentifier: String,
    context: ModelContext
) throws -> Double? {
    var maxAppliedServerUpdatedAt: Double?
    for record in records {
        guard let id = UUID(uuidString: record.clientId) else { continue }
        let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
        let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        if let session = try findWorkoutSession(id: id, context: context) {
            guard SyncConflictResolver.decision(
                localUpdatedAt: session.updatedAt,
                localDeletedAt: session.deletedAt,
                incomingUpdatedAt: incomingUpdatedAt,
                incomingDeletedAt: incomingDeletedAt,
                allowsIncomingRestore: false
            ) == .applyIncoming else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            apply(record, to: session)
        } else {
            guard incomingDeletedAt == nil else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            let session = WorkoutSession(
                id: id,
                title: record.title,
                startedAt: Date(timeIntervalSince1970: record.startedAt),
                endedAt: record.endedAt.map(Date.init(timeIntervalSince1970:)),
                durationSeconds: record.durationSeconds,
                notes: record.notes,
                status: WorkoutSessionStatus(rawValue: record.statusRaw) ?? .completed,
                source: WorkoutSource(rawValue: record.sourceRaw) ?? .blank,
                sourceSessionID: record.sourceSessionID.flatMap(UUID.init(uuidString:)),
                referenceNotes: record.referenceNotes,
                createdAt: Date(timeIntervalSince1970: record.createdAt),
                updatedAt: incomingUpdatedAt,
                deletedAt: incomingDeletedAt,
                healthLinkID: record.healthLinkID.flatMap(UUID.init(uuidString:))
            )
            context.insert(session)
        }
        maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
    }
    return maxAppliedServerUpdatedAt
}

private func apply(_ record: WorkoutSessionSyncRecord, to session: WorkoutSession) {
    session.title = record.title
    session.startedAt = Date(timeIntervalSince1970: record.startedAt)
    session.endedAt = record.endedAt.map(Date.init(timeIntervalSince1970:))
    session.durationSeconds = record.durationSeconds
    session.notes = record.notes
    session.referenceNotes = record.referenceNotes
    session.statusRaw = record.statusRaw
    session.sourceRaw = record.sourceRaw
    session.sourceSessionID = record.sourceSessionID.flatMap(UUID.init(uuidString:))
    session.healthLinkID = record.healthLinkID.flatMap(UUID.init(uuidString:))
    session.createdAt = Date(timeIntervalSince1970: record.createdAt)
    session.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
    session.deletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
}
```

- [ ] **Step 5: Apply logged exercise and set records without orphans**

Add:

```swift
private func apply(
    loggedExerciseRecords records: [LoggedExerciseSyncRecord],
    ownerTokenIdentifier: String,
    context: ModelContext
) throws -> Double? {
    var maxAppliedServerUpdatedAt: Double?
    for record in records {
        guard let id = UUID(uuidString: record.clientId),
              let sessionID = UUID(uuidString: record.sessionClientId),
              let session = try findWorkoutSession(id: sessionID, context: context) else {
            continue
        }
        let exercise = try record.exerciseClientId
            .flatMap(UUID.init(uuidString:))
            .flatMap { try findExercise(id: $0, context: context) }
        let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
        let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))

        if let loggedExercise = try findLoggedExercise(id: id, context: context) {
            guard SyncConflictResolver.decision(
                localUpdatedAt: loggedExercise.updatedAt,
                localDeletedAt: loggedExercise.deletedAt,
                incomingUpdatedAt: incomingUpdatedAt,
                incomingDeletedAt: incomingDeletedAt,
                allowsIncomingRestore: false
            ) == .applyIncoming else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            apply(record, to: loggedExercise, session: session, exercise: exercise)
        } else {
            guard incomingDeletedAt == nil else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            let loggedExercise = LoggedExercise(
                id: id,
                orderIndex: record.orderIndex,
                exercise: exercise,
                exerciseSnapshotName: record.exerciseSnapshotName,
                exerciseSnapshotEquipmentRaw: record.exerciseSnapshotEquipmentRaw,
                exerciseSnapshotPrimaryMuscleGroupRaw: record.exerciseSnapshotPrimaryMuscleGroupRaw,
                notes: record.notes,
                referenceNotes: record.referenceNotes,
                createdAt: Date(timeIntervalSince1970: record.createdAt),
                updatedAt: incomingUpdatedAt,
                deletedAt: incomingDeletedAt
            )
            loggedExercise.hasSnapshotMetadata = record.hasSnapshotMetadata
            loggedExercise.session = session
            session.loggedExercises.append(loggedExercise)
            context.insert(loggedExercise)
        }
        maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
    }
    return maxAppliedServerUpdatedAt
}

private func apply(
    loggedSetRecords records: [LoggedSetSyncRecord],
    ownerTokenIdentifier: String,
    context: ModelContext
) throws -> Double? {
    var maxAppliedServerUpdatedAt: Double?
    for record in records {
        guard let id = UUID(uuidString: record.clientId),
              let loggedExerciseID = UUID(uuidString: record.loggedExerciseClientId),
              let loggedExercise = try findLoggedExercise(id: loggedExerciseID, context: context) else {
            continue
        }
        let incomingUpdatedAt = Date(timeIntervalSince1970: record.updatedAt)
        let incomingDeletedAt = record.deletedAt.map(Date.init(timeIntervalSince1970:))
        if let set = try findLoggedSet(id: id, context: context) {
            guard SyncConflictResolver.decision(
                localUpdatedAt: set.updatedAt,
                localDeletedAt: set.deletedAt,
                incomingUpdatedAt: incomingUpdatedAt,
                incomingDeletedAt: incomingDeletedAt,
                allowsIncomingRestore: false
            ) == .applyIncoming else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            apply(record, to: set, loggedExercise: loggedExercise)
        } else {
            guard incomingDeletedAt == nil else {
                maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
                continue
            }
            let set = LoggedSet(
                id: id,
                orderIndex: record.orderIndex,
                weight: record.weight,
                reps: record.reps,
                rpe: record.rpe,
                placeholderWeight: record.placeholderWeight,
                placeholderReps: record.placeholderReps,
                placeholderRPE: record.placeholderRPE,
                kind: SetKind(rawValue: record.kindRaw) ?? .working,
                isCompleted: record.isCompleted,
                completedAt: record.completedAt.map(Date.init(timeIntervalSince1970:)),
                notes: record.notes,
                createdAt: Date(timeIntervalSince1970: record.createdAt),
                updatedAt: incomingUpdatedAt,
                deletedAt: incomingDeletedAt,
                healthLinkID: record.healthLinkID.flatMap(UUID.init(uuidString:))
            )
            set.loggedExercise = loggedExercise
            loggedExercise.sets.append(set)
            context.insert(set)
        }
        maxAppliedServerUpdatedAt = max(maxAppliedServerUpdatedAt ?? 0, record.serverUpdatedAt)
    }
    return maxAppliedServerUpdatedAt
}
```

Also add `apply` helpers for updating existing logged exercises and sets with the same fields used for construction.

- [ ] **Step 6: Update cursors conservatively**

In `pullChanges`, after applying records:

```swift
let appliedWorkoutSessionCursor = try apply(workoutSessionRecords: response.workoutSessions, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
let appliedLoggedExerciseCursor = try apply(loggedExerciseRecords: response.loggedExercises, ownerTokenIdentifier: ownerTokenIdentifier, context: context)
let appliedLoggedSetCursor = try apply(loggedSetRecords: response.loggedSets, ownerTokenIdentifier: ownerTokenIdentifier, context: context)

state.userSettingsCursor = max(state.userSettingsCursor, response.cursors.userSettings)
state.exercisesCursor = max(state.exercisesCursor, response.cursors.exercises)
if let appliedWorkoutSessionCursor {
    state.workoutSessionsCursor = max(state.workoutSessionsCursor, appliedWorkoutSessionCursor)
}
if let appliedLoggedExerciseCursor {
    state.loggedExercisesCursor = max(state.loggedExercisesCursor, appliedLoggedExerciseCursor)
}
if let appliedLoggedSetCursor {
    state.loggedSetsCursor = max(state.loggedSetsCursor, appliedLoggedSetCursor)
}
```

This avoids advancing a child cursor when no child records were applied because parents were missing.

- [ ] **Step 7: Add missing-parent deferral test**

Add:

```swift
func testPullDoesNotAdvanceLoggedSetCursorWhenParentLoggedExerciseIsMissing() async throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let client = FakeSyncClient()
    client.fetchResponses = [
        SyncFetchChangesResponse(
            userSettings: [],
            exercises: [],
            workoutSessions: [],
            loggedExercises: [],
            loggedSets: [
                LoggedSetSyncRecord(
                    clientId: "00000000-0000-0000-0000-000000006104",
                    createdAt: 1,
                    updatedAt: 2,
                    deletedAt: nil,
                    serverUpdatedAt: 50,
                    loggedExerciseClientId: "00000000-0000-0000-0000-000000006103",
                    orderIndex: 0,
                    weight: 100,
                    reps: 5,
                    rpe: nil,
                    placeholderWeight: nil,
                    placeholderReps: nil,
                    placeholderRPE: nil,
                    kindRaw: "working",
                    isCompleted: true,
                    completedAt: nil,
                    notes: "",
                    healthLinkID: nil
                )
            ],
            cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 0, loggedExercises: 0, loggedSets: 50),
            hasMore: SyncHasMore(userSettings: false, exercises: false)
        )
    ]

    try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

    let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
    XCTAssertEqual(state.loggedSetsCursor, 0)
    XCTAssertTrue(try context.fetch(FetchDescriptor<LoggedSet>()).isEmpty)
}
```

- [ ] **Step 8: Run pull tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCoordinatorTests/testRunPullsFullWorkoutGraphIntoEmptyStore -only-testing:LiftingLogTests/SyncCoordinatorTests/testPullDoesNotAdvanceLoggedSetCursorWhenParentLoggedExerciseIsMissing
```

Expected: tests pass.

- [ ] **Step 9: Commit pull path**

Run:

```bash
git add LiftingLog/Core/Sync/SyncCoordinator.swift LiftingLogTests/SyncCoordinatorTests.swift
git commit -m "Pull workout graph sync records"
```

Expected: commit succeeds.

---

### Task 7: Implement Remote-First Workout Bootstrap

**Files:**
- Modify: `LiftingLog/Core/Sync/SyncCoordinator.swift`
- Modify: `LiftingLogTests/SyncCoordinatorTests.swift`
- Modify: `LiftingLogTests/SyncOutboxIntegrationTests.swift`

- [ ] **Step 1: Add failing no-remote bootstrap upload test**

In `SyncCoordinatorTests.swift`, add:

```swift
func testFirstWorkoutGraphRunBootstrapsLocalCompletedWorkoutWhenRemoteGraphIsEmpty() async throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let session = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000007001")!,
        title: "Local Push",
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 200),
        durationSeconds: 100,
        status: .completed,
        source: .blank
    )
    context.insert(session)
    try context.save()

    let client = FakeSyncClient()
    client.fetchResponses = [
        SyncFetchChangesResponse(
            userSettings: [],
            exercises: [],
            workoutSessions: [],
            loggedExercises: [],
            loggedSets: [],
            cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
            hasMore: SyncHasMore(userSettings: false, exercises: false)
        )
    ]

    try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

    XCTAssertEqual(client.upsertedWorkoutSessions.map(\.clientId), [session.id.uuidString.lowercased()])
    let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
    XCTAssertTrue(state.hasBootstrappedWorkoutGraph)
}
```

- [ ] **Step 2: Add failing remote-existing test**

Add:

```swift
func testFirstWorkoutGraphRunDoesNotBulkUploadOwnerlessLocalWorkoutWhenRemoteGraphExists() async throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let localSession = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000007101")!,
        title: "Local Push",
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 200),
        durationSeconds: 100,
        status: .completed,
        source: .blank
    )
    let remoteSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000007102")!
    context.insert(localSession)
    try context.save()

    let client = FakeSyncClient()
    client.fetchResponses = [
        SyncFetchChangesResponse(
            userSettings: [],
            exercises: [],
            workoutSessions: [
                WorkoutSessionSyncRecord(
                    clientId: remoteSessionID.uuidString.lowercased(),
                    createdAt: 10,
                    updatedAt: 20,
                    deletedAt: nil,
                    serverUpdatedAt: 30,
                    title: "Remote Push",
                    startedAt: 100,
                    endedAt: 200,
                    durationSeconds: 100,
                    notes: "",
                    referenceNotes: nil,
                    statusRaw: "completed",
                    sourceRaw: "blank",
                    sourceSessionID: nil,
                    healthLinkID: nil
                )
            ],
            loggedExercises: [],
            loggedSets: [],
            cursors: SyncChangeCursors(userSettings: 0, exercises: 0, workoutSessions: 30),
            hasMore: SyncHasMore(userSettings: false, exercises: false)
        )
    ]

    try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

    XCTAssertTrue(client.upsertedWorkoutSessions.isEmpty)
    XCTAssertEqual(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).count, 0)
    XCTAssertNotNil(try context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == remoteSessionID })
}
```

- [ ] **Step 3: Implement bootstrap summary tracking**

Extend `SyncPullSummary` to record workout graph remote presence:

```swift
struct SyncPullSummary {
    var hasRemoteRecords = false
    var hasRemoteWorkoutGraphRecords = false

    mutating func record(_ response: SyncFetchChangesResponse) {
        if !response.userSettings.isEmpty || !response.exercises.isEmpty {
            hasRemoteRecords = true
        }
        if !response.workoutSessions.isEmpty || !response.loggedExercises.isEmpty || !response.loggedSets.isEmpty {
            hasRemoteRecords = true
            hasRemoteWorkoutGraphRecords = true
        }
    }
}
```

If `SyncPullSummary` already exists with a different shape, keep its existing semantics and add `hasRemoteWorkoutGraphRecords`.

- [ ] **Step 4: Add workout bootstrap candidate selection**

Add a helper:

```swift
private func bootstrapWorkoutGraphForSync(
    ownerTokenIdentifier: String,
    includeOwnerlessCompletedWorkouts: Bool,
    context: ModelContext,
    now: Date
) throws {
    guard includeOwnerlessCompletedWorkouts else { return }
    for session in try context.fetch(FetchDescriptor<WorkoutSession>())
        where session.status == .completed && !session.isDeleted {
        try recordBootstrapEntry(
            entityKind: .workoutSession,
            entityID: session.id,
            isDeleted: session.isDeleted,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
        for loggedExercise in session.sortedLoggedExercises {
            try recordBootstrapEntry(
                entityKind: .loggedExercise,
                entityID: loggedExercise.id,
                isDeleted: loggedExercise.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
            for set in loggedExercise.sortedSets {
                try recordBootstrapEntry(
                    entityKind: .loggedSet,
                    entityID: set.id,
                    isDeleted: set.isDeleted,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )
            }
        }
    }
}
```

Call this from `prepareForSync` when `!state.hasBootstrappedWorkoutGraph`, using `includeOwnerlessCompletedWorkouts` from the first pull summary. Set `state.hasBootstrappedWorkoutGraph = true` after the bootstrap decision is processed.

- [ ] **Step 5: Claim ownerless workout outbox entries with explicit local intent**

In the outbox entry loop in `prepareForSync`, include workout graph kinds:

```swift
guard let entityKind = entry.entityKind, entityKind.isV1Synced else {
    continue
}
```

Extend `canClaim(entry:ownerTokenIdentifier:context:)`:

```swift
case .workoutSession:
    return try findWorkoutSession(id: entry.entityID, context: context) != nil
case .loggedExercise:
    return try findLoggedExercise(id: entry.entityID, context: context) != nil
case .loggedSet:
    return try findLoggedSet(id: entry.entityID, context: context) != nil
```

The explicit outbox entry is the local intent; do not bulk-upload unrelated ownerless completed sessions when remote graph records exist.

- [ ] **Step 6: Run bootstrap tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCoordinatorTests/testFirstWorkoutGraphRunBootstrapsLocalCompletedWorkoutWhenRemoteGraphIsEmpty -only-testing:LiftingLogTests/SyncCoordinatorTests/testFirstWorkoutGraphRunDoesNotBulkUploadOwnerlessLocalWorkoutWhenRemoteGraphExists
```

Expected: tests pass.

- [ ] **Step 7: Commit bootstrap behavior**

Run:

```bash
git add LiftingLog/Core/Sync/SyncCoordinator.swift LiftingLogTests/SyncCoordinatorTests.swift LiftingLogTests/SyncOutboxIntegrationTests.swift
git commit -m "Bootstrap workout graph sync safely"
```

Expected: commit succeeds.

---

### Task 8: Add Retry, Tombstone, and Idempotency Tests

**Files:**
- Modify: `LiftingLog/Core/Sync/SyncCoordinator.swift`
- Modify: `LiftingLogTests/SyncCoordinatorTests.swift`

- [ ] **Step 1: Add failing delete tombstone test for synced workout graph**

Add:

```swift
func testRunTombstonesDeletedWorkoutGraphEntries() async throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let session = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000008001")!,
        title: "Deleted",
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 200),
        durationSeconds: 100,
        status: .completed,
        source: .blank
    )
    let loggedExercise = LoggedExercise(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000008002")!,
        orderIndex: 0
    )
    let set = LoggedSet(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000008003")!,
        orderIndex: 0
    )
    loggedExercise.session = session
    set.loggedExercise = loggedExercise
    loggedExercise.sets.append(set)
    session.loggedExercises.append(loggedExercise)
    context.insert(session)
    context.insert(loggedExercise)
    context.insert(set)
    try context.save()

    try WorkoutHistoryMutationService().deleteWorkoutHistory(
        session,
        ownerTokenIdentifier: owner,
        context: context,
        now: Date(timeIntervalSince1970: 300)
    )

    let client = FakeSyncClient()
    try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

    XCTAssertEqual(client.tombstones.map(\.0), [.workoutSession, .loggedExercise, .loggedSet])
    XCTAssertEqual(Set(client.tombstones.map(\.2)), [Date(timeIntervalSince1970: 300)])
}
```

- [ ] **Step 2: Add ignored-stale cursor rewind test**

Add:

```swift
func testIgnoredStaleWorkoutSessionPushRewindsWorkoutCursor() async throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let state = SyncCursorState(ownerTokenIdentifier: owner, workoutSessionsCursor: 500)
    let session = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000008101")!,
        title: "Stale",
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 200),
        durationSeconds: 100,
        status: .completed,
        source: .blank
    )
    context.insert(state)
    context.insert(session)
    try SyncOutboxRecorder().recordUpdate(
        entityKind: .workoutSession,
        entityID: session.id,
        ownerTokenIdentifier: owner,
        context: context,
        now: Date(timeIntervalSince1970: 300)
    )
    try context.save()

    let client = FakeSyncClient()
    client.workoutSessionMutationResults = [
        SyncMutationResult(status: "ignored_stale", serverUpdatedAt: 250)
    ]

    try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

    XCTAssertEqual(state.workoutSessionsCursor, 249)
}
```

- [ ] **Step 3: Add retry no-duplicate test**

Add:

```swift
func testRetryAfterWorkoutPushFailureDoesNotDuplicateOutboxEntries() async throws {
    struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let owner = "issuer|owner_a"
    let session = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000008201")!,
        title: "Retry",
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 200),
        durationSeconds: 100,
        status: .completed,
        source: .blank
    )
    context.insert(session)
    try SyncOutboxRecorder().recordCreate(
        entityKind: .workoutSession,
        entityID: session.id,
        ownerTokenIdentifier: owner,
        context: context,
        now: Date(timeIntervalSince1970: 300)
    )
    try context.save()

    let failingClient = FakeSyncClient()
    failingClient.error = PushError()
    try await SyncCoordinator(client: failingClient).run(ownerTokenIdentifier: owner, context: context)

    let failedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
    XCTAssertEqual(failedEntry.status, .failed)

    let retryClient = FakeSyncClient()
    try await SyncCoordinator(client: retryClient).run(ownerTokenIdentifier: owner, context: context)

    XCTAssertEqual(retryClient.upsertedWorkoutSessions.map(\.clientId), [session.id.uuidString.lowercased()])
    XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
}
```

- [ ] **Step 4: Implement fixes surfaced by tests**

If these tests fail, make these concrete updates:

```swift
case .some(.workoutSession):
    state.workoutSessionsCursor = min(state.workoutSessionsCursor, refetchCursor)
case .some(.loggedExercise):
    state.loggedExercisesCursor = min(state.loggedExercisesCursor, refetchCursor)
case .some(.loggedSet):
    state.loggedSetsCursor = min(state.loggedSetsCursor, refetchCursor)
```

Ensure `prepareForSync` retries failed workout graph entries:

```swift
if entry.ownerTokenIdentifier == ownerTokenIdentifier, entry.status == .inFlight || entry.status == .failed {
    recorder.markPendingForRetry(entry, now: .now)
}
```

Ensure delete push cases use `deletedAt` from the local tombstoned model before falling back to outbox logical time.

- [ ] **Step 5: Run retry/tombstone tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/SyncCoordinatorTests/testRunTombstonesDeletedWorkoutGraphEntries -only-testing:LiftingLogTests/SyncCoordinatorTests/testIgnoredStaleWorkoutSessionPushRewindsWorkoutCursor -only-testing:LiftingLogTests/SyncCoordinatorTests/testRetryAfterWorkoutPushFailureDoesNotDuplicateOutboxEntries
```

Expected: tests pass.

- [ ] **Step 6: Commit retry/tombstone behavior**

Run:

```bash
git add LiftingLog/Core/Sync/SyncCoordinator.swift LiftingLogTests/SyncCoordinatorTests.swift
git commit -m "Handle workout sync retries and tombstones"
```

Expected: commit succeeds.

---

### Task 9: Add Convex Workout Graph Coverage

**Files:**
- Modify: `convex/sync.test.ts`
- Modify only if tests expose a backend gap: `convex/sync.ts`, `convex/sync/validators.ts`, `convex/schema.ts`

- [ ] **Step 1: Add workout session and set record helpers**

In `convex/sync.test.ts`, add:

```ts
function workoutSessionRecord(
  overrides: Partial<WorkoutSessionRecord> = {},
): WorkoutSessionRecord {
  const base: WorkoutSessionRecord = {
    clientId: "session-1",
    title: "Push",
    startedAt: 100,
    endedAt: 200,
    durationSeconds: 100,
    notes: "",
    referenceNotes: null,
    statusRaw: "completed",
    sourceRaw: "blank",
    sourceSessionID: null,
    healthLinkID: null,
    createdAt: 1,
    updatedAt: 2,
    deletedAt: null,
  };
  return Object.assign(base, overrides);
}

function loggedSetRecord(overrides: Partial<LoggedSetRecord> = {}): LoggedSetRecord {
  const base: LoggedSetRecord = {
    clientId: "set-1",
    loggedExerciseClientId: "logged-exercise-1",
    orderIndex: 0,
    weight: 185,
    reps: 5,
    rpe: 8,
    placeholderWeight: null,
    placeholderReps: null,
    placeholderRPE: null,
    kindRaw: "working",
    isCompleted: true,
    completedAt: 200,
    notes: "",
    healthLinkID: null,
    createdAt: 1,
    updatedAt: 2,
    deletedAt: null,
  };
  return Object.assign(base, overrides);
}

type WorkoutSessionRecord = {
  clientId: string;
  title: string;
  startedAt: number;
  endedAt: number | null;
  durationSeconds: number;
  notes: string;
  referenceNotes: string | null;
  statusRaw: "completed" | "discarded";
  sourceRaw: "blank" | "pastWorkout" | "template";
  sourceSessionID: string | null;
  healthLinkID: string | null;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};

type LoggedSetRecord = {
  clientId: string;
  loggedExerciseClientId: string;
  orderIndex: number;
  weight: number | null;
  reps: number | null;
  rpe: number | null;
  placeholderWeight: number | null;
  placeholderReps: number | null;
  placeholderRPE: number | null;
  kindRaw: "working" | "warmup" | "drop" | "failure";
  isCompleted: boolean;
  completedAt: number | null;
  notes: string;
  healthLinkID: string | null;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};
```

- [ ] **Step 2: Add full graph round-trip test**

Add:

```ts
test("full workout graph round-trips through fetchChanges", async () => {
  const t = testDb().withIdentity(userA);

  await t.mutation(api.sync.upsertExercise, { record: exerciseRecord() });
  await t.mutation(api.sync.upsertWorkoutSession, {
    record: workoutSessionRecord(),
  });
  await t.mutation(api.sync.upsertLoggedExercise, {
    record: loggedExerciseRecord(),
  });
  await t.mutation(api.sync.upsertLoggedSet, {
    record: loggedSetRecord(),
  });

  const changes = await t.query(api.sync.fetchChanges, {
    cursors: zeroCursors,
  });

  expect(changes.workoutSessions).toHaveLength(1);
  expect(changes.loggedExercises).toHaveLength(1);
  expect(changes.loggedSets).toHaveLength(1);
  expect(changes.workoutSessions[0]).toMatchObject({
    clientId: "session-1",
    title: "Push",
    statusRaw: "completed",
  });
  expect(changes.loggedExercises[0]).toMatchObject({
    clientId: "logged-exercise-1",
    sessionClientId: "session-1",
    exerciseClientId: "exercise-1",
  });
  expect(changes.loggedSets[0]).toMatchObject({
    clientId: "set-1",
    loggedExerciseClientId: "logged-exercise-1",
    reps: 5,
  });
});
```

- [ ] **Step 3: Add tombstone test**

Add:

```ts
test("workout graph tombstones stay in fetchChanges", async () => {
  const t = testDb().withIdentity(userA);

  await t.mutation(api.sync.upsertWorkoutSession, {
    record: workoutSessionRecord(),
  });
  await t.mutation(api.sync.upsertLoggedExercise, {
    record: loggedExerciseRecord(),
  });
  await t.mutation(api.sync.upsertLoggedSet, {
    record: loggedSetRecord(),
  });

  await t.mutation(api.sync.tombstone, {
    entityKind: "workoutSessions",
    clientId: "session-1",
    deletedAt: 10,
  });
  await t.mutation(api.sync.tombstone, {
    entityKind: "loggedExercises",
    clientId: "logged-exercise-1",
    deletedAt: 10,
  });
  await t.mutation(api.sync.tombstone, {
    entityKind: "loggedSets",
    clientId: "set-1",
    deletedAt: 10,
  });

  const changes = await t.query(api.sync.fetchChanges, {
    cursors: zeroCursors,
  });

  expect(changes.workoutSessions[0].deletedAt).toBe(10);
  expect(changes.loggedExercises[0].deletedAt).toBe(10);
  expect(changes.loggedSets[0].deletedAt).toBe(10);
});
```

- [ ] **Step 4: Add per-table cursor test**

Add:

```ts
test("workout graph cursors page independently", async () => {
  const t = testDb().withIdentity(userA);

  await t.mutation(api.sync.upsertWorkoutSession, {
    record: workoutSessionRecord({ clientId: "session-1", updatedAt: 2 }),
  });
  await t.mutation(api.sync.upsertWorkoutSession, {
    record: workoutSessionRecord({ clientId: "session-2", updatedAt: 3 }),
  });
  await t.mutation(api.sync.upsertLoggedExercise, {
    record: loggedExerciseRecord({ clientId: "logged-exercise-1", updatedAt: 4 }),
  });

  const firstPage = await t.query(api.sync.fetchChanges, {
    cursors: zeroCursors,
    limit: 1,
  });
  const secondPage = await t.query(api.sync.fetchChanges, {
    cursors: firstPage.cursors,
    limit: 1,
  });

  expect(firstPage.workoutSessions).toHaveLength(1);
  expect(firstPage.loggedExercises).toHaveLength(1);
  expect(firstPage.hasMore.workoutSessions).toBe(true);
  expect(secondPage.workoutSessions).toHaveLength(1);
  expect(secondPage.workoutSessions[0].clientId).toBe("session-2");
});
```

- [ ] **Step 5: Run Convex tests**

Run:

```bash
pnpm run convex:test
pnpm run convex:typecheck
```

Expected: both commands pass.

- [ ] **Step 6: Fix backend gaps if tests fail**

If a test fails due to backend behavior, fix only the exposed gap in the existing `upsertWorkoutSession`, `upsertLoggedExercise`, `upsertLoggedSet`, `tombstone`, and `fetchChanges` functions.

Do not add a bundled whole-workout mutation.

- [ ] **Step 7: Commit Convex coverage**

Run:

```bash
git add convex/sync.test.ts convex/sync.ts convex/sync/validators.ts convex/schema.ts
git commit -m "Cover workout graph sync API"
```

Expected: commit succeeds. If no backend source files changed, `git add convex/sync.test.ts` is enough.

---

### Task 10: Add Targeted UI Tests

**Files:**
- Modify: `LiftingLogUITests/LiftingLogUITests.swift`

- [ ] **Step 1: Add finish-to-history assertion test if coverage is not already equivalent**

The existing `testCompletedWorkoutCanBeOpenedFromWorkoutAndExerciseHistory` covers finish-to-history. If it remains present and passing, keep it and do not add a duplicate.

If it has been removed during implementation, add:

```swift
@MainActor
func testCompletedWorkoutAppearsInHistory() {
    let app = makeApp()
    app.launch()

    createCompletedBenchWorkout(in: app, title: "Sync Ready Push")

    app.buttons["HistoryTab"].tap()
    XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
    app.buttons["WorkoutHistoryButton-0"].tap()
    XCTAssertTrue(app.staticTexts["Sync Ready Push"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
}
```

- [ ] **Step 2: Add delete-from-history UI test**

Add:

```swift
@MainActor
func testDeletingCompletedWorkoutRemovesItFromHistory() {
    let app = makeApp()
    app.launch()

    createCompletedBenchWorkout(in: app, title: "Delete Me")

    app.buttons["HistoryTab"].tap()
    XCTAssertTrue(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 3))
    app.buttons["WorkoutHistoryButton-0"].tap()
    let deleteButton = app.buttons["Delete Workout"]
    for _ in 0..<4 where !deleteButton.exists || !deleteButton.isHittable {
        app.swipeUp()
    }
    XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
    deleteButton.tap()

    XCTAssertTrue(app.staticTexts["HistoryTitle"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["WorkoutHistoryButton-0"].waitForExistence(timeout: 1))
}
```

- [ ] **Step 3: Run targeted UI tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogUITests/LiftingLogUITests/testCompletedWorkoutCanBeOpenedFromWorkoutAndExerciseHistory -only-testing:LiftingLogUITests/LiftingLogUITests/testDeletingCompletedWorkoutRemovesItFromHistory
```

Expected: tests pass. If the existing finish-to-history test has a different name after implementation, run its actual test name.

- [ ] **Step 4: Commit UI tests**

Run:

```bash
git add LiftingLogUITests/LiftingLogUITests.swift
git commit -m "Add workout history deletion UI coverage"
```

Expected: commit succeeds.

---

### Task 11: Final Integration Verification

**Files:**
- Review all changed files.
- Modify only files needed to fix verification failures.

- [ ] **Step 1: Run full Convex verification**

Run:

```bash
pnpm run convex:test
pnpm run convex:typecheck
```

Expected: both commands pass.

- [ ] **Step 2: Run full XCTest suite**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: all unit and UI tests pass. If simulator destination is unavailable, use an available iPhone simulator from `xcodebuild -scheme LiftingLog -showdestinations`.

- [ ] **Step 3: Search for stale naming**

Run:

```bash
rg -n "SettingsExerciseSync|ConvexSettingsExerciseSync|FakeSettingsExerciseSync|fetchSettingsExerciseChanges" LiftingLog LiftingLogTests LiftingLogUITests
```

Expected: no matches.

- [ ] **Step 4: Search for active workout sync leaks**

Run:

```bash
rg -n "status == \\.active|status != \\.active|statusRaw" LiftingLog/Core/Sync LiftingLog/Features/Workout LiftingLogTests
```

Expected: coordinator code explicitly excludes active workout pushes and bootstrap only includes completed sessions.

- [ ] **Step 5: Review git diff**

Run:

```bash
git diff --stat
git diff -- LiftingLog/Core/Sync LiftingLogTests convex LiftingLogUITests
```

Expected: changes match this issue: sync rename, workout graph payload/client/coordinator behavior, tests, and narrowly related scheduler/UI sync request updates.

- [ ] **Step 6: Commit final fixes**

If verification required fixes, commit them:

```bash
git add LiftingLog LiftingLogTests LiftingLogUITests convex
git commit -m "Verify workout graph sync integration"
```

Expected: commit succeeds if there were final fixes. If no files changed after verification, skip this commit.

- [ ] **Step 7: Summarize manual QA**

Record these manual QA notes in the final implementation response:

```text
Manual QA still recommended on a real device or simulator pair:
- Finish offline, reconnect, sync.
- Reinstall or second device pull reconstructs workout history.
- Delete a synced workout and confirm deletion propagates.
- Finish then delete before sync and confirm no Convex record appears.
- Confirm active workouts do not appear in Convex.
```
