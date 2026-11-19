import Sentry
import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class SyncObservabilityTests: XCTestCase {
    func testSetSaveReportingSuppressesDiskBackedAndInMemoryUIFixtures() {
        for arguments in [
            ["Baros", "--uitest-in-memory-store"],
            ["Baros", "--uitest-force-signed-out-auth"],
            ["Baros", "--uitest-force-signed-in-auth", "--uitest-reset-app-appearance"],
        ] {
            XCTAssertTrue(SentrySetSaveFailureReporter.isTestProcess(arguments: arguments, hasXCTest: false))
        }
        XCTAssertTrue(SentrySetSaveFailureReporter.isTestProcess(arguments: ["Baros"], hasXCTest: true))
        XCTAssertFalse(SentrySetSaveFailureReporter.isTestProcess(arguments: ["Baros"], hasXCTest: false))
    }

    func testInjectedUnitTestFailuresCannotSendEvenWithProductionSentryEnabled() {
        let info: [String: Any] = ["SentryDSN": "https://public@example.com/1",
                                   "SentryEnabled": "YES", "BarosEnvironment": "Production"]
        XCTAssertTrue(SentryRuntimeConfiguration(info: info).isEnabled)
        let failure = ActiveWorkoutSetSaveFailure(operation: .completion, error: CocoaError(.fileWriteUnknown))
        SentrySetSaveFailureReporter.capture(failure, info: info, send: { _ in
            XCTFail("Synthetic unit-test failure must not reach Sentry")
        })
    }

    func testSetSaveFailureScrubsModelDataAndKeepsIncidentBuild() throws {
        let failure = ActiveWorkoutSetSaveFailure(operation: .fieldEdit,
            error: NSError(domain: NSCocoaErrorDomain, code: 640,
                           userInfo: [NSLocalizedDescriptionKey: "Private workout", "weight": 120]))
        let event = SentrySetSaveFailureReporter.makeEvent(failure)
        event.releaseName = "baros@1.3+90"
        event.dist = "90"
        event.tags?["workout_name"] = "Private workout"
        event.tags?["ui_surface"] = "active_workout"
        event.context = ["ui": ["focused_field": "set_weight"], "os": ["name": "iOS"],
                         "workout": ["weight": 120], "trace": ["trace_id": "private-trace"]]
        event.user = User(userId: "private-user")
        event.extra = ["model": "private-model"]
        event.exceptions = [Exception(value: "private-error", type: "NSError")]
        event.breadcrumbs = [SentryUIHangContextSink.makeBreadcrumb(.addExercisePresented)]
        let scrubbed = try XCTUnwrap(SentryEventScrubber.scrub(event))
        XCTAssertEqual(scrubbed.releaseName, "baros@1.3+90")
        XCTAssertEqual(scrubbed.dist, "90")
        XCTAssertEqual(scrubbed.tags, ["component": "local_persistence", "operation": "field_edit",
                                      "error_domain": NSCocoaErrorDomain, "error_code": "640"])
        XCTAssertEqual(scrubbed.fingerprint, ["baros-set-save-v1", "field_edit", NSCocoaErrorDomain, "640"])
        XCTAssertEqual(Set(scrubbed.context?.keys ?? Dictionary<String, [String: Any]>().keys), ["os"])
        XCTAssertNil(scrubbed.user)
        XCTAssertNil(scrubbed.extra)
        XCTAssertNil(scrubbed.exceptions)
        XCTAssertNil(scrubbed.breadcrumbs)
        XCTAssertNil(scrubbed.context?["diagnostic_delivery"])
    }

    func testSetSaveFailureBoundsUnknownErrorsAndRejectsInvalidTags() throws {
        let failure = ActiveWorkoutSetSaveFailure(operation: .rpe,
            error: NSError(domain: "Private workout name", code: 120, userInfo: nil))
        let event = SentrySetSaveFailureReporter.makeEvent(failure)
        XCTAssertEqual(event.tags?["error_domain"], "other")
        XCTAssertEqual(event.tags?["error_code"], "unknown")
        event.tags?["error_domain"] = "Private workout name"
        XCTAssertNil(SentryEventScrubber.scrub(event))
    }

    func testSetSaveReportingLeavesMetricKitEventsOnTheirExistingRoute() throws {
        let event = Event(level: .warning)
        let exception = Exception(value: "system diagnostic", type: "MXHangDiagnostic")
        exception.mechanism = Mechanism(type: "mx_hang_diagnostic")
        event.exceptions = [exception]
        let scrubbed = try XCTUnwrap(SentryEventScrubber.scrub(event))
        XCTAssertEqual(scrubbed.exceptions?.first?.mechanism?.type, "mx_hang_diagnostic")
        XCTAssertNotEqual(scrubbed.tags?["component"], "local_persistence")
        XCTAssertNotEqual(scrubbed.logger, "baros.local_persistence")
    }

    func testSentryMappingAndScrubberRemoveNonAllowlistedData() throws {
        let ownerID = "owner_v1_0123456789abcdef0123456789abcdef"
        let observation = SanitizedSyncObservation(
            kind: .durableFailure,
            level: .error,
            phase: .push,
            entityKind: .exercise,
            operation: .update,
            outcome: .failure,
            failureCategory: .outbox,
            errorCode: .failedOutboxPush,
            counts: SyncObservationCounts(attempt: 2, pending: 1, failed: 1),
            fingerprint: [
                "baros-sync-v1", "push", "exercises", "update",
                "outbox", "failed_outbox_push", "failure",
            ],
            pseudonymousCurrentOwnerID: try XCTUnwrap(
                PseudonymousCurrentOwnerID(sentryValue: ownerID)
            )
        )
        let event = SentrySyncObservationSink.makeEvent(from: observation)
        event.extra = ["raw_owner": "issuer|owner_private"]
        event.context?["secret"] = ["workout_notes": "private content"]
        event.user?.email = "private@example.com"
        let unrelatedBreadcrumb = Breadcrumb(level: .info, category: "navigation")
        unrelatedBreadcrumb.message = "Private Workout"
        event.breadcrumbs = [
            unrelatedBreadcrumb,
            SentrySyncObservationSink.makeBreadcrumb(from: observation),
        ]

        let scrubbed = try XCTUnwrap(SentrySyncEventScrubber.scrub(event))

        XCTAssertEqual(scrubbed.tags?["component"], "sync")
        XCTAssertEqual(scrubbed.fingerprint, observation.fingerprint)
        XCTAssertEqual(scrubbed.user?.userId, ownerID)
        XCTAssertNil(scrubbed.user?.email)
        XCTAssertNil(scrubbed.extra)
        XCTAssertNil(scrubbed.context?["secret"])
        XCTAssertEqual(scrubbed.breadcrumbs?.map(\.category), ["baros.sync"])
        XCTAssertFalse(String(describing: scrubbed.context).contains("private content"))
    }

    func testSentryScrubberRejectsMalformedSyncEventInsteadOfSendingIt() {
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: "Durable Sync Failure")
        event.tags = [
            "component": "sync",
            "schema_version": "1",
            "arbitrary_key": "private value",
        ]
        event.fingerprint = [
            "baros-sync-v1", "push", "exercises", "update",
            "outbox", "failed_outbox_push", "failure",
        ]

        XCTAssertNil(SentrySyncEventScrubber.scrub(event))
    }

    func testSentryScrubberRejectsInconsistentValuesAndDropsMalformedBreadcrumbs() throws {
        let observation = SanitizedSyncObservation(
            kind: .durableFailure,
            level: .error,
            phase: .push,
            entityKind: .exercise,
            operation: .update,
            outcome: .failure,
            failureCategory: .outbox,
            errorCode: .failedOutboxPush,
            counts: SyncObservationCounts(attempt: 2, pending: 1, failed: 1),
            fingerprint: [
                "baros-sync-v1", "push", "exercises", "update",
                "outbox", "failed_outbox_push", "failure",
            ],
            pseudonymousCurrentOwnerID: nil
        )
        let event = SentrySyncObservationSink.makeEvent(from: observation)
        let malformedBreadcrumb = Breadcrumb(level: .info, category: "baros.sync")
        malformedBreadcrumb.type = "default"
        malformedBreadcrumb.message = "raw private diagnostic"
        malformedBreadcrumb.setData(value: "private value", key: "arbitrary")
        event.breadcrumbs = [
            malformedBreadcrumb,
            SentrySyncObservationSink.makeBreadcrumb(from: observation),
        ]

        let scrubbed = try XCTUnwrap(SentrySyncEventScrubber.scrub(event))
        XCTAssertEqual(scrubbed.breadcrumbs?.count, 1)
        XCTAssertEqual(scrubbed.breadcrumbs?.first?.message, "sync_lifecycle")

        let inconsistentEvent = SentrySyncObservationSink.makeEvent(from: observation)
        inconsistentEvent.tags?["sync_phase"] = "pull"
        XCTAssertNil(SentrySyncEventScrubber.scrub(inconsistentEvent))
    }

    func testCompositeScrubberKeepsSyncPrivacyBoundaryWhenUIContextIsActive() throws {
        let observation = SanitizedSyncObservation(
            kind: .durableFailure,
            level: .error,
            phase: .push,
            entityKind: .exercise,
            operation: .update,
            outcome: .failure,
            failureCategory: .outbox,
            errorCode: .failedOutboxPush,
            counts: SyncObservationCounts(attempt: 1, pending: 1, failed: 1),
            fingerprint: [
                "baros-sync-v1", "push", "exercises", "update",
                "outbox", "failed_outbox_push", "failure",
            ],
            pseudonymousCurrentOwnerID: nil
        )
        let event = SentrySyncObservationSink.makeEvent(from: observation)
        event.tags?["ui_surface"] = "active_workout"
        event.context?["ui"] = [
            "schema_version": 1,
            "exercise_count_bucket": "2_5",
            "set_count_bucket": "6_10",
            "focused_field": "set_reps",
        ]
        event.breadcrumbs = [
            SentrySyncObservationSink.makeBreadcrumb(from: observation),
            SentryUIHangContextSink.makeBreadcrumb(.addExercisePresented),
        ]

        let scrubbed = try XCTUnwrap(SentryEventScrubber.scrub(event))

        XCTAssertNil(scrubbed.tags?["ui_surface"])
        XCTAssertNil(scrubbed.context?["ui"])
        XCTAssertEqual(scrubbed.breadcrumbs?.map(\.category), ["baros.sync"])
    }
}
