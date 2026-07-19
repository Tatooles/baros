import XCTest
@testable import Baros

@MainActor
final class WorkoutDataExportServiceTests: XCTestCase {
    private let header = [
        "workout_date",
        "workout_title",
        "workout_notes",
        "exercise_order",
        "exercise_name",
        "exercise_notes",
        "set_order",
        "set_kind",
        "is_completed",
        "weight",
        "reps",
        "unit",
        "rpe",
        "set_notes",
        "completed_at",
        "workout_id",
        "logged_exercise_id",
        "set_id"
    ]

    func testCSVIncludesHeaderCompletedWorkoutSetRowsSortingAndStableIDs() throws {
        let olderSessionID = uuid("00000000-0000-0000-0000-000000000001")
        let benchExerciseID = uuid("00000000-0000-0000-0000-000000000101")
        let curlExerciseID = uuid("00000000-0000-0000-0000-000000000102")
        let incompleteSetID = uuid("00000000-0000-0000-0000-000000000201")
        let completedSetID = uuid("00000000-0000-0000-0000-000000000202")
        let curlSetID = uuid("00000000-0000-0000-0000-000000000203")
        let tieASessionID = uuid("00000000-0000-0000-0000-000000000002")
        let tieAExerciseID = uuid("00000000-0000-0000-0000-000000000103")
        let tieASetID = uuid("00000000-0000-0000-0000-000000000204")
        let tieBSessionID = uuid("00000000-0000-0000-0000-000000000003")
        let tieBExerciseID = uuid("00000000-0000-0000-0000-000000000104")
        let tieBSetID = uuid("00000000-0000-0000-0000-000000000205")

        let olderSession = WorkoutSession(
            id: olderSessionID,
            title: "Alpha, Day",
            startedAt: Date(timeIntervalSince1970: 0),
            notes: "Line one\nLine \"two\"",
            status: .completed,
            source: .blank
        )
        let curlExercise = LoggedExercise(
            id: curlExerciseID,
            orderIndex: 1,
            exerciseSnapshotName: "Curl"
        )
        curlExercise.sets = [
            LoggedSet(
                id: curlSetID,
                orderIndex: 0,
                weight: 42.1259,
                reps: 12,
                rpe: 7.5,
                kind: .drop,
                isCompleted: true,
                completedAt: Date(timeIntervalSince1970: 90),
                notes: "Pump"
            )
        ]
        let benchExercise = LoggedExercise(
            id: benchExerciseID,
            orderIndex: 0,
            exerciseSnapshotName: "Bench \"Press\"",
            notes: "Use, spotter"
        )
        benchExercise.sets = [
            LoggedSet(
                id: completedSetID,
                orderIndex: 1,
                weight: 185.5,
                reps: 5,
                rpe: 8,
                kind: .working,
                isCompleted: true,
                completedAt: Date(timeIntervalSince1970: 60),
                notes: "Smooth"
            ),
            LoggedSet(
                id: incompleteSetID,
                orderIndex: 0,
                kind: .warmup,
                isCompleted: false,
                notes: "Needs\rsetup"
            )
        ]
        olderSession.loggedExercises = [curlExercise, benchExercise]
        let tieBSession = completedSession(
            id: tieBSessionID,
            title: "Tie B",
            startedAt: Date(timeIntervalSince1970: 100),
            exerciseID: tieBExerciseID,
            setID: tieBSetID
        )
        let tieASession = completedSession(
            id: tieASessionID,
            title: "Tie A",
            startedAt: Date(timeIntervalSince1970: 100),
            exerciseID: tieAExerciseID,
            setID: tieASetID
        )
        let activeSession = completedSession(
            id: uuid("00000000-0000-0000-0000-000000000004"),
            title: "Active",
            startedAt: Date(timeIntervalSince1970: -100),
            status: .active,
            exerciseID: uuid("00000000-0000-0000-0000-000000000105"),
            setID: uuid("00000000-0000-0000-0000-000000000206")
        )
        let discardedSession = completedSession(
            id: uuid("00000000-0000-0000-0000-000000000005"),
            title: "Discarded",
            startedAt: Date(timeIntervalSince1970: -50),
            status: .discarded,
            exerciseID: uuid("00000000-0000-0000-0000-000000000106"),
            setID: uuid("00000000-0000-0000-0000-000000000207")
        )

        let csv = WorkoutDataExportService().csv(
            for: [tieBSession, activeSession, olderSession, discardedSession, tieASession],
            unit: .pounds
        )
        let rows = try parseCSV(csv)

        XCTAssertEqual(csv.last, "\n")
        XCTAssertEqual(rows.first, header)
        XCTAssertEqual(rows.count, 6)
        XCTAssertFalse(csv.contains("Active"))
        XCTAssertFalse(csv.contains("Discarded"))
        XCTAssertTrue(csv.contains("\"Alpha, Day\""))
        XCTAssertTrue(csv.contains("\"Line one\nLine \"\"two\"\"\""))
        XCTAssertTrue(csv.contains("\"Bench \"\"Press\"\"\""))
        XCTAssertTrue(csv.contains("\"Use, spotter\""))
        XCTAssertTrue(csv.contains("\"Needs\rsetup\""))

        XCTAssertEqual(rows[1], [
            "1970-01-01T00:00:00Z",
            "Alpha, Day",
            "Line one\nLine \"two\"",
            "1",
            "Bench \"Press\"",
            "Use, spotter",
            "1",
            "warmup",
            "false",
            "",
            "",
            "pounds",
            "",
            "Needs\rsetup",
            "",
            olderSessionID.uuidString,
            benchExerciseID.uuidString,
            incompleteSetID.uuidString
        ])
        XCTAssertEqual(rows[2], [
            "1970-01-01T00:00:00Z",
            "Alpha, Day",
            "Line one\nLine \"two\"",
            "1",
            "Bench \"Press\"",
            "Use, spotter",
            "2",
            "working",
            "true",
            "185.5",
            "5",
            "pounds",
            "8",
            "Smooth",
            "1970-01-01T00:01:00Z",
            olderSessionID.uuidString,
            benchExerciseID.uuidString,
            completedSetID.uuidString
        ])
        XCTAssertEqual(rows[3], [
            "1970-01-01T00:00:00Z",
            "Alpha, Day",
            "Line one\nLine \"two\"",
            "2",
            "Curl",
            "",
            "1",
            "drop",
            "true",
            "42.126",
            "12",
            "pounds",
            "7.5",
            "Pump",
            "1970-01-01T00:01:30Z",
            olderSessionID.uuidString,
            curlExerciseID.uuidString,
            curlSetID.uuidString
        ])
        XCTAssertEqual(rows[4].suffix(3), [
            tieASessionID.uuidString,
            tieAExerciseID.uuidString,
            tieASetID.uuidString
        ])
        XCTAssertEqual(rows[5].suffix(3), [
            tieBSessionID.uuidString,
            tieBExerciseID.uuidString,
            tieBSetID.uuidString
        ])
        XCTAssertEqual(rows[4][1], "Tie A")
        XCTAssertEqual(rows[5][1], "Tie B")
    }

    func testCSVConvertsCanonicalPoundsToSelectedKilogramUnit() throws {
        let session = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000009001")!,
            title: "Metric Export",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000009002")!,
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press"
        )
        let set = LoggedSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000009003")!,
            orderIndex: 0,
            weight: 220.462262185,
            reps: 5,
            rpe: 8,
            isCompleted: true
        )
        set.loggedExercise = loggedExercise
        loggedExercise.session = session
        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)

        let rows = try parseCSV(WorkoutDataExportService().csv(for: [session], unit: .kilograms))

        XCTAssertEqual(rows[1][9], "100")
        XCTAssertEqual(rows[1][11], "kilograms")
    }

    func testCSVUsesUUIDTieBreakersWhenSortKeysMatch() throws {
        let sessionAID = uuid("00000000-0000-0000-0000-000000000001")
        let sessionBID = uuid("00000000-0000-0000-0000-000000000002")
        let exerciseAID = uuid("00000000-0000-0000-0000-000000000101")
        let exerciseBID = uuid("00000000-0000-0000-0000-000000000102")
        let setAID = uuid("00000000-0000-0000-0000-000000000201")
        let setBID = uuid("00000000-0000-0000-0000-000000000202")
        let sessionBSetID = uuid("00000000-0000-0000-0000-000000000203")
        let setCID = uuid("00000000-0000-0000-0000-000000000204")

        let startedAt = Date(timeIntervalSince1970: 200)
        let sessionB = completedSession(
            id: sessionBID,
            title: "Same Title",
            startedAt: startedAt,
            exerciseID: uuid("00000000-0000-0000-0000-000000000103"),
            setID: sessionBSetID
        )
        let sessionA = WorkoutSession(
            id: sessionAID,
            title: "Same Title",
            startedAt: startedAt,
            status: .completed,
            source: .blank
        )
        let exerciseB = LoggedExercise(
            id: exerciseBID,
            orderIndex: 0,
            exerciseSnapshotName: "Exercise B"
        )
        exerciseB.sets = [
            LoggedSet(id: setCID, orderIndex: 0, weight: 30, reps: 3)
        ]
        let exerciseA = LoggedExercise(
            id: exerciseAID,
            orderIndex: 0,
            exerciseSnapshotName: "Exercise A"
        )
        exerciseA.sets = [
            LoggedSet(id: setBID, orderIndex: 0, weight: 20, reps: 2),
            LoggedSet(id: setAID, orderIndex: 0, weight: 10, reps: 1)
        ]
        sessionA.loggedExercises = [exerciseB, exerciseA]

        let rows = try parseCSV(WorkoutDataExportService().csv(for: [sessionB, sessionA], unit: .pounds))

        XCTAssertEqual(rows[1][15], sessionAID.uuidString)
        XCTAssertEqual(rows[1][16], exerciseAID.uuidString)
        XCTAssertEqual(rows[1][17], setAID.uuidString)
        XCTAssertEqual(rows[2][15], sessionAID.uuidString)
        XCTAssertEqual(rows[2][16], exerciseAID.uuidString)
        XCTAssertEqual(rows[2][17], setBID.uuidString)
        XCTAssertEqual(rows[3][15], sessionAID.uuidString)
        XCTAssertEqual(rows[3][16], exerciseBID.uuidString)
        XCTAssertEqual(rows[4][15], sessionBID.uuidString)
    }

    func testCSVExcludesTombstonedWorkoutGraphRecords() throws {
        let visibleSession = WorkoutSession(
            id: uuid("00000000-0000-0000-0000-000000000001"),
            title: "Visible",
            startedAt: Date(timeIntervalSince1970: 0),
            status: .completed,
            source: .blank
        )
        let visibleExercise = LoggedExercise(
            id: uuid("00000000-0000-0000-0000-000000000101"),
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press"
        )
        visibleExercise.sets = [
            LoggedSet(
                id: uuid("00000000-0000-0000-0000-000000000201"),
                orderIndex: 0,
                weight: 185,
                reps: 5,
                isCompleted: true
            ),
            LoggedSet(
                id: uuid("00000000-0000-0000-0000-000000000202"),
                orderIndex: 1,
                weight: 225,
                reps: 1,
                isCompleted: true,
                deletedAt: Date(timeIntervalSince1970: 50)
            )
        ]
        let deletedExercise = LoggedExercise(
            id: uuid("00000000-0000-0000-0000-000000000102"),
            orderIndex: 1,
            exerciseSnapshotName: "Deleted Curl",
            deletedAt: Date(timeIntervalSince1970: 60),
            sets: [
                LoggedSet(
                    id: uuid("00000000-0000-0000-0000-000000000203"),
                    orderIndex: 0,
                    weight: 30,
                    reps: 12,
                    isCompleted: true
                )
            ]
        )
        visibleSession.loggedExercises = [visibleExercise, deletedExercise]
        let deletedSession = completedSession(
            id: uuid("00000000-0000-0000-0000-000000000002"),
            title: "Deleted Session",
            startedAt: Date(timeIntervalSince1970: 100),
            exerciseID: uuid("00000000-0000-0000-0000-000000000103"),
            setID: uuid("00000000-0000-0000-0000-000000000204")
        )
        deletedSession.markDeletedCascade(now: Date(timeIntervalSince1970: 200))

        let rows = try parseCSV(
            WorkoutDataExportService().csv(for: [visibleSession, deletedSession], unit: .pounds)
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][1], "Visible")
        XCTAssertEqual(rows[1][4], "Bench Press")
        XCTAssertEqual(rows[1][17], "00000000-0000-0000-0000-000000000201")
    }

    func testCSVUsesLocaleIndependentTitleOrderingWhenStartDatesMatch() throws {
        let uppercaseSessionID = uuid("00000000-0000-0000-0000-000000000001")
        let lowercaseSessionID = uuid("00000000-0000-0000-0000-000000000002")
        let startedAt = Date(timeIntervalSince1970: 300)
        let lowercaseSession = completedSession(
            id: lowercaseSessionID,
            title: "a",
            startedAt: startedAt,
            exerciseID: uuid("00000000-0000-0000-0000-000000000101"),
            setID: uuid("00000000-0000-0000-0000-000000000201")
        )
        let uppercaseSession = completedSession(
            id: uppercaseSessionID,
            title: "B",
            startedAt: startedAt,
            exerciseID: uuid("00000000-0000-0000-0000-000000000102"),
            setID: uuid("00000000-0000-0000-0000-000000000202")
        )

        let rows = try parseCSV(
            WorkoutDataExportService().csv(for: [lowercaseSession, uppercaseSession], unit: .pounds)
        )

        XCTAssertEqual(rows[1][1], "B")
        XCTAssertEqual(rows[1][15], uppercaseSessionID.uuidString)
        XCTAssertEqual(rows[2][1], "a")
        XCTAssertEqual(rows[2][15], lowercaseSessionID.uuidString)
    }

    func testCSVNeutralizesFormulaLikeUserTextFields() throws {
        let session = WorkoutSession(
            id: uuid("00000000-0000-0000-0000-000000000001"),
            title: "=IMPORTDATA(\"https://example.com\")",
            startedAt: Date(timeIntervalSince1970: 0),
            notes: "+SUM(1,1)",
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(
            id: uuid("00000000-0000-0000-0000-000000000101"),
            orderIndex: 0,
            exerciseSnapshotName: "-HYPERLINK(\"https://example.com\")",
            notes: "@metadata"
        )
        let loggedSet = LoggedSet(
            id: uuid("00000000-0000-0000-0000-000000000201"),
            orderIndex: 0,
            weight: -25,
            reps: 5,
            rpe: 8,
            kind: .working,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 60),
            notes: "=cmd"
        )
        loggedExercise.sets = [loggedSet]
        session.loggedExercises = [loggedExercise]

        let rows = try parseCSV(WorkoutDataExportService().csv(for: [session], unit: .pounds))

        XCTAssertEqual(rows[1][1], "'=IMPORTDATA(\"https://example.com\")")
        XCTAssertEqual(rows[1][2], "'+SUM(1,1)")
        XCTAssertEqual(rows[1][4], "'-HYPERLINK(\"https://example.com\")")
        XCTAssertEqual(rows[1][5], "'@metadata")
        XCTAssertEqual(rows[1][9], "-25")
        XCTAssertEqual(rows[1][13], "'=cmd")
    }

    func testCSVNeutralizesFormulaLikeUserTextAfterLeadingControlCharacters() throws {
        let session = WorkoutSession(
            id: uuid("00000000-0000-0000-0000-000000000001"),
            title: "\t=IMPORTDATA(\"https://example.com\")",
            startedAt: Date(timeIntervalSince1970: 0),
            notes: "\n+SUM(1,1)",
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(
            id: uuid("00000000-0000-0000-0000-000000000101"),
            orderIndex: 0,
            exerciseSnapshotName: "\r-HYPERLINK(\"https://example.com\")",
            notes: "\u{001F}@metadata"
        )
        let loggedSet = LoggedSet(
            id: uuid("00000000-0000-0000-0000-000000000201"),
            orderIndex: 0,
            weight: 25,
            reps: 5,
            rpe: 8,
            kind: .working,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 60),
            notes: "\t=cmd"
        )
        loggedExercise.sets = [loggedSet]
        session.loggedExercises = [loggedExercise]

        let rows = try parseCSV(WorkoutDataExportService().csv(for: [session], unit: .pounds))

        XCTAssertEqual(rows[1][1], "'\t=IMPORTDATA(\"https://example.com\")")
        XCTAssertEqual(rows[1][2], "'\n+SUM(1,1)")
        XCTAssertEqual(rows[1][4], "'\r-HYPERLINK(\"https://example.com\")")
        XCTAssertEqual(rows[1][5], "'\u{001F}@metadata")
        XCTAssertEqual(rows[1][13], "'\t=cmd")
    }

    func testCSVNeutralizesFullWidthFormulaLikeUserTextFields() throws {
        let session = WorkoutSession(
            id: uuid("00000000-0000-0000-0000-000000000001"),
            title: "＝IMPORTDATA(\"https://example.com\")",
            startedAt: Date(timeIntervalSince1970: 0),
            notes: "\t＋SUM(1,1)",
            status: .completed,
            source: .blank
        )
        let loggedExercise = LoggedExercise(
            id: uuid("00000000-0000-0000-0000-000000000101"),
            orderIndex: 0,
            exerciseSnapshotName: "－HYPERLINK(\"https://example.com\")",
            notes: "＠metadata"
        )
        let loggedSet = LoggedSet(
            id: uuid("00000000-0000-0000-0000-000000000201"),
            orderIndex: 0,
            weight: 25,
            reps: 5,
            rpe: 8,
            kind: .working,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 60),
            notes: "\n＝cmd"
        )
        loggedExercise.sets = [loggedSet]
        session.loggedExercises = [loggedExercise]

        let rows = try parseCSV(WorkoutDataExportService().csv(for: [session], unit: .pounds))

        XCTAssertEqual(rows[1][1], "'＝IMPORTDATA(\"https://example.com\")")
        XCTAssertEqual(rows[1][2], "'\t＋SUM(1,1)")
        XCTAssertEqual(rows[1][4], "'－HYPERLINK(\"https://example.com\")")
        XCTAssertEqual(rows[1][5], "'＠metadata")
        XCTAssertEqual(rows[1][13], "'\n＝cmd")
    }

    private func completedSession(
        id: UUID,
        title: String,
        startedAt: Date,
        status: WorkoutSessionStatus = .completed,
        exerciseID: UUID,
        setID: UUID
    ) -> WorkoutSession {
        let session = WorkoutSession(
            id: id,
            title: title,
            startedAt: startedAt,
            status: status,
            source: .blank
        )
        let loggedExercise = LoggedExercise(
            id: exerciseID,
            orderIndex: 0,
            exerciseSnapshotName: "Squat"
        )
        loggedExercise.sets = [
            LoggedSet(
                id: setID,
                orderIndex: 0,
                weight: 225,
                reps: 3,
                rpe: 9,
                isCompleted: true,
                completedAt: startedAt
            )
        ]
        session.loggedExercises = [loggedExercise]
        return session
    }

    private func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            XCTFail("Invalid UUID string: \(value)")
            return UUID()
        }
        return uuid
    }

    private func parseCSV(_ csv: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let character = csv[index]

            if isQuoted {
                if character == "\"" {
                    let next = csv.index(after: index)
                    if next < csv.endIndex, csv[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    isQuoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(character)
                }
            }

            index = csv.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}
