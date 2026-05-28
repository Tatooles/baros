# Exercise Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a focused active-workout exercise reorder flow through a sticky-header workout options menu and a draft-order sheet.

**Architecture:** Keep reorder persistence in `ActiveWorkoutEngine`, keep sheet-local draft state in a new `ReorderExercisesSheet`, and make `WorkoutHeaderView` expose a native SwiftUI `Menu` for workout-level actions. The feature preserves all existing `LoggedExercise` and `LoggedSet` objects by changing only visible exercise `orderIndex` values on `Done`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, XCUITest, native SwiftUI `Menu`, `List.onMove`, sheet detents.

---

## File Structure

- Modify `LiftingLog/Features/Workout/ActiveWorkoutEngine.swift`
  - Add `ActiveWorkoutEngineError.invalidExerciseReorder`.
  - Add `reorderLoggedExercises(in:orderedIDs:context:now:)`.
- Create `LiftingLog/Features/Workout/ReorderExercisesSheet.swift`
  - Own draft row state and visible drag handles.
  - Call the engine only from `Done`.
- Modify `LiftingLog/Features/Workout/WorkoutHeaderView.swift`
  - Replace the dedicated finish button with an icon-only native `Menu`.
  - Preserve finish behavior through a `Finish Workout` menu item.
- Modify `LiftingLog/Features/Workout/WorkoutSessionView.swift`
  - Add reorder sheet presentation state.
  - Pass menu callbacks and reorder availability into the header.
- Modify `LiftingLogTests/ActiveWorkoutEngineTests.swift`
  - Add unit coverage for valid reorder, preservation, invalid drafts, and tombstoned exercises.
- Modify `LiftingLogUITests/LiftingLogUITests.swift`
  - Update existing finish flows to use the menu.
  - Add a four-exercise reorder flow test.

---

### Task 1: Add Engine Reorder Tests

**Files:**
- Modify: `LiftingLogTests/ActiveWorkoutEngineTests.swift`
- Test command target: `LiftingLogTests/ActiveWorkoutEngineTests.swift`

- [ ] **Step 1: Add failing engine tests**

Insert these tests in `ActiveWorkoutEngineTests`, before the existing private helper methods:

```swift
    func testReorderingLoggedExercisesUpdatesVisibleOrderIndexes() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context, now: Date(timeIntervalSince1970: 100))
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        let deadlift = Exercise(name: "Conventional Deadlift", category: .strength, equipment: .barbell, primaryMuscle: "Posterior Chain")
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
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
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
        firstSet.placeholderWeight = 305
        firstSet.placeholderReps = 5
        firstSet.placeholderRPE = 7.5
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
        XCTAssertEqual(movedFirst.sortedSets[0].placeholderWeight, 305)
        XCTAssertEqual(movedFirst.sortedSets[0].placeholderReps, 5)
        XCTAssertEqual(movedFirst.sortedSets[0].placeholderRPE, 7.5)
        XCTAssertTrue(movedFirst.sortedSets[0].isCompleted)
    }

    func testReorderingLoggedExercisesRejectsInvalidIDsWithoutMutation() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let engine = ActiveWorkoutEngine()
        let session = try engine.startBlankWorkout(context: context)
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
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
        let squat = Exercise(name: "Back Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads")
        let bench = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        let deadlift = Exercise(name: "Conventional Deadlift", category: .strength, equipment: .barbell, primaryMuscle: "Posterior Chain")
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
```

- [ ] **Step 2: Run the engine tests and verify they fail**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/ActiveWorkoutEngineTests
```

Expected: FAIL because `ActiveWorkoutEngine.reorderLoggedExercises` and `ActiveWorkoutEngineError` do not exist.

- [ ] **Step 3: Commit the failing tests**

Run:

```bash
git add LiftingLogTests/ActiveWorkoutEngineTests.swift
git commit -m "test: cover active workout exercise reorder"
```

Expected: a commit containing only the failing engine tests.

---

### Task 2: Implement Engine Reorder API

**Files:**
- Modify: `LiftingLog/Features/Workout/ActiveWorkoutEngine.swift`
- Test: `LiftingLogTests/ActiveWorkoutEngineTests.swift`

- [ ] **Step 1: Add the reorder error type**

Add this enum after the imports and before `@Observable`:

```swift
enum ActiveWorkoutEngineError: LocalizedError, Equatable {
    case invalidExerciseReorder

    var errorDescription: String? {
        switch self {
        case .invalidExerciseReorder:
            return "Workout exercises changed. Review the current order and try again."
        }
    }
}
```

- [ ] **Step 2: Add the reorder method**

Add this method to `ActiveWorkoutEngine`, near `removeLoggedExercise(_:context:now:)`:

```swift
    func reorderLoggedExercises(
        in session: WorkoutSession,
        orderedIDs: [UUID],
        context: ModelContext,
        now: Date = .now
    ) throws {
        let visibleExercises = session.sortedLoggedExercises
        let visibleIDs = visibleExercises.map(\.id)
        guard orderedIDs.count == visibleIDs.count, Set(orderedIDs) == Set(visibleIDs) else {
            throw ActiveWorkoutEngineError.invalidExerciseReorder
        }

        let exercisesByID = Dictionary(uniqueKeysWithValues: visibleExercises.map { ($0.id, $0) })
        var didChangeOrder = false

        for (index, id) in orderedIDs.enumerated() {
            guard let loggedExercise = exercisesByID[id] else {
                throw ActiveWorkoutEngineError.invalidExerciseReorder
            }

            if loggedExercise.orderIndex != index {
                loggedExercise.orderIndex = index
                loggedExercise.touch(now: now)
                didChangeOrder = true
            }
        }

        if didChangeOrder {
            session.touch(now: now)
        }

        try context.save()
    }
```

- [ ] **Step 3: Run the engine tests and verify they pass**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/ActiveWorkoutEngineTests
```

Expected: PASS for `ActiveWorkoutEngineTests`.

- [ ] **Step 4: Commit the engine implementation**

Run:

```bash
git add LiftingLog/Features/Workout/ActiveWorkoutEngine.swift
git commit -m "feat: reorder active workout exercises"
```

Expected: a commit containing the engine error and reorder method.

---

### Task 3: Add Reorder Exercises Sheet

**Files:**
- Create: `LiftingLog/Features/Workout/ReorderExercisesSheet.swift`
- Test: `LiftingLogTests/ActiveWorkoutEngineTests.swift`

- [ ] **Step 1: Create the reorder sheet view**

Create `LiftingLog/Features/Workout/ReorderExercisesSheet.swift` with this content:

```swift
import SwiftData
import SwiftUI

private struct ReorderExerciseDraft: Identifiable, Equatable {
    let id: UUID
    let name: String
    let completedSets: Int
    let totalSets: Int

    init(loggedExercise: LoggedExercise) {
        let progress = ExerciseCardView.setProgress(for: loggedExercise)
        id = loggedExercise.id
        name = loggedExercise.exerciseSnapshotName
        completedSets = progress.completed
        totalSets = progress.total
    }

    var progressText: String {
        "\(completedSets)/\(totalSets) sets"
    }
}

struct ReorderExercisesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @State private var draftExercises: [ReorderExerciseDraft] = []
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                ForEach(draftExercises) { exercise in
                    HStack(spacing: 12) {
                        Text(exercise.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Text(exercise.progressText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ReorderExerciseRow-\(exercise.name)")
                }
                .onMove(perform: moveExercises)
            }
            .accessibilityIdentifier("ReorderExercisesList")
            .environment(\.editMode, $editMode)
            .navigationTitle("Reorder Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("CancelReorderExercisesButton")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveOrder()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(draftExercises.count < 2)
                    .accessibilityIdentifier("DoneReorderExercisesButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if draftExercises.isEmpty {
                draftExercises = session.sortedLoggedExercises.map(ReorderExerciseDraft.init)
            }
        }
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        draftExercises.move(fromOffsets: source, toOffset: destination)
    }

    private func saveOrder() {
        do {
            try engine.reorderLoggedExercises(
                in: session,
                orderedIDs: draftExercises.map(\.id),
                context: modelContext
            )
            dismiss()
        } catch {
            engine.lastErrorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Run a compile-focused test pass**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/ActiveWorkoutEngineTests
```

Expected: PASS, proving the new view compiles with the app target while the engine tests still pass.

- [ ] **Step 3: Commit the sheet**

Run:

```bash
git add LiftingLog/Features/Workout/ReorderExercisesSheet.swift
git commit -m "feat: add exercise reorder sheet"
```

Expected: a commit containing only the new sheet file.

---

### Task 4: Wire The Workout Options Menu

**Files:**
- Modify: `LiftingLog/Features/Workout/WorkoutHeaderView.swift`
- Modify: `LiftingLog/Features/Workout/WorkoutSessionView.swift`
- Create or update generated project membership if this repo requires it after adding `ReorderExercisesSheet.swift`.

- [ ] **Step 1: Update `WorkoutHeaderView` inputs**

Replace the existing stored properties:

```swift
    let elapsedSeconds: Int
    let completedSets: Int
    let totalSets: Int
    let onFinish: () -> Void
```

with:

```swift
    let elapsedSeconds: Int
    let completedSets: Int
    let totalSets: Int
    let canReorderExercises: Bool
    let onFinish: () -> Void
    let onReorderExercises: () -> Void
```

- [ ] **Step 2: Replace the finish button with a native menu**

In `WorkoutHeaderView.body`, replace the existing `Button(action: onFinish) { ... }` block with this menu:

```swift
            Menu {
                Button {
                    onFinish()
                } label: {
                    Label("Finish Workout", systemImage: "checkmark.circle")
                }

                Button {
                    onReorderExercises()
                } label: {
                    Label("Reorder Exercises", systemImage: "arrow.up.arrow.down")
                }
                .disabled(!canReorderExercises)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(AppTheme.borderStrong)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Workout options")
            .accessibilityIdentifier("WorkoutOptionsButton")
```

Keep the timer, set progress, header padding, material background, and bottom border unchanged.

- [ ] **Step 3: Add reorder presentation state to `WorkoutSessionView`**

Add this state property with the other sheet state:

```swift
    @State private var isReorderExercisesPresented = false
```

- [ ] **Step 4: Pass menu callbacks into the header**

Replace the current `WorkoutHeaderView` call in `WorkoutSessionView`:

```swift
                    WorkoutHeaderView(
                        elapsedSeconds: metrics.durationSeconds,
                        completedSets: metrics.completedSetCount,
                        totalSets: metrics.totalSetCount
                    ) {
                        isFinishSheetPresented = true
                    }
```

with:

```swift
                    WorkoutHeaderView(
                        elapsedSeconds: metrics.durationSeconds,
                        completedSets: metrics.completedSetCount,
                        totalSets: metrics.totalSetCount,
                        canReorderExercises: session.sortedLoggedExercises.count >= 2,
                        onFinish: {
                            isFinishSheetPresented = true
                        },
                        onReorderExercises: {
                            isReorderExercisesPresented = true
                        }
                    )
```

- [ ] **Step 5: Present the reorder sheet**

Add this sheet modifier in `WorkoutSessionView`, next to the existing sheet modifiers:

```swift
        .sheet(isPresented: $isReorderExercisesPresented) {
            ReorderExercisesSheet(session: session, engine: engine)
        }
```

- [ ] **Step 6: Add the new Swift file to the Xcode project if needed**

Run:

```bash
xcodebuild build -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS. If it fails with `cannot find 'ReorderExercisesSheet' in scope`, add `LiftingLog/Features/Workout/ReorderExercisesSheet.swift` to `LiftingLog.xcodeproj/project.pbxproj` using the existing project file pattern for nearby files in `LiftingLog/Features/Workout/`.

- [ ] **Step 7: Commit the menu wiring**

Run:

```bash
git add LiftingLog/Features/Workout/WorkoutHeaderView.swift LiftingLog/Features/Workout/WorkoutSessionView.swift LiftingLog.xcodeproj/project.pbxproj
git commit -m "feat: add workout options menu"
```

Expected: a commit containing the header menu wiring and project membership change only if the project file changed.

---

### Task 5: Update Existing UI Finish Flows

**Files:**
- Modify: `LiftingLogUITests/LiftingLogUITests.swift`

- [ ] **Step 1: Add helper methods for workout options and finish**

Add these helpers near the other private UI test helpers:

```swift
    @MainActor
    private func openWorkoutOptions(in app: XCUIApplication) {
        let optionsButton = app.buttons["WorkoutOptionsButton"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 3))
        optionsButton.tap()
    }

    @MainActor
    private func openFinishWorkoutSheet(in app: XCUIApplication) {
        openWorkoutOptions(in: app)
        let finishButton = app.buttons["Finish Workout"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 3))
        finishButton.tap()
    }
```

- [ ] **Step 2: Update direct finish button taps**

Replace each existing direct finish action:

```swift
        app.buttons["Finish"].tap()
```

and:

```swift
        app.buttons["FinishWorkoutButton"].tap()
```

with:

```swift
        openFinishWorkoutSheet(in: app)
```

The current file has direct finish taps in `testTabNavigationAndFinishSheetSmoke`, `testExerciseHistorySummaryUsesAvailableContentWidth`, `createCompletedBenchWorkout(in:title:)`, `assertCompletingClonedSetCommitsPlaceholdersAfterFocusing(fieldIdentifier:)`, and `assertClearingCompletedSetField(fieldIdentifier:expectedHistorySummary:)`.

- [ ] **Step 3: Run the updated UI smoke test**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogUITests/LiftingLogUITests/testTabNavigationAndFinishSheetSmoke
```

Expected: PASS and the existing finish sheet still appears through the menu.

- [ ] **Step 4: Commit the finish flow updates**

Run:

```bash
git add LiftingLogUITests/LiftingLogUITests.swift
git commit -m "test: use workout options menu for finish flows"
```

Expected: a commit containing only UI test updates for existing finish behavior.

---

### Task 6: Add Four-Exercise Reorder UI Test

**Files:**
- Modify: `LiftingLogUITests/LiftingLogUITests.swift`
- Test depends on: `ReorderExercisesSheet`, `WorkoutOptionsButton`

- [ ] **Step 1: Add the disabled reorder menu test**

Add this test near the other active workout flow tests:

```swift
    @MainActor
    func testWorkoutOptionsDisablesReorderWithOneExercise() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))
        addExercise("Bench Press, Strength • Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)

        openWorkoutOptions(in: app)

        let reorderButton = app.buttons["Reorder Exercises"]
        XCTAssertTrue(reorderButton.waitForExistence(timeout: 3))
        XCTAssertFalse(reorderButton.isEnabled)
    }
```

- [ ] **Step 2: Add the reorder UI test**

Add this test near the other active workout flow tests:

```swift
    @MainActor
    func testReorderingActiveWorkoutExercisesChangesCardOrder() {
        let app = makeApp()
        app.launch()

        app.buttons["StartBlankWorkoutButton"].tap()
        XCTAssertTrue(app.textFields["WorkoutTitle"].waitForExistence(timeout: 3))

        addExercise("Back Squat, Strength • Barbell • Quads", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("Bench Press, Strength • Barbell • Chest", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("Conventional Deadlift, Strength • Barbell • Posterior Chain", in: app)
        dismissKeyboardIfNeeded(in: app)
        addExercise("Overhead Press, Strength • Barbell • Shoulders", in: app)
        dismissKeyboardIfNeeded(in: app)

        XCTAssertEqual(app.buttons["ExerciseHeader-0"].label, "Back Squat, 0/1")
        XCTAssertEqual(app.buttons["ExerciseHeader-3"].label, "Overhead Press, 0/1")

        openWorkoutOptions(in: app)
        app.buttons["Reorder Exercises"].tap()

        let reorderList = app.collectionViews["ReorderExercisesList"]
        XCTAssertTrue(reorderList.waitForExistence(timeout: 3))

        let overheadRow = app.cells["ReorderExerciseRow-Overhead Press"]
        let backSquatRow = app.cells["ReorderExerciseRow-Back Squat"]
        XCTAssertTrue(overheadRow.waitForExistence(timeout: 3))
        XCTAssertTrue(backSquatRow.waitForExistence(timeout: 3))
        overheadRow.press(forDuration: 0.5, thenDragTo: backSquatRow)

        app.buttons["DoneReorderExercisesButton"].tap()

        XCTAssertTrue(app.buttons["ExerciseHeader-0"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["ExerciseHeader-0"].label, "Overhead Press, 0/1")
        XCTAssertEqual(app.buttons["ExerciseHeader-1"].label, "Back Squat, 0/1")
        XCTAssertEqual(app.buttons["ExerciseHeader-2"].label, "Bench Press, 0/1")
        XCTAssertEqual(app.buttons["ExerciseHeader-3"].label, "Conventional Deadlift, 0/1")
    }
```

- [ ] **Step 3: Run the disabled reorder menu test**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogUITests/LiftingLogUITests/testWorkoutOptionsDisablesReorderWithOneExercise
```

Expected: PASS. The test should add one exercise, open the workout options menu, and confirm `Reorder Exercises` exists but is disabled.

- [ ] **Step 4: Run the reorder UI test and verify behavior**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogUITests/LiftingLogUITests/testReorderingActiveWorkoutExercisesChangesCardOrder
```

Expected: PASS. The test should add four exercises, open the menu, reorder `Overhead Press` to the top, tap `Done`, and observe the active workout card order.

- [ ] **Step 5: Stabilize row lookup if XCTest exposes SwiftUI list rows as buttons**

If Step 4 fails because `app.cells["ReorderExerciseRow-Overhead Press"]` is not found, change the row lookups in the test to:

```swift
        let overheadRow = app.buttons["ReorderExerciseRow-Overhead Press"]
        let backSquatRow = app.buttons["ReorderExerciseRow-Back Squat"]
```

Run the same command again. Expected: PASS.

- [ ] **Step 6: Commit the reorder UI tests**

Run:

```bash
git add LiftingLogUITests/LiftingLogUITests.swift
git commit -m "test: cover active workout exercise reorder flow"
```

Expected: a commit containing the disabled one-exercise menu test, the new four-exercise reorder UI test, and any row lookup adjustment from Step 5.

---

### Task 7: Full Verification And Cleanup

**Files:**
- Check: all modified files
- Verify: unit tests, UI tests, git status

- [ ] **Step 1: Run focused unit tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogTests/ActiveWorkoutEngineTests
```

Expected: PASS.

- [ ] **Step 2: Run focused UI tests**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:LiftingLogUITests/LiftingLogUITests/testTabNavigationAndFinishSheetSmoke -only-testing:LiftingLogUITests/LiftingLogUITests/testWorkoutOptionsDisablesReorderWithOneExercise -only-testing:LiftingLogUITests/LiftingLogUITests/testReorderingActiveWorkoutExercisesChangesCardOrder
```

Expected: PASS.

- [ ] **Step 3: Run the full test suite**

Run:

```bash
xcodebuild test -scheme LiftingLog -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS for `LiftingLogTests` and `LiftingLogUITests`.

- [ ] **Step 4: Inspect the final diff**

Run:

```bash
git diff --stat HEAD~6..HEAD
git status --short --branch
```

Expected: the branch contains the design/spec commit plus implementation commits, and the worktree is clean.

- [ ] **Step 5: Record any simulator-specific caveat**

If a UI drag test is flaky only in the full suite but passes focused, record the exact failing command and simulator result in the final handoff. Keep the implementation unchanged unless the failure points to a real app bug.
