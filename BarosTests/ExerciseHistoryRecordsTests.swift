import XCTest
@testable import Baros

@MainActor
final class ExerciseHistoryRecordsTests: XCTestCase {
    func testHeaviestRepAndEstimated1RMSelectIndependentSourceSets() throws {
        let heavy = LoggedSet(orderIndex: 2, weight: 225, reps: 1, isCompleted: true)
        let strongest = LoggedSet(orderIndex: 1, weight: 210, reps: 5, isCompleted: true)
        let session = makeSession(sets: [heavy, strongest])

        let records = try records(from: [session])

        XCTAssertEqual(records.heaviestRep?.setID, heavy.id)
        XCTAssertEqual(records.heaviestRep?.value, 225)
        XCTAssertEqual(records.estimated1RM?.setID, strongest.id)
        XCTAssertEqual(try XCTUnwrap(records.estimated1RM?.value), 245, accuracy: 0.000001)
    }

    func testEstimateUsesOnlyWorkingAndFailureSetsOfAtMostTenReps() throws {
        for kind in SetKind.allCases {
            for reps in [1, 10, 11] {
                let set = LoggedSet(orderIndex: 0, weight: 100, reps: reps, kind: kind, isCompleted: true)
                let result = try records(from: [makeSession(sets: [set])])
                XCTAssertEqual(result.heaviestRep?.value, 100)
                if (kind == .working || kind == .failure) && reps <= 10 {
                    XCTAssertEqual(try XCTUnwrap(result.estimated1RM?.value), reps == 1 ? 100 : 133.333333, accuracy: 0.000001)
                } else {
                    XCTAssertNil(result.estimated1RM, "\(kind) with \(reps) reps must not produce an estimate")
                }
            }
        }
    }

    func testRecordsUseHistoricalEquipmentAndHideUnsupportedEquipment() throws {
        let barbell = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)])
        let dumbbell = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 300, reps: 5, isCompleted: true)])
        let libraryExercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        barbell.loggedExercises[0].exercise = libraryExercise
        dumbbell.loggedExercises[0].exercise = libraryExercise
        dumbbell.loggedExercises[0].exerciseSnapshotEquipmentRaw = ExerciseEquipment.dumbbell.rawValue
        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [barbell, dumbbell]).first)
        let groups = ExerciseHistorySessionGroup.makeGroups(from: [barbell, dumbbell], matching: summary)

        let result = try XCTUnwrap(ExerciseHistoryRecords.make(from: groups, equipmentRaw: "barbell"))
        XCTAssertEqual(result.heaviestRep?.value, 100)
        for equipment in [nil, "bodyweight", "resistanceBand", "unrecognized"] as [String?] {
            XCTAssertNil(ExerciseHistoryRecords.make(from: groups, equipmentRaw: equipment))
        }
    }

    func testLegacyEquipmentCannotFollowLibraryEditsIntoRecords() throws {
        let set = LoggedSet(orderIndex: 0, weight: 300, reps: 5, isCompleted: true)
        let session = makeSession(sets: [set])
        let occurrence = session.loggedExercises[0]
        occurrence.hasSnapshotMetadata = false
        occurrence.exerciseSnapshotEquipmentRaw = ExerciseEquipment.other.rawValue
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        occurrence.exercise = exercise

        for equipment in [ExerciseEquipment.barbell, .dumbbell] {
            exercise.equipmentRaw = equipment.rawValue
            let result = try records(from: [session])
            XCTAssertNil(result.heaviestRep)
            XCTAssertNil(result.estimated1RM)
            XCTAssertTrue(result.kinds(for: set.id).isEmpty)
        }

        // Explicit legacy snapshot values are known history even without the newer flag.
        occurrence.exerciseSnapshotEquipmentRaw = ExerciseEquipment.barbell.rawValue
        XCTAssertEqual(try records(from: [session]).heaviestRep?.setID, set.id)
    }

    func testTiesSelectNewestWorkoutRegardlessOfInputOrderAndShareBadgeSources() throws {
        let olderSet = LoggedSet(orderIndex: 0, weight: 225, reps: 5, isCompleted: true)
        let newerSet = LoggedSet(orderIndex: 0, weight: 225, reps: 5, isCompleted: true)
        let older = makeSession(sets: [olderSet])
        let newer = makeSession(sets: [newerSet])
        newer.startedAt = Date(timeIntervalSince1970: 2_000)
        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [older, newer]).first)
        let groups = ExerciseHistorySessionGroup.makeGroups(from: [older, newer], matching: summary)

        for input in [groups, Array(groups.reversed())] {
            let result = try XCTUnwrap(ExerciseHistoryRecords.make(from: input, equipmentRaw: summary.equipmentRaw))
            XCTAssertEqual(result.heaviestRep?.setID, newerSet.id)
            XCTAssertEqual(result.estimated1RM?.setID, newerSet.id)
            XCTAssertEqual(result.kinds(for: newerSet.id), [.heaviestRep, .estimated1RM])
            XCTAssertEqual(result.kinds(for: olderSet.id), [])
        }
    }

    func testInvalidNumbersAndUnknownKindsDoNotProduceRecords() throws {
        let invalidValues: [(Double?, Int?)] = [
            (nil, 5), (0, 5), (-1, 5), (.infinity, 5), (.nan, 5), (10_001, 5),
            (100, nil), (100, 0), (100, -1), (100, 1_001),
        ]
        var sets = invalidValues.enumerated().map { index, value in
            LoggedSet(orderIndex: index, weight: value.0, reps: value.1, isCompleted: true)
        }
        let unknownKind = LoggedSet(orderIndex: 20, weight: 200, reps: 5, isCompleted: true)
        unknownKind.kindRaw = "unknown"
        sets.append(unknownKind)
        let result = try records(from: [makeSession(sets: sets)])
        XCTAssertNil(result.heaviestRep)
        XCTAssertNil(result.estimated1RM)
    }

    func testRecordsAndBadgesRecalculateAfterEditsDeletionAndCompletionChanges() throws {
        let first = LoggedSet(orderIndex: 0, weight: 225, reps: 5, isCompleted: true)
        let second = LoggedSet(orderIndex: 2, weight: 210, reps: 5, isCompleted: true)
        let session = makeSession(sets: [first, second])
        XCTAssertEqual(try records(from: [session]).heaviestRep?.setID, first.id)

        first.weight = 200
        var result = try records(from: [session])
        XCTAssertEqual(result.heaviestRep?.setID, second.id)
        XCTAssertEqual(result.heaviestRep?.displaySetNumber, 3)
        XCTAssertEqual(result.kinds(for: first.id), [])
        XCTAssertEqual(result.kinds(for: second.id), [.heaviestRep, .estimated1RM])

        second.deletedAt = .now
        result = try records(from: [session])
        XCTAssertEqual(result.heaviestRep?.setID, first.id)
        second.deletedAt = nil
        second.isCompleted = false
        XCTAssertEqual(try records(from: [session]).heaviestRep?.setID, first.id)
        first.weight = nil
        result = try records(from: [session])
        XCTAssertNil(result.heaviestRep)
        XCTAssertNil(result.estimated1RM)
    }

    func testRecordsExcludeOtherOwnersUnfinishedWorkoutsAndDeletedHistory() throws {
        let own = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)])
        own.syncOwnerTokenIdentifier = "owner-a"
        let local = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 80, reps: 5, isCompleted: true)])
        let other = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 500, reps: 5, isCompleted: true)])
        other.syncOwnerTokenIdentifier = "owner-b"
        let active = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 600, reps: 5, isCompleted: true)])
        active.status = .active
        let deleted = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 700, reps: 5, isCompleted: true)])
        deleted.deletedAt = .now
        let deletedOccurrence = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 800, reps: 5, isCompleted: true)])
        deletedOccurrence.loggedExercises[0].deletedAt = .now
        let sessions = [own, local, other, active, deleted, deletedOccurrence]

        XCTAssertEqual(try records(from: sessions, owner: "owner-a").heaviestRep?.value, 100)
        XCTAssertEqual(try records(from: sessions).heaviestRep?.value, 80)
        XCTAssertEqual(try records(from: sessions, owner: "owner-b").heaviestRep?.value, 500)
    }

    func testTiesWithinWorkoutUseExerciseThenSetOrder() throws {
        let first = LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)
        let laterSet = LoggedSet(orderIndex: 2, weight: 100, reps: 5, isCompleted: true)
        let laterOccurrenceSet = LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)
        let session = makeSession(sets: [laterSet, first])
        session.loggedExercises.append(LoggedExercise(
            orderIndex: 1,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: "barbell",
            sets: [laterOccurrenceSet]
        ))
        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: [session]).first)
        let group = try XCTUnwrap(ExerciseHistorySessionGroup.makeGroups(from: [session], matching: summary).first)
        let reversedGroup = ExerciseHistorySessionGroup(session: session, setEntries: group.setEntries.reversed())
        let result = try XCTUnwrap(ExerciseHistoryRecords.make(from: [reversedGroup], equipmentRaw: "barbell"))
        XCTAssertEqual(result.heaviestRep?.setID, first.id)
        XCTAssertEqual(result.estimated1RM?.setID, first.id)
    }

    func testSeparateExercisesAndAmbiguousSnapshotsDoNotShareRecords() throws {
        let firstExercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let secondExercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let first = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)])
        first.loggedExercises[0].exercise = firstExercise
        let second = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 200, reps: 5, isCompleted: true)])
        second.loggedExercises[0].exercise = secondExercise
        let ambiguous = makeSession(sets: [LoggedSet(orderIndex: 0, weight: 500, reps: 5, isCompleted: true)])
        let sessions = [first, second, ambiguous]
        let history = ExerciseHistorySummary.makeResolvedHistory(from: sessions, exercises: [firstExercise, secondExercise])
        let summary = try XCTUnwrap(history.summary(for: firstExercise))
        let groups = ExerciseHistorySessionGroup.makeGroups(from: sessions, matching: summary)
        let result = try XCTUnwrap(ExerciseHistoryRecords.make(from: groups, equipmentRaw: "barbell"))
        XCTAssertEqual(result.heaviestRep?.value, 100)
    }

    func testRankingUsesUnroundedCanonicalWeightAndPreservesSourceContext() throws {
        let smaller = LoggedSet(orderIndex: 0, weight: 100.001, reps: 5, isCompleted: true)
        let larger = LoggedSet(orderIndex: 3, weight: 100.002, reps: 5, isCompleted: true)
        let result = try records(from: [makeSession(sets: [smaller, larger])])
        let winner = try XCTUnwrap(result.heaviestRep)
        XCTAssertEqual(winner.setID, larger.id)
        XCTAssertEqual(winner.workoutTitle, "Upper Body")
        XCTAssertEqual(winner.workoutDate, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(winner.reps, 5)
        XCTAssertEqual(winner.displaySetNumber, 4)
        XCTAssertEqual(MeasurementUnit.kilograms.displayWeight(fromCanonicalPounds: winner.value) ?? 0, 45.360145, accuracy: 0.00001)
    }

    private func makeSession(sets: [LoggedSet]) -> WorkoutSession {
        WorkoutSession(
            title: "Upper Body",
            startedAt: Date(timeIntervalSince1970: 1_000),
            status: .completed,
            source: .blank,
            loggedExercises: [LoggedExercise(
                orderIndex: 0,
                exerciseSnapshotName: "Bench Press",
                exerciseSnapshotEquipmentRaw: ExerciseEquipment.barbell.rawValue,
                sets: sets
            )]
        )
    }

    private func records(from sessions: [WorkoutSession], owner: String? = nil) throws -> ExerciseHistoryRecords {
        let summary = try XCTUnwrap(ExerciseHistorySummary.makeSummaries(from: sessions, ownerTokenIdentifier: owner).first)
        let groups = ExerciseHistorySessionGroup.makeGroups(from: sessions, matching: summary, ownerTokenIdentifier: owner)
        return try XCTUnwrap(ExerciseHistoryRecords.make(from: groups, equipmentRaw: summary.equipmentRaw))
    }
}
