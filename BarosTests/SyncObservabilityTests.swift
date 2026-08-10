import Sentry
import XCTest
@testable import Baros

@MainActor
final class SyncObservabilityTests: XCTestCase {
    func testRepeatedDurableFailuresAreAllRecordedWithTheSameFingerprint() {
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        observability.setCurrentOwner("issuer|owner_a")
        let failure = DurableSyncFailure(
            phase: .push,
            entityKind: .exercise,
            operation: .update,
            category: .outbox,
            errorCode: .failedOutboxPush,
            counts: SyncObservationCounts(attempt: 3, pending: 2, failed: 1)
        )

        observability.record(.durableFailure(failure))
        observability.record(.durableFailure(failure))

        let failures = sink.observations.filter { $0.kind == .durableFailure }
        XCTAssertEqual(failures.count, 2)
        XCTAssertEqual(failures[0].fingerprint, failures[1].fingerprint)
        XCTAssertEqual(failures[0].fingerprint, [
            "baros-sync-v1", "push", "exercises", "update",
            "outbox", "failed_outbox_push", "failure",
        ])
    }

    func testDifferentFailureCategoriesProduceDifferentFingerprints() {
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)

        observability.record(.durableFailure(DurableSyncFailure(
            phase: .push,
            entityKind: .exercise,
            operation: .update,
            category: .outbox,
            errorCode: .failedOutboxPush
        )))
        observability.record(.durableFailure(DurableSyncFailure(
            phase: .pull,
            category: .remotePull,
            errorCode: .incompleteRemotePull
        )))

        let failures = sink.observations.filter { $0.kind == .durableFailure }
        XCTAssertNotEqual(failures[0].fingerprint, failures[1].fingerprint)
    }

    func testOwnerPseudonymIsStableAcrossInstancesAndRawOwnerIsAbsent() throws {
        let firstSink = RecordingSyncObservationSink()
        let secondSink = RecordingSyncObservationSink()
        let first = SyncObservability(sink: firstSink)
        let second = SyncObservability(sink: secondSink)
        let rawOwner = "https://clerk.baros.fit|user_private_123"

        first.setCurrentOwner(rawOwner)
        second.setCurrentOwner(rawOwner)
        let failure = DurableSyncFailure(
            phase: .pull,
            category: .remotePull,
            errorCode: .incompleteRemotePull
        )
        first.record(.durableFailure(failure))
        second.record(.durableFailure(failure))

        let firstPseudonym = try XCTUnwrap(
            firstSink.observations.last?.pseudonymousCurrentOwnerID
        ).sentryValue
        let secondPseudonym = try XCTUnwrap(
            secondSink.observations.last?.pseudonymousCurrentOwnerID
        ).sentryValue
        XCTAssertEqual(firstPseudonym, secondPseudonym)
        XCTAssertTrue(firstPseudonym.hasPrefix("owner_v1_"))
        XCTAssertFalse(firstPseudonym.contains(rawOwner))
    }

    func testOwnerChangeAndSignOutReplaceThenClearSyncEventAttribution() {
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)
        let failure = DurableSyncFailure(
            phase: .pull,
            category: .remotePull,
            errorCode: .incompleteRemotePull
        )

        observability.setCurrentOwner("issuer|owner_a")
        observability.record(.durableFailure(failure))
        observability.setCurrentOwner("issuer|owner_b")
        observability.record(.durableFailure(failure))
        observability.setCurrentOwner(nil)
        observability.record(.durableFailure(failure))

        let events = sink.observations.filter { $0.kind == .durableFailure }
        XCTAssertEqual(events.count, 3)
        XCTAssertNotEqual(
            events[0].pseudonymousCurrentOwnerID,
            events[1].pseudonymousCurrentOwnerID
        )
        XCTAssertNil(events[2].pseudonymousCurrentOwnerID)
    }

    func testCountsAreBoundedBeforeTheyReachTheSink() {
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)

        observability.record(.durableFailure(DurableSyncFailure(
            phase: .push,
            category: .outbox,
            errorCode: .failedOutboxPush,
            counts: SyncObservationCounts(
                attempt: -1,
                pending: 50_000,
                failed: 50_000
            )
        )))

        let failure = sink.observations.first { $0.kind == .durableFailure }
        XCTAssertEqual(failure?.counts.attempt, 0)
        XCTAssertEqual(failure?.counts.pending, 1_000)
        XCTAssertEqual(failure?.counts.failed, 1_000)
    }

    func testProductionConfigurationRequiresExplicitFlagAndNonEmptyDSN() throws {
        let enabled = SentryRuntimeConfiguration(info: [
            "SentryEnabled": "YES",
            "SentryDSN": "https://public@example.invalid/1",
            "BarosEnvironment": "Production",
            "CFBundleIdentifier": "com.example.Baros",
            "CFBundleShortVersionString": "1.1",
            "CFBundleVersion": "42",
        ])
        let missingDSN = SentryRuntimeConfiguration(info: [
            "SentryEnabled": "YES",
            "SentryDSN": "",
            "BarosEnvironment": "Production",
        ])
        let debug = SentryRuntimeConfiguration(info: [
            "SentryEnabled": "NO",
            "SentryDSN": "https://public@example.invalid/1",
            "BarosEnvironment": "Development",
        ])

        XCTAssertTrue(enabled.isEnabled)
        XCTAssertEqual(enabled.releaseName, "com.example.Baros@1.1+42")
        XCTAssertEqual(enabled.dist, "42")
        XCTAssertEqual(enabled.environment, "production")
        XCTAssertFalse(missingDSN.isEnabled)
        XCTAssertFalse(debug.isEnabled)
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

    func testLifecycleFactsProduceSafePhaseAndFailureBreadcrumbs() {
        let sink = RecordingSyncObservationSink()
        let observability = SyncObservability(sink: sink)

        observability.record(.syncPhaseCompleted(.pull))
        observability.record(.durableFailure(DurableSyncFailure(
            phase: .push,
            entityKind: .exercise,
            operation: .update,
            category: .outbox,
            errorCode: .failedOutboxPush
        )))

        let breadcrumbs = sink.observations.filter { $0.kind == .breadcrumb }
        XCTAssertEqual(breadcrumbs.map(\.outcome), [.completed, .failure])
        XCTAssertEqual(breadcrumbs.map(\.phase), [.pull, .push])
        XCTAssertEqual(
            sink.observations.filter { $0.kind == .durableFailure }.count,
            1
        )
    }

    func testTransientSyncConditionClassifierMapsConnectivityTimeoutAndCancellation() {
        XCTAssertEqual(
            TransientSyncConditionClassifier.errorCode(for: URLError(.notConnectedToInternet)),
            .networkUnavailable
        )
        XCTAssertEqual(
            TransientSyncConditionClassifier.errorCode(for: URLError(.timedOut)),
            .requestTimedOut
        )
        XCTAssertEqual(
            TransientSyncConditionClassifier.errorCode(for: URLError(.cancelled)),
            .cancelled
        )
        XCTAssertNil(
            TransientSyncConditionClassifier.errorCode(for: NSError(
                domain: "BarosTests",
                code: 1
            ))
        )
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
}

@MainActor
final class RecordingSyncObservationSink: SyncObservationSink {
    private(set) var observations: [SanitizedSyncObservation] = []

    func record(_ observation: SanitizedSyncObservation) {
        observations.append(observation)
    }
}
