import XCTest
@testable import Baros

final class ExercisePickerContentTests: XCTestCase {
    func testRecentSortPlacesLatestPerformanceFirstAndNeverPerformedLast() {
        let benchPress = exercise(named: "Bench Press")
        let backSquat = exercise(named: "Back Squat", muscleGroup: .quads)
        let bicepsCurl = exercise(
            named: "Biceps Curl",
            equipment: .dumbbell,
            muscleGroup: .biceps
        )
        let olderBenchSession = completedSession(
            title: "Push",
            startedAt: Date(timeIntervalSince1970: 100),
            exercise: benchPress
        )
        let newerSquatSession = completedSession(
            title: "Legs",
            startedAt: Date(timeIntervalSince1970: 200),
            exercise: backSquat
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [benchPress, backSquat, bicepsCurl],
            sessions: [olderBenchSession, newerSquatSession],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .recent
        )

        XCTAssertEqual(rows.map(\.exercise.name), ["Back Squat", "Bench Press", "Biceps Curl"])
        XCTAssertEqual(rows.map(\.performanceCount), [1, 1, 0])
        XCTAssertNil(rows.last?.lastPerformedAt)
    }

    func testRecentSortUsesNameForEqualDatesAndAlphabetizesNeverPerformedExercises() {
        let alphaPress = exercise(named: "Alpha Press")
        let betaPress = exercise(named: "Beta Press")
        let cableCurl = exercise(named: "Cable Curl", equipment: .cable, muscleGroup: .biceps)
        let dumbbellCurl = exercise(named: "Dumbbell Curl", equipment: .dumbbell, muscleGroup: .biceps)
        let performedAt = Date(timeIntervalSince1970: 200)

        let rows = ExercisePickerContent.makeRows(
            exercises: [dumbbellCurl, betaPress, cableCurl, alphaPress],
            sessions: [
                completedSession(title: "Beta", startedAt: performedAt, exercise: betaPress),
                completedSession(title: "Alpha", startedAt: performedAt, exercise: alphaPress),
            ],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .recent
        )

        XCTAssertEqual(
            rows.map(\.exercise.name),
            ["Alpha Press", "Beta Press", "Cable Curl", "Dumbbell Curl"]
        )
    }

    func testMostPerformedSortUsesPerformanceCountThenRecencyThenName() {
        let benchPress = exercise(named: "Bench Press")
        let backSquat = exercise(named: "Back Squat", muscleGroup: .quads)
        let bicepsCurl = exercise(
            named: "Biceps Curl",
            equipment: .dumbbell,
            muscleGroup: .biceps
        )
        let sessions = [
            completedSession(
                title: "Push A",
                startedAt: Date(timeIntervalSince1970: 100),
                exercise: benchPress
            ),
            completedSession(
                title: "Push B",
                startedAt: Date(timeIntervalSince1970: 200),
                exercise: benchPress
            ),
            completedSession(
                title: "Legs",
                startedAt: Date(timeIntervalSince1970: 300),
                exercise: backSquat
            ),
        ]

        let rows = ExercisePickerContent.makeRows(
            exercises: [backSquat, bicepsCurl, benchPress],
            sessions: sessions,
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .mostPerformed
        )

        XCTAssertEqual(rows.map(\.exercise.name), ["Bench Press", "Back Squat", "Biceps Curl"])
        XCTAssertEqual(rows.map(\.performanceCount), [2, 1, 0])
    }

    func testMostPerformedSortUsesRecencyAndNameToBreakEqualCountTies() {
        let alphaPress = exercise(named: "Alpha Press")
        let betaPress = exercise(named: "Beta Press")
        let gammaPress = exercise(named: "Gamma Press")
        let singlePress = exercise(named: "Single Press")

        let rows = ExercisePickerContent.makeRows(
            exercises: [singlePress, gammaPress, betaPress, alphaPress],
            sessions: [
                completedSession(title: "Alpha A", startedAt: Date(timeIntervalSince1970: 100), exercise: alphaPress),
                completedSession(title: "Alpha B", startedAt: Date(timeIntervalSince1970: 300), exercise: alphaPress),
                completedSession(title: "Beta A", startedAt: Date(timeIntervalSince1970: 100), exercise: betaPress),
                completedSession(title: "Beta B", startedAt: Date(timeIntervalSince1970: 300), exercise: betaPress),
                completedSession(title: "Gamma A", startedAt: Date(timeIntervalSince1970: 100), exercise: gammaPress),
                completedSession(title: "Gamma B", startedAt: Date(timeIntervalSince1970: 200), exercise: gammaPress),
                completedSession(title: "Single", startedAt: Date(timeIntervalSince1970: 400), exercise: singlePress),
            ],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .mostPerformed
        )

        XCTAssertEqual(
            rows.map(\.exercise.name),
            ["Alpha Press", "Beta Press", "Gamma Press", "Single Press"]
        )
        XCTAssertEqual(rows.map(\.performanceCount), [2, 2, 2, 1])
    }

    func testNameSortIgnoresPerformanceHistory() {
        let benchPress = exercise(named: "Bench Press")
        let backSquat = exercise(named: "Back Squat", muscleGroup: .quads)
        let newerBenchSession = completedSession(
            title: "Push",
            startedAt: Date(timeIntervalSince1970: 200),
            exercise: benchPress
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [benchPress, backSquat],
            sessions: [newerBenchSession],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .name
        )

        XCTAssertEqual(rows.map(\.exercise.name), ["Back Squat", "Bench Press"])
    }

    func testSearchRanksNameMatchesBeforeMuscleMatchesThenAppliesSelectedSort() {
        let chestPress = Exercise(
            name: "Chest Press",
            category: .strength,
            equipment: .machine,
            primaryMuscleGroup: .chest
        )
        let benchPress = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let backSquat = Exercise(
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .quads
        )
        let sessions = [
            completedSession(
                title: "Older Chest Press",
                startedAt: Date(timeIntervalSince1970: 100),
                exercise: chestPress
            ),
            completedSession(
                title: "Newer Bench Press",
                startedAt: Date(timeIntervalSince1970: 200),
                exercise: benchPress
            ),
            completedSession(
                title: "Newest Squat",
                startedAt: Date(timeIntervalSince1970: 300),
                exercise: backSquat
            ),
        ]

        let rows = ExercisePickerContent.makeRows(
            exercises: [backSquat, benchPress, chestPress],
            sessions: sessions,
            ownerTokenIdentifier: nil,
            query: "chest",
            sortOrder: .recent
        )

        XCTAssertEqual(rows.map(\.exercise.name), ["Chest Press", "Bench Press"])
    }

    func testSearchMatchesEquipmentAndExcludesUnrelatedExercises() {
        let dumbbellRow = Exercise(
            name: "One Arm Row",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscleGroup: .upperBack
        )
        let dumbbellPress = Exercise(
            name: "Shoulder Press",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscleGroup: .shoulders
        )
        let barbellSquat = Exercise(
            name: "Back Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .quads
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [dumbbellPress, barbellSquat, dumbbellRow],
            sessions: [],
            ownerTokenIdentifier: nil,
            query: "DUMBBELL",
            sortOrder: .name
        )

        XCTAssertEqual(rows.map(\.exercise.name), ["One Arm Row", "Shoulder Press"])
    }

    func testSearchAppliesSelectedSortWithinTheSameRelevanceTier() {
        let alphaPress = exercise(named: "Alpha Press")
        let betaPress = exercise(named: "Beta Press")
        let backSquat = exercise(named: "Back Squat", muscleGroup: .quads)

        let rows = ExercisePickerContent.makeRows(
            exercises: [alphaPress, backSquat, betaPress],
            sessions: [
                completedSession(title: "Alpha", startedAt: Date(timeIntervalSince1970: 300), exercise: alphaPress),
                completedSession(title: "Beta A", startedAt: Date(timeIntervalSince1970: 100), exercise: betaPress),
                completedSession(title: "Beta B", startedAt: Date(timeIntervalSince1970: 200), exercise: betaPress),
            ],
            ownerTokenIdentifier: nil,
            query: "press",
            sortOrder: .mostPerformed
        )

        XCTAssertEqual(rows.map(\.exercise.name), ["Beta Press", "Alpha Press"])
    }

    func testSnapshotHistoryFallsBackByNameAndEquipmentWithoutCombiningVariants() {
        let barbellBench = exercise(named: "Bench Press")
        let dumbbellBench = exercise(
            named: "Bench Press",
            equipment: .dumbbell
        )
        let snapshotSession = completedSnapshotSession(
            title: "Legacy Push",
            startedAt: Date(timeIntervalSince1970: 200),
            name: "bench press",
            equipment: .barbell,
            muscleGroup: .chest
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [dumbbellBench, barbellBench],
            sessions: [snapshotSession],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .recent
        )

        XCTAssertEqual(rows.map(\.exercise.id), [barbellBench.id, dumbbellBench.id])
        XCTAssertEqual(rows.map(\.performanceCount), [1, 0])
    }

    func testLinkedAndSnapshotHistoryMergeWithoutDoubleCountingOneWorkout() {
        let benchPress = exercise(named: "Bench Press")
        let linkedSession = completedSession(
            title: "Linked Push",
            startedAt: Date(timeIntervalSince1970: 100),
            exercise: benchPress
        )
        let mixedSession = completedMixedIdentitySession(
            title: "Mixed Push",
            startedAt: Date(timeIntervalSince1970: 200),
            exercise: benchPress
        )
        let snapshotSession = completedSnapshotSession(
            title: "Legacy Push",
            startedAt: Date(timeIntervalSince1970: 300),
            name: benchPress.name,
            equipment: benchPress.equipment,
            muscleGroup: benchPress.primaryMuscleGroup
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [benchPress],
            sessions: [linkedSession, mixedSession, snapshotSession],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .recent
        )

        XCTAssertEqual(rows.first?.performanceCount, 3)
        XCTAssertEqual(rows.first?.lastPerformedAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(rows.first?.historySummary?.completedSetCount, 4)
    }

    func testRenamedExerciseCombinesExactHistoryWithEligibleCurrentSnapshotHistory() throws {
        let benchPress = exercise(named: "Bench Press")
        let linkedSession = completedSession(
            title: "Original Name Push",
            startedAt: Date(timeIntervalSince1970: 100),
            exercise: benchPress
        )
        benchPress.name = "Competition Bench Press"
        let snapshotSession = completedSnapshotSession(
            title: "Current Name Push",
            startedAt: Date(timeIntervalSince1970: 200),
            name: benchPress.name,
            equipment: benchPress.equipment,
            muscleGroup: benchPress.primaryMuscleGroup
        )
        let mixedSession = completedMixedIdentitySession(
            title: "Mixed Name Push",
            startedAt: Date(timeIntervalSince1970: 300),
            exercise: benchPress,
            linkedSnapshotName: "Bench Press",
            snapshotName: benchPress.name
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [benchPress],
            sessions: [linkedSession, snapshotSession, mixedSession],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .recent
        )

        XCTAssertEqual(rows.first?.performanceCount, 3)
        XCTAssertEqual(rows.first?.lastPerformedAt, mixedSession.startedAt)
        XCTAssertEqual(rows.first?.historySummary?.completedSetCount, 4)

        let visibility = ExerciseHistoryVisibilityScope(
            exercises: [benchPress],
            ownerTokenIdentifier: nil
        )
        let routeSummary = try XCTUnwrap(ExerciseHistorySummary.makeIndex(
            from: [linkedSession, snapshotSession, mixedSession]
        ).summary(
            matching: ExerciseHistoryRoute(
                exerciseID: benchPress.id,
                name: benchPress.name,
                equipmentRaw: benchPress.equipmentRaw
            ),
            visibility: visibility
        ))

        XCTAssertEqual(routeSummary.performanceCount, rows.first?.performanceCount)
        XCTAssertEqual(
            ExerciseHistorySessionGroup.makeGroups(
                from: [linkedSession, snapshotSession, mixedSession],
                matching: routeSummary
            ).map(\.title),
            ["Mixed Name Push", "Current Name Push", "Original Name Push"]
        )
    }

    func testVisibleHistoricalClaimPreventsAnotherExerciseFromInheritingSnapshotHistory() {
        let historicalClaimant = exercise(named: "Bench Press")
        let linkedSession = completedSession(
            title: "Linked Push",
            startedAt: Date(timeIntervalSince1970: 100),
            exercise: historicalClaimant
        )
        historicalClaimant.name = "Competition Bench Press"
        let currentNameMatch = exercise(named: "Bench Press")
        let snapshotSession = completedSnapshotSession(
            title: "Snapshot Push",
            startedAt: Date(timeIntervalSince1970: 200),
            name: currentNameMatch.name,
            equipment: currentNameMatch.equipment,
            muscleGroup: currentNameMatch.primaryMuscleGroup
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [historicalClaimant, currentNameMatch],
            sessions: [linkedSession, snapshotSession],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .name
        )

        let rowsByExerciseID = Dictionary(uniqueKeysWithValues: rows.map { ($0.exercise.id, $0) })
        XCTAssertEqual(rowsByExerciseID[historicalClaimant.id]?.performanceCount, 2)
        XCTAssertEqual(rowsByExerciseID[currentNameMatch.id]?.performanceCount, 0)

        let visibility = ExerciseHistoryVisibilityScope(
            exercises: [historicalClaimant, currentNameMatch],
            ownerTokenIdentifier: nil
        )
        let routeSummary = ExerciseHistorySummary.makeIndex(
            from: [linkedSession, snapshotSession]
        ).summary(
            matching: ExerciseHistoryRoute(
                exerciseID: currentNameMatch.id,
                name: currentNameMatch.name,
                equipmentRaw: currentNameMatch.equipmentRaw
            ),
            visibility: visibility
        )
        XCTAssertNil(routeSummary)
    }

    func testAmbiguousSnapshotHistoryIsNotAttributedToDuplicateExerciseRows() {
        let firstExercise = exercise(named: "Bench Press")
        let secondExercise = exercise(named: "Bench Press")
        let firstLinkedSession = completedSession(
            title: "First Linked Push",
            startedAt: Date(timeIntervalSince1970: 100),
            exercise: firstExercise
        )
        let secondLinkedSession = completedSession(
            title: "Second Linked Push",
            startedAt: Date(timeIntervalSince1970: 200),
            exercise: secondExercise
        )
        let snapshotSession = completedSnapshotSession(
            title: "Ambiguous Snapshot Push",
            startedAt: Date(timeIntervalSince1970: 300),
            name: "Bench Press",
            equipment: .barbell,
            muscleGroup: .chest
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [firstExercise, secondExercise],
            sessions: [firstLinkedSession, secondLinkedSession, snapshotSession],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .name
        )

        let rowsByExerciseID = Dictionary(uniqueKeysWithValues: rows.map { ($0.exercise.id, $0) })
        XCTAssertEqual(rowsByExerciseID[firstExercise.id]?.performanceCount, 1)
        XCTAssertEqual(rowsByExerciseID[secondExercise.id]?.performanceCount, 1)
        XCTAssertEqual(rowsByExerciseID[firstExercise.id]?.lastPerformedAt, firstLinkedSession.startedAt)
        XCTAssertEqual(rowsByExerciseID[secondExercise.id]?.lastPerformedAt, secondLinkedSession.startedAt)
    }

    func testContentExcludesArchivedDeletedAndOtherOwnerExercises() {
        let visible = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest,
            syncOwnerTokenIdentifier: "owner-a"
        )
        let archived = Exercise(
            name: "Archived Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest,
            isArchived: true,
            syncOwnerTokenIdentifier: "owner-a"
        )
        let deleted = Exercise(
            name: "Deleted Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest,
            syncOwnerTokenIdentifier: "owner-a",
            deletedAt: Date(timeIntervalSince1970: 100)
        )
        let otherOwner = Exercise(
            name: "Other Owner Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest,
            syncOwnerTokenIdentifier: "owner-b"
        )

        let rows = ExercisePickerContent.makeRows(
            exercises: [otherOwner, deleted, visible, archived],
            sessions: [],
            ownerTokenIdentifier: "owner-a",
            query: "",
            sortOrder: .recent
        )

        XCTAssertEqual(rows.map(\.exercise.name), ["Bench Press"])
    }

    func testIneligibleAndInvisibleWorkoutHistoryDoesNotAffectPickerRows() {
        let benchPress = exercise(named: "Bench Press")
        let activeSession = completedSession(
            title: "Active Push",
            startedAt: Date(timeIntervalSince1970: 100),
            exercise: benchPress
        )
        activeSession.status = .active
        let deletedSession = completedSession(
            title: "Deleted Push",
            startedAt: Date(timeIntervalSince1970: 200),
            exercise: benchPress
        )
        deletedSession.markDeletedCascade(now: Date(timeIntervalSince1970: 400))
        let otherOwnerSession = completedSession(
            title: "Other Owner Push",
            startedAt: Date(timeIntervalSince1970: 300),
            exercise: benchPress
        )
        otherOwnerSession.syncOwnerTokenIdentifier = "owner-b"
        let incompleteSession = completedSession(
            title: "Incomplete Push",
            startedAt: Date(timeIntervalSince1970: 400),
            exercise: benchPress
        )
        incompleteSession.loggedExercises[0].sets[0].isCompleted = false

        let rows = ExercisePickerContent.makeRows(
            exercises: [benchPress],
            sessions: [activeSession, deletedSession, otherOwnerSession, incompleteSession],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .recent
        )

        XCTAssertEqual(rows.first?.performanceCount, 0)
        XCTAssertEqual(rows.first?.performanceSummaryText, "Never performed")
    }

    func testNameSortUsesEquipmentToOrderSameNameVariants() {
        let dumbbellBench = exercise(named: "Bench Press", equipment: .dumbbell)
        let barbellBench = exercise(named: "Bench Press", equipment: .barbell)

        let rows = ExercisePickerContent.makeRows(
            exercises: [dumbbellBench, barbellBench],
            sessions: [],
            ownerTokenIdentifier: nil,
            query: "",
            sortOrder: .name
        )

        XCTAssertEqual(rows.map { $0.exercise.equipment }, [.barbell, .dumbbell])
    }

    func testRowPerformanceSummaryFormatsPerformanceCountAndNeverPerformedState() {
        let benchPress = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let performedAt = Date(timeIntervalSince1970: 100)
        let summary = ExerciseHistorySummary(
            id: "exercise-\(benchPress.id.uuidString)",
            exerciseID: benchPress.id,
            name: benchPress.name,
            equipmentRaw: benchPress.equipmentRaw,
            primaryMuscleGroupRaw: benchPress.primaryMuscleGroupRaw,
            lastPerformedAt: performedAt,
            completedSetCount: 12,
            performanceSessionIDs: [UUID()],
            snapshotFallbackIdentities: [
                ExerciseHistorySnapshotIdentity(
                    name: benchPress.name,
                    equipmentRaw: benchPress.equipmentRaw
                ),
            ]
        )

        let performedRow = ExercisePickerRowContent(
            exercise: benchPress,
            historySummary: summary
        )
        let neverPerformedRow = ExercisePickerRowContent(
            exercise: benchPress,
            historySummary: nil
        )

        XCTAssertEqual(
            performedRow.performanceSummaryText,
            "Last: \(WorkoutFormatters.compactDate(performedAt)) · 1 workout"
        )
        XCTAssertEqual(neverPerformedRow.performanceSummaryText, "Never performed")

        var repeatedSummary = summary
        repeatedSummary.performanceSessionIDs = Set((0..<8).map { _ in UUID() })
        XCTAssertEqual(
            ExercisePickerRowContent(
                exercise: benchPress,
                historySummary: repeatedSummary
            ).performanceSummaryText,
            "Last: \(WorkoutFormatters.compactDate(performedAt)) · 8 workouts"
        )
    }

    private func completedSession(
        title: String,
        startedAt: Date,
        exercise: Exercise
    ) -> WorkoutSession {
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name
        )
        loggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)
        ]
        let session = WorkoutSession(
            title: title,
            startedAt: startedAt,
            status: .completed,
            source: .blank
        )
        session.loggedExercises = [loggedExercise]
        return session
    }

    private func completedSnapshotSession(
        title: String,
        startedAt: Date,
        name: String,
        equipment: ExerciseEquipment,
        muscleGroup: ExerciseMuscleGroup
    ) -> WorkoutSession {
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: nil,
            exerciseSnapshotName: name,
            exerciseSnapshotEquipmentRaw: equipment.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: muscleGroup.rawValue
        )
        loggedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)
        ]
        let session = WorkoutSession(
            title: title,
            startedAt: startedAt,
            status: .completed,
            source: .blank
        )
        session.loggedExercises = [loggedExercise]
        return session
    }

    private func completedMixedIdentitySession(
        title: String,
        startedAt: Date,
        exercise: Exercise,
        linkedSnapshotName: String? = nil,
        snapshotName: String? = nil
    ) -> WorkoutSession {
        let linkedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: linkedSnapshotName ?? exercise.name
        )
        linkedExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)
        ]
        let snapshotExercise = LoggedExercise(
            orderIndex: 1,
            exercise: nil,
            exerciseSnapshotName: snapshotName ?? exercise.name,
            exerciseSnapshotEquipmentRaw: exercise.equipmentRaw,
            exerciseSnapshotPrimaryMuscleGroupRaw: exercise.primaryMuscleGroupRaw
        )
        snapshotExercise.sets = [
            LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)
        ]
        let session = WorkoutSession(
            title: title,
            startedAt: startedAt,
            status: .completed,
            source: .blank
        )
        session.loggedExercises = [linkedExercise, snapshotExercise]
        return session
    }

    private func exercise(
        named name: String,
        equipment: ExerciseEquipment = .barbell,
        muscleGroup: ExerciseMuscleGroup = .chest
    ) -> Exercise {
        Exercise(
            name: name,
            category: .strength,
            equipment: equipment,
            primaryMuscleGroup: muscleGroup
        )
    }
}
