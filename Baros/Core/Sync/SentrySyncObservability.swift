import CoreFoundation
import Foundation
import Sentry
import StoreKit

@MainActor
enum SentryRuntime {
    static func startIfEnabled(bundle: Bundle = .main) -> any SyncObserving {
        let configuration = SentryRuntimeConfiguration(info: bundle.infoDictionary ?? [:])
        guard configuration.isEnabled else {
            return DisabledSyncObservability.shared
        }

        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.environment = configuration.environment
            options.releaseName = configuration.releaseName
            options.dist = configuration.dist
            options.sampleRate = 1.0

            options.sendDefaultPii = false
            options.enableCaptureFailedRequests = false
            options.enableNetworkBreadcrumbs = false
            options.enableLogs = false
            options.enableMetrics = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.beforeSend = SentryEventScrubber.scrub
        }

        UIHangContextObservability.shared.install(sink: SentryUIHangContextSink())

        Task { @MainActor in
            await SentryDistributionChannelTagger.updateTag()
        }
        return SyncObservability(sink: SentrySyncObservationSink())
    }
}

enum SentryEventScrubber {
    static func scrub(_ event: Event) -> Event? {
        if event.tags?["component"] == "sync" {
            // Sync events retain their original strict allowlist. UI scope data
            // is useful for automatic hangs, but is intentionally excluded
            // from manually captured durable sync failures.
            event.tags?.removeValue(forKey: "ui_surface")
            event.context?.removeValue(forKey: "ui")
            return SentrySyncEventScrubber.scrub(event)
        }
        guard let syncScrubbedEvent = SentrySyncEventScrubber.scrub(event) else {
            return nil
        }
        return SentryUIHangEventScrubber.scrub(syncScrubbedEvent)
    }
}

@MainActor
final class SentryUIHangContextSink: UIHangContextSink {
    private static let surfaceTagKey = "ui_surface"
    private static let contextKey = "ui"

    func apply(_ snapshot: UIHangContextSnapshot) {
        let tags = Self.tagValues(for: snapshot)
        let context = Self.contextValues(for: snapshot)
        SentrySDK.configureScope { scope in
            if let surface = tags[Self.surfaceTagKey] {
                scope.setTag(value: surface, key: Self.surfaceTagKey)
            } else {
                scope.removeTag(key: Self.surfaceTagKey)
            }
            if context.isEmpty {
                scope.removeContext(key: Self.contextKey)
            } else {
                scope.setContext(value: context, key: Self.contextKey)
            }
        }
    }

    func addBreadcrumb(_ breadcrumb: UIHangBreadcrumb) {
        SentrySDK.addBreadcrumb(Self.makeBreadcrumb(breadcrumb))
    }

    static func tagValues(for snapshot: UIHangContextSnapshot) -> [String: String] {
        guard let surface = snapshot.surface else { return [:] }
        return [surfaceTagKey: surface.rawValue]
    }

    static func contextValues(for snapshot: UIHangContextSnapshot) -> [String: Any] {
        guard snapshot.surface != nil else { return [:] }
        var context: [String: Any] = ["schema_version": 1]
        if let exerciseCountBucket = snapshot.exerciseCountBucket {
            context["exercise_count_bucket"] = exerciseCountBucket.rawValue
        }
        if let setCountBucket = snapshot.setCountBucket {
            context["set_count_bucket"] = setCountBucket.rawValue
        }
        if let focusedField = snapshot.focusedField {
            context["focused_field"] = focusedField.rawValue
        }
        return context
    }

    static func makeBreadcrumb(_ transition: UIHangBreadcrumb) -> Breadcrumb {
        let breadcrumb = Breadcrumb(level: .info, category: "baros.ui")
        breadcrumb.type = "navigation"
        breadcrumb.message = transition.rawValue
        breadcrumb.setData(value: 1, key: "schema_version")
        return breadcrumb
    }
}

enum SentryUIHangEventScrubber {
    private static let allowedContextKeys: Set<String> = [
        "schema_version",
        "exercise_count_bucket",
        "set_count_bucket",
        "focused_field",
    ]

    static func scrub(_ event: Event) -> Event? {
        let surface = event.tags?["ui_surface"]
        let context = event.context?["ui"]
        if let surface, let context, isValid(surface: surface, context: context) {
            // The scope already contains only approved typed values.
        } else {
            event.tags?.removeValue(forKey: "ui_surface")
            event.context?.removeValue(forKey: "ui")
        }
        event.breadcrumbs = event.breadcrumbs?.filter { breadcrumb in
            breadcrumb.category != "baros.ui" || isValidUIBreadcrumb(breadcrumb)
        }
        return event
    }

    private static func isValid(surface: String, context: [String: Any]) -> Bool {
        guard UIHangSurface(rawValue: surface) != nil,
              Set(context.keys).isSubset(of: allowedContextKeys),
              isExactSchemaVersionOne(context["schema_version"]) else {
            return false
        }

        // A failed cast must not make a present value look like an absent
        // optional field: nested data must never survive under an approved key.
        for key in ["exercise_count_bucket", "set_count_bucket", "focused_field"] {
            if let value = context[key], !(value is String) {
                return false
            }
        }

        let exerciseBucket = context["exercise_count_bucket"] as? String
        let setBucket = context["set_count_bucket"] as? String
        guard (exerciseBucket == nil) == (setBucket == nil),
              exerciseBucket.map({ UIHangCountBucket(rawValue: $0) != nil }) ?? true,
              setBucket.map({ UIHangCountBucket(rawValue: $0) != nil }) ?? true else {
            return false
        }
        if surface == UIHangSurface.activeWorkout.rawValue,
           exerciseBucket == nil || setBucket == nil {
            return false
        }
        if let focusedField = context["focused_field"] as? String,
           UIHangFocusedField(rawValue: focusedField) == nil {
            return false
        }
        return true
    }

    private static func isValidUIBreadcrumb(_ breadcrumb: Breadcrumb) -> Bool {
        guard breadcrumb.type == "navigation",
              let message = breadcrumb.message,
              UIHangBreadcrumb(rawValue: message) != nil,
              let data = breadcrumb.data as? [String: Any],
              Set(data.keys) == ["schema_version"],
              isExactSchemaVersionOne(data["schema_version"]) else {
            return false
        }
        return true
    }

    private static func isExactSchemaVersionOne(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return false
        }
        return number.doubleValue == 1
    }
}

@MainActor
final class SentrySyncObservationSink: SyncObservationSink {
    func record(_ observation: SanitizedSyncObservation) {
        if observation.kind.eventMessage != nil {
            SentrySDK.capture(event: Self.makeEvent(from: observation))
        } else {
            SentrySDK.addBreadcrumb(Self.makeBreadcrumb(from: observation))
        }
    }

    static func makeBreadcrumb(from observation: SanitizedSyncObservation) -> Breadcrumb {
        let breadcrumb = Breadcrumb(
            level: sentryLevel(for: observation.level),
            category: "baros.sync"
        )
        breadcrumb.type = "default"
        breadcrumb.message = "sync_lifecycle"
        for (key, value) in tags(for: observation) {
            breadcrumb.setData(value: value, key: key)
        }
        return breadcrumb
    }

    static func makeEvent(from observation: SanitizedSyncObservation) -> Event {
        let event = Event(level: sentryLevel(for: observation.level))
        guard let message = observation.kind.eventMessage else {
            preconditionFailure("Breadcrumb observations cannot be mapped to Sentry events")
        }
        event.message = SentryMessage(formatted: message)
        event.logger = "baros.sync"
        event.tags = tags(for: observation)
        event.context = [
            "sync": [
                "attempt_count": observation.counts.attempt,
                "pending_outbox_count": observation.counts.pending,
                "failed_outbox_count": observation.counts.failed,
                "classifier_version": 1,
            ],
        ]
        event.fingerprint = observation.fingerprint
        event.user = observation.pseudonymousCurrentOwnerID.map { User(userId: $0.sentryValue) }
        return event
    }

    private static func tags(for observation: SanitizedSyncObservation) -> [String: String] {
        [
            "component": "sync",
            "schema_version": "1",
            "sync_phase": observation.phase.rawValue,
            "entity_kind": observation.entityKind?.rawValue ?? "none",
            "operation": observation.operation?.rawValue ?? "none",
            "outcome": observation.outcome.rawValue,
            "failure_category": observation.failureCategory?.rawValue ?? "none",
            "error_code": observation.errorCode.rawValue,
        ]
    }

    private static func sentryLevel(for level: SyncObservationLevel) -> SentryLevel {
        switch level {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }
}

enum SentrySyncEventScrubber {
    private static let requiredTagKeys: Set<String> = [
        "component",
        "schema_version",
        "sync_phase",
        "entity_kind",
        "operation",
        "outcome",
        "failure_category",
        "error_code",
    ]
    private static let allowedTagKeys = requiredTagKeys.union([
        "distribution_channel",
    ])
    private static let allowedContextKeys: Set<String> = [
        "app",
        "culture",
        "device",
        "os",
        "runtime",
        "sync",
        "trace",
    ]
    private static let allowedSyncContextKeys: Set<String> = [
        "attempt_count",
        "pending_outbox_count",
        "failed_outbox_count",
        "classifier_version",
    ]
    private static let durableErrorCodes: Set<String> = [
        SyncStableErrorCode.failedOutboxPush.rawValue,
        SyncStableErrorCode.incompleteRemotePull.rawValue,
        SyncStableErrorCode.syncRunFailed.rawValue,
        SyncStableErrorCode.ownerMismatch.rawValue,
    ]

    static func scrub(_ event: Event) -> Event? {
        guard event.tags?["component"] == "sync" else {
            return event
        }
        guard let tags = event.tags,
              areValidCommonTags(tags, allowsDistributionChannel: true),
              let outcome = tags["outcome"],
              outcome == SyncObservationOutcome.failure.rawValue,
              let errorCode = tags["error_code"],
              durableErrorCodes.contains(errorCode),
              tags["failure_category"] != "none",
              (tags["entity_kind"] == "none") == (tags["operation"] == "none"),
              let fingerprint = event.fingerprint,
              let formattedMessage = event.message?.formatted,
              formattedMessage == "Durable Sync Failure",
              fingerprint == [
                "baros-sync-v1",
                tags["sync_phase"]!,
                tags["entity_kind"]!,
                tags["operation"]!,
                tags["failure_category"]!,
                errorCode,
                outcome,
              ] else {
            return nil
        }

        if let ownerID = event.user?.userId {
            guard let pseudonymousCurrentOwnerID = PseudonymousCurrentOwnerID(sentryValue: ownerID) else {
                return nil
            }
            event.user = User(userId: pseudonymousCurrentOwnerID.sentryValue)
        } else {
            event.user = nil
        }

        guard let syncContext = event.context?["sync"],
              Set(syncContext.keys) == allowedSyncContextKeys,
              areValidSyncContextValues(syncContext) else {
            return nil
        }

        event.tags = tags.filter { allowedTagKeys.contains($0.key) }
        event.context = event.context?.filter { allowedContextKeys.contains($0.key) }
        event.breadcrumbs = event.breadcrumbs?.filter(isValidSyncBreadcrumb)
        event.request = nil
        event.extra = nil
        event.serverName = nil
        event.exceptions = nil
        event.threads = nil
        event.stacktrace = nil
        return event
    }

    private static func areValidCommonTags(
        _ tags: [String: String],
        allowsDistributionChannel: Bool
    ) -> Bool {
        let keys = Set(tags.keys)
        guard requiredTagKeys.isSubset(of: keys),
              keys.isSubset(of: allowsDistributionChannel ? allowedTagKeys : requiredTagKeys),
              tags.values.allSatisfy({ !$0.isEmpty && $0.count <= 64 }),
              tags["component"] == "sync",
              tags["schema_version"] == "1",
              Set(SyncObservationPhase.allCases.map(\.rawValue)).contains(tags["sync_phase"] ?? ""),
              Set(SyncEntityKind.allCases.map(\.rawValue) + ["none"]).contains(tags["entity_kind"] ?? ""),
              Set(SyncOperation.allCases.map(\.rawValue) + ["none"]).contains(tags["operation"] ?? ""),
              Set(SyncObservationOutcome.allCases.map(\.rawValue)).contains(tags["outcome"] ?? ""),
              Set(SyncFailureCategory.allCases.map(\.rawValue) + ["none"]).contains(tags["failure_category"] ?? ""),
              Set(SyncStableErrorCode.allCases.map(\.rawValue)).contains(tags["error_code"] ?? "") else {
            return false
        }
        if let distributionChannel = tags["distribution_channel"] {
            return distributionChannel == "testflight" || distributionChannel == "app_store"
        }
        return true
    }

    private static func areValidSyncContextValues(_ context: [String: Any]) -> Bool {
        for (key, value) in context {
            guard let number = value as? NSNumber else { return false }
            let integer = number.intValue
            guard number.doubleValue == Double(integer) else { return false }
            if key == "classifier_version" {
                guard integer == 1 else { return false }
            } else {
                guard (0...1_000).contains(integer) else { return false }
            }
        }
        return true
    }

    private static func isValidSyncBreadcrumb(_ breadcrumb: Breadcrumb) -> Bool {
        guard breadcrumb.category == "baros.sync",
              breadcrumb.type == "default",
              breadcrumb.message == "sync_lifecycle",
              let data = breadcrumb.data as? [String: String] else {
            return false
        }
        return areValidCommonTags(data, allowsDistributionChannel: false)
    }
}

private extension SyncObservationKind {
    var eventMessage: String? {
        switch self {
        case .durableFailure:
            "Durable Sync Failure"
        case .breadcrumb:
            nil
        }
    }
}

@MainActor
private enum SentryDistributionChannelTagger {
    static func updateTag() async {
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result else {
            return
        }

        let channel: String
        if transaction.environment == .sandbox {
            channel = "testflight"
        } else if transaction.environment == .production {
            channel = "app_store"
        } else {
            return
        }

        SentrySDK.configureScope { scope in
            scope.setTag(value: channel, key: "distribution_channel")
        }
    }
}
