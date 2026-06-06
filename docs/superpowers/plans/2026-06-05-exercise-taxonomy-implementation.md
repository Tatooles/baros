# Exercise Taxonomy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace free-text exercise muscle metadata with controlled taxonomy, make equipment part of exercise identity, and preserve clear workout history for same-name equipment variants.

**Architecture:** Keep SwiftData storage based on raw strings with typed enum accessors for app code. Add metadata snapshot fields to `LoggedExercise`, update history grouping to use linked exercise identity or snapshot `name + equipment`, and keep Convex exercise taxonomy fields as flexible strings. UI changes are limited to pickers and secondary metadata text.

**Tech Stack:** SwiftUI, SwiftData, XCTest, XCUITest, Convex, Vitest.

**Before implementation:** Set reasoning level to low. The implementation is mechanical and test-driven; low reasoning is enough once this plan is open.

---

## Required Context

- Read `docs/superpowers/specs/2026-06-05-exercise-taxonomy-design.md`.
- Before editing Convex code, read `convex/_generated/ai/guidelines.md`.
- If using XcodeBuildMCP for build/test/run, first read the installed `xcodebuildmcp` skill as required by `AGENTS.md`.
- Use the existing test commands from `README.md`.

## File Structure

- Create `LiftingLog/Core/Domain/ExerciseMuscleGroup.swift`: controlled primary muscle taxonomy and legacy mapping helpers.
- Modify `LiftingLog/Core/Domain/ExerciseEquipment.swift`: add new equipment cases and labels.
- Modify `LiftingLog/Core/Models/Exercise.swift`: add `primaryMuscleGroupRaw`, typed accessor, metadata display helper, and `name + equipment` duplicate helper.
- Modify `LiftingLog/Core/Models/LoggedExercise.swift`: add metadata snapshot fields and fallback display helpers.
- Modify `LiftingLog/Core/Persistence/SeedDataService.swift`: seed exercises with `ExerciseMuscleGroup` values and migrate legacy raw values opportunistically.
- Modify exercise UI files under `LiftingLog/Features/Exercises`: picker-based primary muscle editing, metadata display, and duplicate validation.
- Modify workout/history UI files under `LiftingLog/Features/Workout` and `LiftingLog/Features/History`: show secondary metadata and update history matching.
- Modify Convex schema and validators in `convex/schema.ts`, `convex/sync/validators.ts`, and `convex/sync.test.ts`.
- Modify tests in `LiftingLogTests` and `LiftingLogUITests`.

---

### Task 1: Add Domain Taxonomy Types

**Files:**
- Create: `LiftingLog/Core/Domain/ExerciseMuscleGroup.swift`
- Modify: `LiftingLog/Core/Domain/ExerciseEquipment.swift`
- Test: `LiftingLogTests/ModelPersistenceTests.swift`

- [ ] **Step 1: Write failing domain tests**

Add tests near the existing exercise model tests in `LiftingLogTests/ModelPersistenceTests.swift`:

```swift
func testExerciseMuscleGroupDisplayNamesAndFallback() throws {
    XCTAssertEqual(ExerciseMuscleGroup.chest.displayName, "Chest")
    XCTAssertEqual(ExerciseMuscleGroup.upperBack.displayName, "Upper Back")
    XCTAssertEqual(ExerciseMuscleGroup.lowerBack.displayName, "Lower Back")
    XCTAssertEqual(ExerciseMuscleGroup.fullBody.displayName, "Full Body")
    XCTAssertEqual(ExerciseMuscleGroup(rawValue: "futureValue") ?? .other, .other)
}

func testExerciseMuscleGroupMapsLegacyValues() throws {
    XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Quads"), .quads)
    XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Rear Delts"), .shoulders)
    XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Abdominals"), .core)
    XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Lower Back"), .lowerBack)
    XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Unknown Muscle"), .other)
}

func testExpandedExerciseEquipmentDisplayNames() throws {
    XCTAssertEqual(ExerciseEquipment.smithMachine.displayName, "Smith Machine")
    XCTAssertEqual(ExerciseEquipment.resistanceBand.displayName, "Resistance Band")
    XCTAssertEqual(ExerciseEquipment.medicineBall.displayName, "Medicine Ball")
}
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogTests/ModelPersistenceTests -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: FAIL because `ExerciseMuscleGroup` and new equipment cases do not exist.

- [ ] **Step 3: Add `ExerciseMuscleGroup`**

Create `LiftingLog/Core/Domain/ExerciseMuscleGroup.swift`:

```swift
import Foundation

enum ExerciseMuscleGroup: String, CaseIterable, Codable, Identifiable {
    case chest
    case lats
    case upperBack
    case traps
    case lowerBack
    case shoulders
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case abductors
    case adductors
    case calves
    case core
    case neck
    case fullBody
    case cardio
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .lats: return "Lats"
        case .upperBack: return "Upper Back"
        case .traps: return "Traps"
        case .lowerBack: return "Lower Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .abductors: return "Abductors"
        case .adductors: return "Adductors"
        case .calves: return "Calves"
        case .core: return "Core"
        case .neck: return "Neck"
        case .fullBody: return "Full Body"
        case .cardio: return "Cardio"
        case .other: return "Other"
        }
    }

    static func legacyGroup(for rawValue: String) -> ExerciseMuscleGroup {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "quads", "quadriceps": return .quads
        case "hamstrings": return .hamstrings
        case "posterior chain": return .glutes
        case "chest", "pecs", "pectorals": return .chest
        case "back", "upper back": return .upperBack
        case "lats", "latissimus dorsi": return .lats
        case "traps", "trapezius": return .traps
        case "lower back", "spinal erectors", "erectors": return .lowerBack
        case "rear delts", "rear deltoids", "shoulders", "delts": return .shoulders
        case "biceps": return .biceps
        case "triceps": return .triceps
        case "forearms": return .forearms
        case "abductors", "hip abductors": return .abductors
        case "adductors", "hip adductors": return .adductors
        case "calves": return .calves
        case "core", "abs", "abdominals": return .core
        case "neck": return .neck
        case "full body", "full-body": return .fullBody
        case "cardio": return .cardio
        default: return .other
        }
    }
}
```

- [ ] **Step 4: Expand `ExerciseEquipment`**

Update `LiftingLog/Core/Domain/ExerciseEquipment.swift`:

```swift
import Foundation

enum ExerciseEquipment: String, CaseIterable, Codable, Identifiable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case kettlebell
    case smithMachine
    case resistanceBand
    case medicineBall
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine"
        case .cable: return "Cable"
        case .bodyweight: return "Bodyweight"
        case .kettlebell: return "Kettlebell"
        case .smithMachine: return "Smith Machine"
        case .resistanceBand: return "Resistance Band"
        case .medicineBall: return "Medicine Ball"
        case .other: return "Other"
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run the same `xcodebuild test` command from Step 2.

Expected: PASS for the new domain tests. Existing tests may still fail later because call sites still use `primaryMuscle: String`; that is handled in the next task.

- [ ] **Step 6: Commit**

```bash
git add LiftingLog/Core/Domain/ExerciseMuscleGroup.swift LiftingLog/Core/Domain/ExerciseEquipment.swift LiftingLogTests/ModelPersistenceTests.swift
git commit -m "Add exercise taxonomy domain types"
```

---

### Task 2: Update Exercise And LoggedExercise Models

**Files:**
- Modify: `LiftingLog/Core/Models/Exercise.swift`
- Modify: `LiftingLog/Core/Models/LoggedExercise.swift`
- Test: `LiftingLogTests/ModelPersistenceTests.swift`

- [ ] **Step 1: Write failing model tests**

Add tests in `LiftingLogTests/ModelPersistenceTests.swift`:

```swift
func testExercisePersistsPrimaryMuscleGroupAndMetadataDisplay() throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let exercise = Exercise(
        name: "Bench Press",
        category: .strength,
        equipment: .barbell,
        primaryMuscleGroup: .chest
    )

    context.insert(exercise)
    try context.save()

    let id = exercise.id
    let fetched = try XCTUnwrap(
        context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first
    )
    XCTAssertEqual(fetched.primaryMuscleGroup, .chest)
    XCTAssertEqual(fetched.primaryMuscleGroupRaw, "chest")
    XCTAssertEqual(fetched.metadataDisplayText, "Barbell • Chest")
}

func testExerciseUnknownPrimaryMuscleGroupFallsBackToOther() throws {
    let exercise = Exercise(
        name: "Mystery Lift",
        category: .strength,
        equipment: .other,
        primaryMuscleGroup: .other
    )
    exercise.primaryMuscleGroupRaw = "futureGroup"

    XCTAssertEqual(exercise.primaryMuscleGroup, .other)
    XCTAssertEqual(exercise.primaryMuscleGroupRaw, "futureGroup")
    XCTAssertEqual(exercise.metadataDisplayText, "Other • Other")
}

func testLoggedExerciseSnapshotsExerciseMetadata() throws {
    let exercise = Exercise(
        name: "Bench Press",
        category: .strength,
        equipment: .barbell,
        primaryMuscleGroup: .chest
    )
    let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise)

    XCTAssertEqual(loggedExercise.exerciseSnapshotName, "Bench Press")
    XCTAssertEqual(loggedExercise.exerciseSnapshotEquipmentRaw, "barbell")
    XCTAssertEqual(loggedExercise.exerciseSnapshotPrimaryMuscleGroupRaw, "chest")
    XCTAssertEqual(loggedExercise.metadataDisplayText, "Barbell • Chest")
}
```

- [ ] **Step 2: Run failing model tests**

Run:

```bash
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogTests/ModelPersistenceTests -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: FAIL because model fields and initializers are not updated.

- [ ] **Step 3: Update `Exercise` model**

Modify `LiftingLog/Core/Models/Exercise.swift`. Keep `primaryMuscleRaw` as a legacy migration source for existing local stores, but make `primaryMuscleGroupRaw` the app-facing value.

Key shape:

```swift
@Model
final class Exercise: Identifiable {
    @Attribute(.unique) var id: UUID
    var seedIdentifier: String?
    var name: String
    var categoryRaw: String
    var equipmentRaw: String
    var primaryMuscleRaw: String = ""
    var primaryMuscleGroupRaw: String = ExerciseMuscleGroup.other.rawValue
    var notes: String
    var isArchived: Bool
    var isSeeded: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        seedIdentifier: String? = nil,
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscleGroup: ExerciseMuscleGroup,
        notes: String = "",
        isArchived: Bool = false,
        isSeeded: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.seedIdentifier = seedIdentifier
        self.name = name
        self.categoryRaw = category.rawValue
        self.equipmentRaw = equipment.rawValue
        self.primaryMuscleRaw = primaryMuscleGroup.displayName
        self.primaryMuscleGroupRaw = primaryMuscleGroup.rawValue
        self.notes = notes
        self.isArchived = isArchived
        self.isSeeded = isSeeded
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var primaryMuscleGroup: ExerciseMuscleGroup {
        get { ExerciseMuscleGroup(rawValue: primaryMuscleGroupRaw) ?? .other }
        set {
            primaryMuscleGroupRaw = newValue.rawValue
            primaryMuscleRaw = newValue.displayName
            touch()
        }
    }

    var metadataDisplayText: String {
        "\(equipment.displayName) • \(primaryMuscleGroup.displayName)"
    }

    func hasSameActiveIdentity(name normalizedName: String, equipment candidateEquipment: ExerciseEquipment) -> Bool {
        !isArchived
            && !isDeleted
            && name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(normalizedName) == .orderedSame
            && equipment == candidateEquipment
    }

    func update(
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscleGroup: ExerciseMuscleGroup,
        notes: String
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.equipmentRaw = equipment.rawValue
        self.primaryMuscleGroupRaw = primaryMuscleGroup.rawValue
        self.primaryMuscleRaw = primaryMuscleGroup.displayName
        self.notes = notes
        touch()
    }
}
```

Preserve existing methods not shown in the snippet: `visibleActiveExercises`, `isDeleted`, `category`, `equipment`, `archive`, `archiveOrDelete`, `touch`, `markDeleted`, and `restoreFromDeletion`.

- [ ] **Step 4: Update `LoggedExercise` model**

Modify `LiftingLog/Core/Models/LoggedExercise.swift`:

```swift
@Model
final class LoggedExercise: Identifiable {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var exerciseSnapshotName: String
    var exerciseSnapshotEquipmentRaw: String = ExerciseEquipment.other.rawValue
    var exerciseSnapshotPrimaryMuscleGroupRaw: String = ExerciseMuscleGroup.other.rawValue
    var notes: String
    var referenceNotes: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var exercise: Exercise?
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.loggedExercise) var sets: [LoggedSet]

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        exercise: Exercise? = nil,
        exerciseSnapshotName: String? = nil,
        exerciseSnapshotEquipmentRaw: String? = nil,
        exerciseSnapshotPrimaryMuscleGroupRaw: String? = nil,
        notes: String = "",
        referenceNotes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        sets: [LoggedSet] = []
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exercise = exercise
        self.exerciseSnapshotName = exerciseSnapshotName ?? exercise?.name ?? "Exercise"
        self.exerciseSnapshotEquipmentRaw = exerciseSnapshotEquipmentRaw ?? exercise?.equipmentRaw ?? ExerciseEquipment.other.rawValue
        self.exerciseSnapshotPrimaryMuscleGroupRaw = exerciseSnapshotPrimaryMuscleGroupRaw ?? exercise?.primaryMuscleGroupRaw ?? ExerciseMuscleGroup.other.rawValue
        self.notes = notes
        self.referenceNotes = referenceNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sets = sets

        for set in sets {
            set.loggedExercise = self
        }
    }

    var snapshotEquipment: ExerciseEquipment {
        ExerciseEquipment(rawValue: exerciseSnapshotEquipmentRaw) ?? .other
    }

    var snapshotPrimaryMuscleGroup: ExerciseMuscleGroup {
        ExerciseMuscleGroup(rawValue: exerciseSnapshotPrimaryMuscleGroupRaw) ?? .other
    }

    var metadataDisplayText: String {
        "\(snapshotEquipment.displayName) • \(snapshotPrimaryMuscleGroup.displayName)"
    }
}
```

Preserve existing methods and computed properties not shown.

- [ ] **Step 5: Update obvious compile errors**

Run:

```bash
rg "primaryMuscle:" LiftingLog LiftingLogTests
```

For each match, change the argument to `primaryMuscleGroup: .<group>`. Use `.chest`, `.quads`, `.hamstrings`, `.upperBack`, `.lats`, `.shoulders`, `.biceps`, `.triceps`, `.calves`, `.core`, or `.glutes` based on the current string.

- [ ] **Step 6: Run model tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add LiftingLog/Core/Models/Exercise.swift LiftingLog/Core/Models/LoggedExercise.swift LiftingLogTests/ModelPersistenceTests.swift LiftingLogTests
git commit -m "Update exercise models for taxonomy metadata"
```

---

### Task 3: Update Seed Data And Legacy Mapping

**Files:**
- Modify: `LiftingLog/Core/Persistence/SeedDataService.swift`
- Test: `LiftingLogTests/SeedDataServiceTests.swift`

- [ ] **Step 1: Write failing seed tests**

Add to `LiftingLogTests/SeedDataServiceTests.swift`:

```swift
func testSeedServiceUsesControlledPrimaryMuscleGroups() throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext

    try SeedDataService.seedIfNeeded(context: context)

    let exercises = try context.fetch(FetchDescriptor<Exercise>())
    XCTAssertEqual(exercises.first { $0.seedIdentifier == "back-squat" }?.primaryMuscleGroup, .quads)
    XCTAssertEqual(exercises.first { $0.seedIdentifier == "conventional-deadlift" }?.primaryMuscleGroup, .glutes)
    XCTAssertEqual(exercises.first { $0.seedIdentifier == "pull-up" }?.primaryMuscleGroup, .lats)
    XCTAssertEqual(exercises.first { $0.seedIdentifier == "barbell-row" }?.primaryMuscleGroup, .upperBack)
    XCTAssertEqual(exercises.first { $0.seedIdentifier == "face-pull" }?.primaryMuscleGroup, .shoulders)
}

func testSeedServiceMigratesLegacyPrimaryMuscleStrings() throws {
    let container = try SwiftDataTestSupport.makeInMemoryContainer()
    let context = container.mainContext
    let exercise = Exercise(
        name: "Legacy Face Pull",
        category: .strength,
        equipment: .cable,
        primaryMuscleGroup: .other
    )
    exercise.primaryMuscleRaw = "Rear Delts"
    exercise.primaryMuscleGroupRaw = ExerciseMuscleGroup.other.rawValue
    context.insert(exercise)

    try SeedDataService.seedIfNeeded(context: context)

    XCTAssertEqual(exercise.primaryMuscleGroup, .shoulders)
}
```

- [ ] **Step 2: Run failing seed tests**

```bash
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogTests/SeedDataServiceTests -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: FAIL until seed data and migration are updated.

- [ ] **Step 3: Update seed structure**

In `LiftingLog/Core/Persistence/SeedDataService.swift`, change `ExerciseSeed.primaryMuscle` to `primaryMuscleGroup: ExerciseMuscleGroup`, and insert exercises with `primaryMuscleGroup`.

Use this seed list:

```swift
static let exerciseSeeds: [ExerciseSeed] = [
    ExerciseSeed("back-squat", "Back Squat", .strength, .barbell, .quads),
    ExerciseSeed("front-squat", "Front Squat", .strength, .barbell, .quads),
    ExerciseSeed("romanian-deadlift", "Romanian Deadlift", .strength, .barbell, .hamstrings),
    ExerciseSeed("conventional-deadlift", "Conventional Deadlift", .strength, .barbell, .glutes),
    ExerciseSeed("leg-press", "Leg Press", .strength, .machine, .quads),
    ExerciseSeed("leg-extension", "Leg Extension", .strength, .machine, .quads),
    ExerciseSeed("leg-curl", "Leg Curl", .strength, .machine, .hamstrings),
    ExerciseSeed("bench-press", "Bench Press", .strength, .barbell, .chest),
    ExerciseSeed("incline-dumbbell-press", "Incline Dumbbell Press", .strength, .dumbbell, .chest),
    ExerciseSeed("overhead-press", "Overhead Press", .strength, .barbell, .shoulders),
    ExerciseSeed("pull-up", "Pull-Up", .strength, .bodyweight, .lats),
    ExerciseSeed("lat-pulldown", "Lat Pulldown", .strength, .cable, .lats),
    ExerciseSeed("barbell-row", "Barbell Row", .strength, .barbell, .upperBack),
    ExerciseSeed("seated-cable-row", "Seated Cable Row", .strength, .cable, .upperBack),
    ExerciseSeed("dumbbell-row", "Dumbbell Row", .strength, .dumbbell, .upperBack),
    ExerciseSeed("face-pull", "Face Pull", .strength, .cable, .shoulders),
    ExerciseSeed("biceps-curl", "Biceps Curl", .strength, .dumbbell, .biceps),
    ExerciseSeed("triceps-pushdown", "Triceps Pushdown", .strength, .cable, .triceps),
    ExerciseSeed("calf-raise", "Calf Raise", .strength, .machine, .calves),
    ExerciseSeed("plank", "Plank", .strength, .bodyweight, .core)
]
```

- [ ] **Step 4: Add opportunistic legacy migration**

Call this from `seedIfNeeded(context:)` before `context.save()`:

```swift
private static func migrateLegacyPrimaryMuscleGroups(context: ModelContext) throws {
    let exercises = try context.fetch(FetchDescriptor<Exercise>())

    for exercise in exercises where exercise.primaryMuscleGroup == .other {
        let migrated = ExerciseMuscleGroup.legacyGroup(for: exercise.primaryMuscleRaw)
        if migrated != .other {
            exercise.primaryMuscleGroupRaw = migrated.rawValue
            exercise.primaryMuscleRaw = migrated.displayName
            exercise.touch()
        }
    }
}
```

Ensure `seedIfNeeded(context:)` calls:

```swift
try ensureSettings(context: context)
try ensureExercises(context: context)
try migrateLegacyPrimaryMuscleGroups(context: context)
try ensureSeedMetadata(context: context)
try context.save()
```

- [ ] **Step 5: Run seed tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add LiftingLog/Core/Persistence/SeedDataService.swift LiftingLogTests/SeedDataServiceTests.swift
git commit -m "Migrate seed data to muscle groups"
```

---

### Task 4: Update Exercise Editor And Library UI

**Files:**
- Modify: `LiftingLog/Features/Exercises/ExerciseEditorView.swift`
- Modify: `LiftingLog/Features/Exercises/ExerciseLibraryView.swift`
- Modify: `LiftingLog/Features/Exercises/ExercisePickerView.swift`
- Test: `LiftingLogUITests/LiftingLogUITests.swift`

- [ ] **Step 1: Write failing UI test for same-name equipment variants**

Add this new test beside `testExerciseLibraryCreateEditAndRemoveCustomExercise`:

```swift
@MainActor
func testExerciseLibraryAllowsSameNameWithDifferentEquipmentAndRejectsExactDuplicate() {
    let app = makeApp()
    app.launch()

    app.buttons["ProfileTab"].tap()
    app.buttons["ProfileExerciseLibraryLink"].tap()
    XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3))

    createExercise(name: "Variant Press", equipment: "Barbell", muscle: "Chest", in: app)
    createExercise(name: "Variant Press", equipment: "Dumbbell", muscle: "Chest", in: app)

    XCTAssertTrue(app.buttons["ExerciseLibraryRow-Variant Press-Barbell"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["ExerciseLibraryRow-Variant Press-Dumbbell"].waitForExistence(timeout: 3))

    app.buttons["CreateExerciseButton"].tap()
    XCTAssertTrue(app.navigationBars["Create Exercise"].waitForExistence(timeout: 3))
    app.textFields["ExerciseNameField"].tap()
    app.textFields["ExerciseNameField"].typeText("Variant Press")
    selectPickerValue(identifier: "ExerciseEquipmentPicker", value: "Barbell", in: app)
    selectPickerValue(identifier: "ExercisePrimaryMuscleGroupPicker", value: "Chest", in: app)
    app.buttons["ExerciseEditorSaveButton"].tap()

    XCTAssertTrue(app.staticTexts["An active exercise with that name and equipment already exists."].waitForExistence(timeout: 3))
}
```

Add helper functions at the bottom of `LiftingLogUITests.swift`:

```swift
@MainActor
private func createExercise(name: String, equipment: String, muscle: String, in app: XCUIApplication) {
    app.buttons["CreateExerciseButton"].tap()
    XCTAssertTrue(app.navigationBars["Create Exercise"].waitForExistence(timeout: 3))
    app.textFields["ExerciseNameField"].tap()
    app.textFields["ExerciseNameField"].typeText(name)
    selectPickerValue(identifier: "ExerciseEquipmentPicker", value: equipment, in: app)
    selectPickerValue(identifier: "ExercisePrimaryMuscleGroupPicker", value: muscle, in: app)
    app.buttons["ExerciseEditorSaveButton"].tap()
}

@MainActor
private func selectPickerValue(identifier: String, value: String, in app: XCUIApplication) {
    let picker = app.buttons[identifier]
    if picker.waitForExistence(timeout: 1) {
        picker.tap()
        app.buttons[value].tap()
        return
    }

    let segmentedPicker = app.segmentedControls[identifier]
    if segmentedPicker.waitForExistence(timeout: 1) {
        segmentedPicker.buttons[value].tap()
        return
    }

    let staticValue = app.staticTexts[value]
    XCTAssertTrue(staticValue.waitForExistence(timeout: 3))
    staticValue.tap()
}
```

- [ ] **Step 2: Run failing UI test**

```bash
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogUITests/LiftingLogUITests/testExerciseLibraryAllowsSameNameWithDifferentEquipmentAndRejectsExactDuplicate -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: FAIL because the editor still has a free-text primary muscle field and duplicate validation is name-only.

- [ ] **Step 3: Update `ExerciseEditorView` state and form**

Change `primaryMuscle: String` state to:

```swift
@State private var primaryMuscleGroup: ExerciseMuscleGroup
```

Initialize it with:

```swift
_primaryMuscleGroup = State(initialValue: exercise?.primaryMuscleGroup ?? .chest)
```

Replace the primary muscle `TextField` with:

```swift
Picker("Primary Muscle", selection: $primaryMuscleGroup) {
    ForEach(ExerciseMuscleGroup.allCases) { muscleGroup in
        Text(muscleGroup.displayName).tag(muscleGroup)
    }
}
.accessibilityIdentifier("ExercisePrimaryMuscleGroupPicker")
```

Add identifiers to existing pickers:

```swift
.accessibilityIdentifier("ExerciseCategoryPicker")
.accessibilityIdentifier("ExerciseEquipmentPicker")
```

- [ ] **Step 4: Update duplicate validation and save**

Replace the duplicate check with:

```swift
let duplicate = exercises.contains { existing in
    existing.id != exercise?.id
        && existing.hasSameActiveIdentity(name: trimmedName, equipment: equipment)
}
guard !duplicate else {
    validationMessage = "An active exercise with that name and equipment already exists."
    return
}
```

Update save calls:

```swift
exercise.update(
    name: trimmedName,
    category: category,
    equipment: equipment,
    primaryMuscleGroup: primaryMuscleGroup,
    notes: notes
)
```

and:

```swift
let exercise = Exercise(
    name: trimmedName,
    category: category,
    equipment: equipment,
    primaryMuscleGroup: primaryMuscleGroup,
    notes: notes
)
```

- [ ] **Step 5: Update library and picker metadata**

In `ExerciseLibraryView`, use:

```swift
Text(exercise.metadataDisplayText)
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(.secondary)
```

Change row identifier:

```swift
.accessibilityIdentifier("ExerciseLibraryRow-\(exercise.name)-\(exercise.equipment.displayName)")
```

In `ExercisePickerView`, use:

```swift
Text(exercise.metadataDisplayText)
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(.secondary)
```

- [ ] **Step 6: Update UI test labels**

Existing picker labels such as:

```swift
"Bench Press, Strength • Barbell • Chest"
```

must become:

```swift
"Bench Press, Barbell • Chest"
```

Run this search and update labels based on actual accessibility labels after UI changes:

```bash
rg "Strength •|Posterior Chain|ExercisePrimaryMuscleField|ExerciseLibraryRow-" LiftingLogUITests
```

- [ ] **Step 7: Run UI test**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add LiftingLog/Features/Exercises/ExerciseEditorView.swift LiftingLog/Features/Exercises/ExerciseLibraryView.swift LiftingLog/Features/Exercises/ExercisePickerView.swift LiftingLogUITests/LiftingLogUITests.swift
git commit -m "Update exercise editor taxonomy UI"
```

---

### Task 5: Update Active Workout And History Matching

**Files:**
- Modify: `LiftingLog/Features/Workout/ActiveWorkoutEngine.swift`
- Modify: `LiftingLog/Features/Workout/ExerciseCardView.swift`
- Modify: `LiftingLog/Features/Workout/ReorderExercisesSheet.swift`
- Modify: `LiftingLog/Features/Workout/ExerciseQuickHistorySheet.swift`
- Modify: `LiftingLog/Features/History/ExerciseHistorySummary.swift`
- Modify: `LiftingLog/Features/History/ExerciseHistoryRoute.swift`
- Modify: `LiftingLog/Features/History/ExerciseHistorySessionGroup.swift`
- Modify: `LiftingLog/Features/History/ExerciseHistoryRow.swift`
- Modify: `LiftingLog/Features/History/ExerciseHistorySessionGroupCard.swift`
- Modify: `LiftingLog/Features/History/WorkoutHistoryDetailView.swift`
- Test: `LiftingLogTests/HistoryPersistenceTests.swift`
- Test: `LiftingLogUITests/LiftingLogUITests.swift`

- [ ] **Step 1: Write failing history unit tests**

Add to `LiftingLogTests/HistoryPersistenceTests.swift`:

```swift
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
    let barbellSession = WorkoutSession(title: "Barbell Push", startedAt: Date(timeIntervalSince1970: 100), status: .completed, source: .blank, loggedExercises: [barbell])
    let dumbbellSession = WorkoutSession(title: "Dumbbell Push", startedAt: Date(timeIntervalSince1970: 200), status: .completed, source: .blank, loggedExercises: [dumbbell])

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
        exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
        sets: [LoggedSet(orderIndex: 0, weight: 185, reps: 5, isCompleted: true)]
    )
    let nonMatchingLoggedExercise = LoggedExercise(
        orderIndex: 1,
        exerciseSnapshotName: "Bench Press",
        exerciseSnapshotEquipmentRaw: ExerciseEquipment.dumbbell.rawValue,
        exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.chest.rawValue,
        sets: [LoggedSet(orderIndex: 0, weight: 70, reps: 8, isCompleted: true)]
    )
    let session = WorkoutSession(
        title: "Mixed Push",
        startedAt: Date(timeIntervalSince1970: 100),
        status: .completed,
        source: .blank,
        loggedExercises: [matchingLoggedExercise, nonMatchingLoggedExercise]
    )

    let groups = ExerciseHistorySessionGroup.makeGroups(from: [session], matching: summary)

    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups.first?.setEntries.count, 1)
    XCTAssertEqual(groups.first?.setEntries.first?.loggedExercise.exerciseSnapshotEquipmentRaw, "barbell")
}
```

- [ ] **Step 2: Run failing history tests**

```bash
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogTests/HistoryPersistenceTests -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: FAIL because summaries do not carry equipment metadata and fallback grouping is name-only.

- [ ] **Step 3: Update active workout snapshot creation**

In `LiftingLog/Features/Workout/ActiveWorkoutEngine.swift`, change `addExercise` to rely on the updated `LoggedExercise(orderIndex:exercise:)` initializer:

```swift
let loggedExercise = LoggedExercise(orderIndex: nextIndex, exercise: exercise)
```

When cloning from past workouts, copy snapshot metadata:

```swift
LoggedExercise(
    orderIndex: index,
    exercise: pastLoggedExercise.exercise,
    exerciseSnapshotName: pastLoggedExercise.exerciseSnapshotName,
    exerciseSnapshotEquipmentRaw: pastLoggedExercise.exerciseSnapshotEquipmentRaw,
    exerciseSnapshotPrimaryMuscleGroupRaw: pastLoggedExercise.exerciseSnapshotPrimaryMuscleGroupRaw,
    referenceNotes: pastLoggedExercise.notes
)
```

- [ ] **Step 4: Update route and summary types**

Update `ExerciseHistoryRoute`:

```swift
struct ExerciseHistoryRoute: Hashable, Identifiable {
    let exerciseID: UUID?
    let name: String
    let equipmentRaw: String

    var id: String {
        if let exerciseID {
            return "exercise-\(exerciseID.uuidString)"
        }

        return "snapshot-\(name.lowercased())-\(equipmentRaw.lowercased())"
    }

    init(exerciseID: UUID?, name: String, equipmentRaw: String) {
        self.exerciseID = exerciseID
        self.name = name
        self.equipmentRaw = equipmentRaw
    }

    init(summary: ExerciseHistorySummary) {
        self.init(exerciseID: summary.exerciseID, name: summary.name, equipmentRaw: summary.equipmentRaw)
    }

    init(loggedExercise: LoggedExercise) {
        self.init(
            exerciseID: loggedExercise.exercise?.id,
            name: loggedExercise.exerciseSnapshotName,
            equipmentRaw: loggedExercise.exerciseSnapshotEquipmentRaw
        )
    }
}
```

Update `ExerciseHistorySummary` fields:

```swift
var equipmentRaw: String
var primaryMuscleGroupRaw: String

var metadataDisplayText: String {
    let equipment = ExerciseEquipment(rawValue: equipmentRaw) ?? .other
    let muscleGroup = ExerciseMuscleGroup(rawValue: primaryMuscleGroupRaw) ?? .other
    return "\(equipment.displayName) • \(muscleGroup.displayName)"
}
```

In `makeSummaries`, key linked exercises by `exercise.id` and fallback snapshots by normalized `exerciseSnapshotName + exerciseSnapshotEquipmentRaw`.

In `find(in:matching:)`, match linked routes by `exerciseID`; fallback routes by case-insensitive `name` and exact `equipmentRaw`.

- [ ] **Step 5: Update session group matching**

In `ExerciseHistorySessionGroup.matches`, use:

```swift
if let exerciseID = summary.exerciseID {
    return loggedExercise.exercise?.id == exerciseID
}

return loggedExercise.exerciseSnapshotName.caseInsensitiveCompare(summary.name) == .orderedSame
    && loggedExercise.exerciseSnapshotEquipmentRaw == summary.equipmentRaw
```

For testing, either make `matches` internal:

```swift
static func matchesForTesting(_ loggedExercise: LoggedExercise, summary: ExerciseHistorySummary) -> Bool {
    matches(loggedExercise, summary: summary)
}
```

or avoid this helper and assert through public grouping.

- [ ] **Step 6: Update metadata display in workout/history views**

In `ExerciseCardView`, replace the title-only header with a vertical stack:

```swift
VStack(alignment: .leading, spacing: 2) {
    Text(loggedExercise.exerciseSnapshotName)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(AppTheme.textPrimary)
    Text(loggedExercise.metadataDisplayText)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(AppTheme.textSecondary)
        .lineLimit(1)
}
```

In `WorkoutHistoryDetailView`, show:

```swift
Text(loggedExercise.exerciseSnapshotName)
    .font(.system(size: 18, weight: .bold))
Text(loggedExercise.metadataDisplayText)
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(AppTheme.textSecondary)
    .lineLimit(1)
```

In exercise history summary rows, show `summary.metadataDisplayText` as secondary text under the exercise name. In session group cards and workout history detail rows, show `loggedExercise.metadataDisplayText` as secondary text under the logged exercise name.

- [ ] **Step 7: Write failing UI test for active history separation**

Add to `LiftingLogUITests/LiftingLogUITests.swift`:

```swift
@MainActor
func testActiveWorkoutHistorySeparatesSameNameDifferentEquipment() {
    let app = makeApp()
    app.launch()

    app.buttons["ProfileTab"].tap()
    app.buttons["ProfileExerciseLibraryLink"].tap()
    XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3))
    createExercise(name: "Variant Bench", equipment: "Barbell", muscle: "Chest", in: app)
    createExercise(name: "Variant Bench", equipment: "Dumbbell", muscle: "Chest", in: app)
    app.navigationBars.buttons.element(boundBy: 0).tap()

    createCompletedWorkout(exerciseButtonLabel: "Variant Bench, Barbell • Chest", title: "Barbell Variant", weight: "185", reps: "5", rpe: "8", in: app)
    createCompletedWorkout(exerciseButtonLabel: "Variant Bench, Dumbbell • Chest", title: "Dumbbell Variant", weight: "70", reps: "8", rpe: "7", in: app)

    app.buttons["WorkoutTab"].tap()
    app.buttons["StartBlankWorkoutButton"].tap()
    XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
    addExercise("Variant Bench, Dumbbell • Chest", in: app)
    dismissKeyboardIfNeeded(in: app)
    app.buttons["ExerciseHistoryButton-0"].tap()

    XCTAssertTrue(app.staticTexts["Dumbbell Variant"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["Barbell Variant"].exists)
}
```

Add helper:

```swift
@MainActor
private func createCompletedWorkout(
    exerciseButtonLabel: String,
    title: String,
    weight: String,
    reps: String,
    rpe: String,
    in app: XCUIApplication
) {
    app.buttons["WorkoutTab"].tap()
    app.buttons["StartBlankWorkoutButton"].tap()
    XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
    replaceText(in: app.textFields["WorkoutTitle"], with: title)
    addExercise(exerciseButtonLabel, in: app)
    app.textFields["SetWeightField-0-0"].tap()
    app.textFields["SetWeightField-0-0"].typeText(weight)
    app.textFields["SetRepsField-0-0"].tap()
    app.textFields["SetRepsField-0-0"].typeText(reps)
    app.textFields["SetRPEField-0-0"].tap()
    app.textFields["SetRPEField-0-0"].typeText(rpe)
    app.buttons["SetCompletionButton-0-0"].tap()
    dismissKeyboardIfNeeded(in: app)
    openFinishWorkoutSheet(in: app)
    XCTAssertTrue(app.buttons["SaveWorkoutButton"].waitForExistence(timeout: 3))
    app.buttons["SaveWorkoutButton"].tap()
    XCTAssertTrue(app.staticTexts["StartWorkoutTitle"].waitForExistence(timeout: 3))
}
```

- [ ] **Step 8: Run history unit and focused UI tests**

```bash
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogTests/HistoryPersistenceTests -derivedDataPath /private/tmp/codex-ios-app-derived-data
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogUITests/LiftingLogUITests/testActiveWorkoutHistorySeparatesSameNameDifferentEquipment -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add LiftingLog/Features/Workout LiftingLog/Features/History LiftingLogTests/HistoryPersistenceTests.swift LiftingLogUITests/LiftingLogUITests.swift
git commit -m "Separate exercise history by equipment"
```

---

### Task 6: Update Convex Schema And Sync Validators

**Files:**
- Read first: `convex/_generated/ai/guidelines.md`
- Modify: `convex/schema.ts`
- Modify: `convex/sync/validators.ts`
- Modify: `convex/sync.test.ts`

- [ ] **Step 1: Read Convex guidelines**

Run:

```bash
sed -n '1,220p' convex/_generated/ai/guidelines.md
```

Expected: review the rules before editing Convex code.

- [ ] **Step 2: Write failing Convex sync test updates**

Update the helper record in `convex/sync.test.ts`:

```ts
function exerciseRecord(overrides: Partial<ExerciseRecord> = {}): ExerciseRecord {
  return {
    clientId: "exercise-1",
    seedIdentifier: null,
    name: "Bench Press",
    categoryRaw: "strength",
    equipmentRaw: "barbell",
    primaryMuscleRaw: "Chest",
    primaryMuscleGroupRaw: "chest",
    notes: "",
    isArchived: false,
    isSeeded: false,
    createdAt: 1,
    updatedAt: 2,
    deletedAt: null,
    ...overrides,
  };
}
```

Update `ExerciseRecord`:

```ts
type ExerciseRecord = {
  clientId: string;
  seedIdentifier: string | null;
  name: string;
  categoryRaw: string;
  equipmentRaw: string;
  primaryMuscleRaw: string;
  primaryMuscleGroupRaw: string;
  notes: string;
  isArchived: boolean;
  isSeeded: boolean;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};
```

Add a test:

```ts
test("exercise sync accepts forward-compatible taxonomy strings", async () => {
  const t = testDb().withIdentity(userA);

  await t.mutation(api.sync.upsertExercise, {
    record: exerciseRecord({
      equipmentRaw: "futureEquipment",
      primaryMuscleGroupRaw: "futureMuscle",
    }),
  });

  const changes = await t.query(api.sync.fetchChanges, { cursors: zeroCursors });
  expect(changes.exercises[0]).toMatchObject({
    equipmentRaw: "futureEquipment",
    primaryMuscleGroupRaw: "futureMuscle",
  });
});
```

- [ ] **Step 3: Run failing Convex tests**

```bash
pnpm run convex:test
```

Expected: FAIL until schema and validators accept `primaryMuscleGroupRaw` and flexible equipment strings.

- [ ] **Step 4: Update schema and validators**

In `convex/schema.ts`, change exercise fields:

```ts
categoryRaw: v.string(),
equipmentRaw: v.string(),
primaryMuscleRaw: v.string(),
primaryMuscleGroupRaw: v.string(),
```

In `convex/sync/validators.ts`, change exercise payload fields the same way:

```ts
categoryRaw: v.string(),
equipmentRaw: v.string(),
primaryMuscleRaw: v.string(),
primaryMuscleGroupRaw: v.string(),
```

Keep `primaryMuscleRaw` for compatibility during this transition; the app-facing value is `primaryMuscleGroupRaw`.

- [ ] **Step 5: Run Convex tests and typecheck**

```bash
pnpm run convex:test
pnpm run convex:typecheck
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add convex/schema.ts convex/sync/validators.ts convex/sync.test.ts
git commit -m "Update Convex exercise taxonomy fields"
```

---

### Task 7: Full Verification And Cleanup

**Files:**
- Modify only the files already touched in Tasks 1-6 when a verification failure points to a concrete defect.

- [ ] **Step 1: Search for legacy API leftovers**

Run:

```bash
rg "primaryMuscle:|primaryMuscle\\)|ExercisePrimaryMuscleField|Posterior Chain|Strength •" LiftingLog LiftingLogTests LiftingLogUITests convex
```

Expected: no stale `primaryMuscle:` initializer labels, no deleted UI identifiers, and no old picker labels. `primaryMuscleRaw` may still appear as a legacy storage/sync field.

- [ ] **Step 2: Run Swift unit tests**

```bash
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogTests -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: PASS.

- [ ] **Step 3: Run UI tests**

```bash
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:LiftingLogUITests -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: PASS.

- [ ] **Step 4: Run Convex tests**

```bash
pnpm run convex:test
pnpm run convex:typecheck
```

Expected: PASS.

- [ ] **Step 5: Build app**

```bash
xcodebuild build -project LiftingLog.xcodeproj -scheme LiftingLog -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Expected: PASS.

- [ ] **Step 6: Commit final verification fixes**

If verification required a concrete fix, commit it:

```bash
git add LiftingLog LiftingLogTests LiftingLogUITests convex
git commit -m "Polish exercise taxonomy implementation"
```

If verification passed without code changes, run `git status --short` and confirm that it prints no output.

---

## Completion Criteria

- Exercise editor uses controlled primary muscle group picker.
- Equipment includes Smith Machine, Resistance Band, and Medicine Ball.
- Same exercise name can exist with different equipment.
- Same exercise name and same equipment is rejected for active exercises.
- Exercise-focused rows show `Equipment • Primary Muscle Group` secondary metadata.
- Logged exercises snapshot name, equipment, and primary muscle group.
- Active workout history for same-name variants is separated by linked exercise or snapshot `name + equipment`.
- Convex accepts flexible raw taxonomy strings and includes `primaryMuscleGroupRaw`.
- Focused Swift, UI, and Convex tests pass.
