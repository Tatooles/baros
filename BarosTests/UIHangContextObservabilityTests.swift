import Sentry
import XCTest
@testable import Baros

@MainActor
final class UIHangContextObservabilityTests: XCTestCase {
    func testCountBucketsUseDocumentedBoundaries() {
        let expectations: [(Int, UIHangCountBucket)] = [
            (-1, .zero),
            (0, .zero),
            (1, .one),
            (2, .twoToFive),
            (5, .twoToFive),
            (6, .sixToTen),
            (10, .sixToTen),
            (11, .elevenToTwenty),
            (20, .elevenToTwenty),
            (21, .twentyOneOrMore),
            (10_000, .twentyOneOrMore),
        ]

        for (count, expectedBucket) in expectations {
            XCTAssertEqual(UIHangCountBucket(count: count), expectedBucket, "count: \(count)")
        }
    }

    func testWorkoutFieldsMapToCategoriesWithoutIdentifiers() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(UIHangFocusedField(workoutField: .workoutTitle), .workoutText)
        XCTAssertEqual(UIHangFocusedField(workoutField: .workoutNotes), .workoutText)
        XCTAssertEqual(UIHangFocusedField(workoutField: .exerciseNotes(firstID)), .exerciseNote)
        XCTAssertEqual(UIHangFocusedField(workoutField: .setWeight(firstID)), .setWeight)
        XCTAssertEqual(UIHangFocusedField(workoutField: .setReps(secondID)), .setReps)
        XCTAssertFalse(UIHangFocusedField.allCases.map(\.rawValue).contains { value in
            value.contains(firstID.uuidString) || value.contains(secondID.uuidString)
        })
    }

    func testPresentationFocusStructureAndClearingProduceBoundedSnapshots() throws {
        let sink = RecordingUIHangContextSink()
        let observability = UIHangContextObservability(sink: sink)

        observability.activeWorkoutBecameCurrent(exerciseCount: 2, setCount: 11)
        XCTAssertEqual(sink.snapshots.last, UIHangContextSnapshot(
            surface: .activeWorkout,
            exerciseCountBucket: .twoToFive,
            setCountBucket: .elevenToTwenty,
            focusedField: nil
        ))

        observability.focusChanged(to: .setWeight(UUID()))
        XCTAssertEqual(sink.snapshots.last?.focusedField, .setWeight)

        observability.activeWorkoutStructureChanged(exerciseCount: 6, setCount: 21)
        XCTAssertEqual(sink.snapshots.last?.exerciseCountBucket, .sixToTen)
        XCTAssertEqual(sink.snapshots.last?.setCountBucket, .twentyOneOrMore)

        observability.addExercisePresented()
        XCTAssertEqual(sink.snapshots.last?.surface, .exercisePicker)
        XCTAssertNil(sink.snapshots.last?.focusedField)
        XCTAssertEqual(sink.breadcrumbs, [.addExercisePresented])

        observability.exerciseSearchEditingChanged(isEditing: true)
        observability.exerciseSearchEditingChanged(isEditing: true)
        observability.exerciseSearchEditingChanged(isEditing: false)
        XCTAssertEqual(sink.breadcrumbs, [
            .addExercisePresented,
            .exerciseSearchBegan,
            .exerciseSearchEnded,
        ])

        observability.addExerciseDismissed()
        XCTAssertEqual(sink.snapshots.last?.surface, .activeWorkout)
        XCTAssertEqual(sink.breadcrumbs.last, .addExerciseDismissed)

        observability.activeWorkoutCeasedBeingCurrent()
        XCTAssertEqual(try XCTUnwrap(sink.snapshots.last), .empty)
    }

    func testSentryScopeMappingUsesOnlyApprovedKeysAndValues() {
        let snapshot = UIHangContextSnapshot(
            surface: .activeWorkout,
            exerciseCountBucket: .twoToFive,
            setCountBucket: .sixToTen,
            focusedField: .exerciseNote
        )

        XCTAssertEqual(SentryUIHangContextSink.tagValues(for: snapshot), [
            "ui_surface": "active_workout",
        ])
        XCTAssertEqual(SentryUIHangContextSink.contextValues(for: snapshot) as NSDictionary, [
            "schema_version": 1,
            "exercise_count_bucket": "2_5",
            "set_count_bucket": "6_10",
            "focused_field": "exercise_note",
        ] as NSDictionary)
        XCTAssertEqual(SentryUIHangContextSink.tagValues(for: .empty), [:])
        XCTAssertTrue(SentryUIHangContextSink.contextValues(for: .empty).isEmpty)
    }

    func testUIScrubberRemovesProhibitedContextAndBreadcrumbData() throws {
        let event = Event(level: .fatal)
        event.tags = [
            "ui_surface": "active_workout",
            "distribution_channel": "app_store",
        ]
        event.context = [
            "ui": [
                "schema_version": 1,
                "exercise_count_bucket": "2_5",
                "set_count_bucket": "6_10",
                "focused_field": "set_reps",
                "workout_name": "Private Workout",
            ],
        ]
        let unsafeBreadcrumb = Breadcrumb(level: .info, category: "baros.ui")
        unsafeBreadcrumb.type = "navigation"
        unsafeBreadcrumb.message = "exercise_search_began"
        unsafeBreadcrumb.setData(value: "private query", key: "search_text")
        let safeBreadcrumb = SentryUIHangContextSink.makeBreadcrumb(.exerciseSearchEnded)
        event.breadcrumbs = [unsafeBreadcrumb, safeBreadcrumb]

        let scrubbed = try XCTUnwrap(SentryUIHangEventScrubber.scrub(event))

        XCTAssertNil(scrubbed.tags?["ui_surface"])
        XCTAssertNil(scrubbed.context?["ui"])
        XCTAssertEqual(scrubbed.breadcrumbs?.filter { $0.category == "baros.ui" }.count, 1)
        XCTAssertEqual(
            scrubbed.breadcrumbs?.first { $0.category == "baros.ui" }?.message,
            "exercise_search_ended"
        )
        XCTAssertFalse(String(describing: scrubbed).contains("Private Workout"))
        XCTAssertFalse(String(describing: scrubbed).contains("private query"))
    }
}

@MainActor
private final class RecordingUIHangContextSink: UIHangContextSink {
    private(set) var snapshots: [UIHangContextSnapshot] = []
    private(set) var breadcrumbs: [UIHangBreadcrumb] = []

    func apply(_ snapshot: UIHangContextSnapshot) {
        snapshots.append(snapshot)
    }

    func addBreadcrumb(_ breadcrumb: UIHangBreadcrumb) {
        breadcrumbs.append(breadcrumb)
    }
}
