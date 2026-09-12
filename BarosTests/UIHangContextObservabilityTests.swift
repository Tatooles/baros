import Sentry
import XCTest
@testable import Baros

@MainActor
final class UIHangContextObservabilityTests: XCTestCase {
    func testMetricKitDoesNotAttributeHistoricalDiagnosticToDeliverySession() throws {
        let event = Event(level: .warning)
        event.timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        event.releaseName = "com.example.Baros@1.3+90"
        event.dist = "90"
        let exception = Exception(value: "MXHangDiagnostic hangDuration:3 seconds", type: "MXHangDiagnostic")
        exception.mechanism = Mechanism(type: "mx_hang_diagnostic")
        event.exceptions = [exception]
        event.tags = ["ui_surface": "active_workout", "distribution_channel": "app_store"]
        event.context = ["ui": ["schema_version": 1,
                                "exercise_count_bucket": "2_5", "set_count_bucket": "6_10"],
                         "app": ["app_version": "1.3", "app_build": "90"],
                         "trace": ["trace_id": "delivery-session-trace"]]
        event.user = User(userId: "delivery-session-user")
        event.breadcrumbs = [SentryUIHangContextSink.makeBreadcrumb(.addExercisePresented)]

        let scrubbed = try XCTUnwrap(SentryEventScrubber.scrub(event))

        XCTAssertEqual(scrubbed.timestamp, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(scrubbed.exceptions?.first?.value, "MXHangDiagnostic hangDuration:3 seconds")
        XCTAssertEqual(scrubbed.exceptions?.first?.mechanism?.type, "mx_hang_diagnostic")
        XCTAssertNil(scrubbed.releaseName)
        XCTAssertNil(scrubbed.dist)
        XCTAssertNil(scrubbed.user)
        XCTAssertNil(scrubbed.context?["app"])
        XCTAssertNil(scrubbed.context?["trace"])
        XCTAssertNil(scrubbed.tags?["ui_surface"])
        XCTAssertNil(scrubbed.context?["ui"])
        XCTAssertTrue(scrubbed.breadcrumbs?.isEmpty != false)
        let delivery = try XCTUnwrap(scrubbed.context?["diagnostic_delivery"])
        XCTAssertEqual(delivery["release"] as? String, "com.example.Baros@1.3+90")
        XCTAssertEqual(delivery["dist"] as? String, "90")
        XCTAssertEqual(delivery["ui_surface"] as? String, "active_workout")
        XCTAssertEqual(scrubbed.tags?["diagnostic_timestamp_basis"], "payload_interval_start")
    }

    func testMetricKitPreservesSampledStacksAndSymbolsForAllSupportedDiagnostics() throws {
        for mechanism in ["mx_hang_diagnostic", "mx_cpu_exception", "mx_disk_write_exception"] {
            let event = Event(level: .warning)
            let frame = Frame()
            frame.function = "loadWorkout"
            frame.instructionAddress = "0x100001000"
            let stacktrace = SentryStacktrace(frames: [frame], registers: [:])
            let thread = SentryThread(threadId: 0)
            thread.stacktrace = stacktrace
            event.threads = [thread]
            let exception = Exception(value: "system diagnostic", type: "MetricKit")
            exception.mechanism = Mechanism(type: mechanism)
            exception.stacktrace = stacktrace
            event.exceptions = [exception]
            let image = DebugMeta()
            image.type = "macho"
            image.debugID = "00112233-4455-6677-8899-AABBCCDDEEFF"
            event.debugMeta = [image]

            let scrubbed = try XCTUnwrap(SentryEventScrubber.scrub(event))

            XCTAssertTrue(scrubbed.threads?.first?.stacktrace === stacktrace)
            XCTAssertTrue(scrubbed.exceptions?.first?.stacktrace === stacktrace)
            XCTAssertEqual(scrubbed.debugMeta?.first?.debugID, "00112233-4455-6677-8899-AABBCCDDEEFF")
            XCTAssertNotNil(scrubbed.context?["diagnostic_delivery"])
            XCTAssertEqual(scrubbed.tags?["diagnostic_timestamp_basis"], "payload_interval_start")
        }
    }

    func testOrdinaryCrashRetainsIncidentReleaseUserAndUIContext() throws {
        let event = Event(level: .fatal)
        event.releaseName = "com.example.Baros@1.3+90"
        event.dist = "90"
        event.user = User(userId: "incident-user")
        event.tags = ["ui_surface": "whats_new"]
        event.context = ["ui": ["schema_version": 1, "base_screen": "home", "scene_phase": "active"]]
        event.breadcrumbs = [SentryUIHangContextSink.makeBreadcrumb(.whatsNewPresented)]

        let scrubbed = try XCTUnwrap(SentryEventScrubber.scrub(event))

        XCTAssertEqual(scrubbed.releaseName, "com.example.Baros@1.3+90")
        XCTAssertEqual(scrubbed.dist, "90")
        XCTAssertEqual(scrubbed.user?.userId, "incident-user")
        XCTAssertEqual(scrubbed.tags?["ui_surface"], "whats_new")
        XCTAssertEqual(scrubbed.context?["ui"]?["base_screen"] as? String, "home")
        XCTAssertEqual(scrubbed.breadcrumbs?.count, 1)
        XCTAssertNil(scrubbed.context?["diagnostic_delivery"])
    }

    func testAllShellSurfacesPassFilterAndRejectUnboundedOrInconsistentFields() throws {
        for surface in ["launch", "home", "history", "profile", "onboarding", "whats_new", "active_workout"] {
            let event = Event(level: .fatal)
            event.tags = ["ui_surface": surface]
            event.context = ["ui": ["schema_version": 1, "base_screen": "home", "scene_phase": "inactive"]]
            let valid = try XCTUnwrap(SentryEventScrubber.scrub(event))
            XCTAssertEqual(valid.tags?["ui_surface"], surface)
        }
        for (key, value) in [("base_screen", "My private workout"), ("scene_phase", "background"),
                             ("focused_field", "set_reps"), ("set_count_bucket", "21_plus")] {
            let event = Event(level: .fatal)
            event.tags = ["ui_surface": "onboarding"]
            var context: [String: Any] = ["schema_version": 1, "base_screen": "home"]
            context[key] = value
            event.context = ["ui": context]
            let scrubbed = try XCTUnwrap(SentryEventScrubber.scrub(event))
            XCTAssertNil(scrubbed.context?["ui"], key)
            XCTAssertNil(scrubbed.tags?["ui_surface"], key)
        }
    }

    func testLaunchPresentationRestoresUnderlyingTabAndClearsWorkoutContext() throws {
        let sink = RecordingUIHangContextSink()
        let context = UIHangContextObservability(sink: sink)
        context.launchStarted()
        XCTAssertEqual(sink.snapshots.last?.surface, .launch)
        context.shellChanged(screen: .home, presentation: .onboarding)
        XCTAssertEqual(sink.snapshots.last?.surface, .onboarding)
        XCTAssertEqual(sink.snapshots.last?.baseScreen, .home)
        context.shellChanged(screen: .home, presentation: nil)
        XCTAssertEqual(sink.snapshots.last?.surface, .home)
        context.shellChanged(screen: .history, presentation: .activeWorkout)
        context.activeWorkoutBecameCurrent(exerciseCount: 6, setCount: 21)
        context.addExercisePresented()
        context.focusChanged(to: .setReps(UUID()))
        XCTAssertEqual(sink.snapshots.last?.surface, .exercisePicker)
        XCTAssertNil(sink.snapshots.last?.focusedField)
        context.shellChanged(screen: .profile, presentation: .whatsNew)
        // Late callbacks from the dismissed workout must not replace What's New.
        context.addExerciseDismissed()
        context.activeWorkoutStructureChanged(exerciseCount: 30, setCount: 100)
        context.activeWorkoutCeasedBeingCurrent()
        XCTAssertEqual(sink.snapshots.last?.surface, .whatsNew)
        XCTAssertNil(sink.snapshots.last?.setCountBucket)
        context.shellChanged(screen: .profile, presentation: nil)
        XCTAssertEqual(sink.snapshots.last?.surface, .profile)
        XCTAssertEqual(sink.snapshots.last?.baseScreen, .profile)
        XCTAssertNil(sink.snapshots.last?.focusedField)
    }

    func testBackgroundClearsVisibleStateAndRestoresCurrentSurfaceWithoutOldFocus() {
        let sink = RecordingUIHangContextSink()
        let context = UIHangContextObservability(sink: sink)
        context.shellChanged(screen: .home, presentation: .activeWorkout)
        context.activeWorkoutBecameCurrent(exerciseCount: 2, setCount: 10)
        context.focusChanged(to: .setWeight(UUID()))
        context.sceneChanged(to: .background)
        XCTAssertEqual(sink.snapshots.last, .empty)
        context.focusChanged(to: .setReps(UUID()))
        context.shellChanged(screen: .history, presentation: nil)
        context.sceneChanged(to: .active)
        XCTAssertEqual(sink.snapshots.last?.surface, .history)
        XCTAssertNil(sink.snapshots.last?.focusedField)
        XCTAssertNil(sink.snapshots.last?.setCountBucket)
        let count = sink.breadcrumbs.count
        let snapshots = sink.snapshots.count
        context.sceneChanged(to: .active)
        context.shellChanged(screen: .history, presentation: nil)
        XCTAssertEqual(sink.breadcrumbs.count, count)
        XCTAssertEqual(sink.snapshots.count, snapshots)
    }

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

    func testUIScrubberRejectsWrongTypesUnderAllowedContextKeys() throws {
        let invalidValues: [Any] = [
            ["note": "Private workout note"],
            ["Private search text"],
            42,
            true,
            NSNull(),
        ]

        for surface in ["active_workout", "exercise_picker"] {
            for key in ["focused_field", "exercise_count_bucket", "set_count_bucket"] {
                for invalidValue in invalidValues {
                    var context: [String: Any] = [
                        "schema_version": 1,
                        "exercise_count_bucket": "2_5",
                        "set_count_bucket": "6_10",
                        "focused_field": "set_reps",
                    ]
                    context[key] = invalidValue
                    // Both failed casts used to look like absent, optional picker buckets.
                    if key != "focused_field" {
                        context["exercise_count_bucket"] = invalidValue
                        context["set_count_bucket"] = invalidValue
                    }
                    let event = Event(level: .fatal)
                    event.tags = ["ui_surface": surface, "distribution_channel": "app_store"]
                    event.context = ["ui": context]

                    let scrubbed = try XCTUnwrap(SentryUIHangEventScrubber.scrub(event))

                    XCTAssertNil(scrubbed.tags?["ui_surface"], "\(surface), \(key): \(invalidValue)")
                    XCTAssertNil(scrubbed.context?["ui"], "\(surface), \(key): \(invalidValue)")
                    XCTAssertEqual(scrubbed.tags?["distribution_channel"], "app_store")
                }
            }
        }
    }

    func testUIScrubberPreservesValidContextWithOptionalFieldsAbsent() throws {
        let contexts: [(String, [String: Any])] = [
            ("exercise_picker", ["schema_version": 1]),
            ("active_workout", [
                "schema_version": 1,
                "exercise_count_bucket": "2_5",
                "set_count_bucket": "6_10",
            ]),
        ]
        for (surface, context) in contexts {
            let event = Event(level: .fatal)
            event.tags = ["ui_surface": surface]
            event.context = ["ui": context]

            let scrubbed = try XCTUnwrap(SentryUIHangEventScrubber.scrub(event))

            XCTAssertEqual(scrubbed.tags?["ui_surface"], surface)
            XCTAssertEqual(try XCTUnwrap(scrubbed.context?["ui"]) as NSDictionary, context as NSDictionary)
        }
    }

    func testUIScrubberRequiresExactIntegerSchemaVersion() throws {
        let invalidVersions: [Any] = [true, 1.5, 1.9, 0, 2, "1", NSNull()]

        for invalidVersion in invalidVersions {
            let event = Event(level: .fatal)
            event.tags = ["ui_surface": "active_workout"]
            event.context = [
                "ui": [
                    "schema_version": invalidVersion,
                    "exercise_count_bucket": "2_5",
                    "set_count_bucket": "6_10",
                ],
            ]
            let breadcrumb = Breadcrumb(level: .info, category: "baros.ui")
            breadcrumb.type = "navigation"
            breadcrumb.message = "exercise_search_began"
            breadcrumb.setData(value: invalidVersion, key: "schema_version")
            event.breadcrumbs = [breadcrumb]

            let scrubbed = try XCTUnwrap(SentryUIHangEventScrubber.scrub(event))

            XCTAssertNil(scrubbed.tags?["ui_surface"], "context schema version: \(invalidVersion)")
            XCTAssertNil(scrubbed.context?["ui"], "context schema version: \(invalidVersion)")
            XCTAssertTrue(scrubbed.breadcrumbs?.isEmpty == true, "breadcrumb schema version: \(invalidVersion)")
        }
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
