import CryptoKit
import Foundation

enum SyncObservationPhase: String, CaseIterable, Equatable {
    case scheduler
    case push
    case pull
    case ownership
    case recovery
}

enum SyncObservationOutcome: String, CaseIterable, Equatable {
    case requested
    case retrying
    case completed
    case paused
    case failure
    case recovered
    case changed
}

enum SyncFailureCategory: String, CaseIterable, Equatable {
    case outbox
    case remotePull = "remote_pull"
    case clientCall = "client_call"
    case ownership
}

enum SyncStableErrorCode: String, CaseIterable, Equatable {
    case failedOutboxPush = "failed_outbox_push"
    case incompleteRemotePull = "incomplete_remote_pull"
    case clientCallFailed = "client_call_failed"
    case ownerMismatch = "owner_mismatch"
    case noCurrentOwner = "no_current_owner"
    case authorizationUnavailable = "authorization_unavailable"
    case deletionMode = "deletion_mode"
    case cancelled
    case authenticationFailed = "authentication_failed"
    case currentOwnerChanged = "current_owner_changed"
    case syncRequested = "sync_requested"
    case syncRetryRequested = "sync_retry_requested"
    case syncPhaseCompleted = "sync_phase_completed"
    case networkUnavailable = "network_unavailable"
    case requestTimedOut = "request_timed_out"
}

struct SyncObservationCounts: Equatable {
    private static let maximum = 1_000

    let attempt: Int
    let pending: Int
    let failed: Int
    let recovered: Int

    init(
        attempt: Int = 0,
        pending: Int = 0,
        failed: Int = 0,
        recovered: Int = 0
    ) {
        self.attempt = Self.bounded(attempt)
        self.pending = Self.bounded(pending)
        self.failed = Self.bounded(failed)
        self.recovered = Self.bounded(recovered)
    }

    private static func bounded(_ value: Int) -> Int {
        min(maximum, max(0, value))
    }
}

struct DurableSyncFailure: Equatable {
    let phase: SyncObservationPhase
    let entityKind: SyncEntityKind?
    let operation: SyncOperation?
    let category: SyncFailureCategory
    let errorCode: SyncStableErrorCode
    let counts: SyncObservationCounts

    init(
        phase: SyncObservationPhase,
        entityKind: SyncEntityKind? = nil,
        operation: SyncOperation? = nil,
        category: SyncFailureCategory,
        errorCode: SyncStableErrorCode,
        counts: SyncObservationCounts = SyncObservationCounts()
    ) {
        self.phase = phase
        self.entityKind = entityKind
        self.operation = operation
        self.category = category
        self.errorCode = errorCode
        self.counts = counts
    }
}

enum SyncLifecycleFact: Equatable {
    case syncRequested(isRetry: Bool)
    case syncPhaseCompleted(SyncObservationPhase)
    case transient(phase: SyncObservationPhase, errorCode: SyncStableErrorCode)
    case durableFailure(DurableSyncFailure)
    case syncSucceeded(counts: SyncObservationCounts)
}

enum SyncObservationKind: Equatable {
    case breadcrumb
    case durableFailure
    case recovery
}

enum SyncObservationLevel: Equatable {
    case info
    case warning
    case error
}

struct SanitizedSyncObservation: Equatable {
    let kind: SyncObservationKind
    let level: SyncObservationLevel
    let phase: SyncObservationPhase
    let entityKind: SyncEntityKind?
    let operation: SyncOperation?
    let outcome: SyncObservationOutcome
    let failureCategory: SyncFailureCategory?
    let errorCode: SyncStableErrorCode
    let counts: SyncObservationCounts
    let fingerprint: [String]
    let pseudonymousCurrentOwnerID: PseudonymousCurrentOwnerID?
}

struct PseudonymousCurrentOwnerID: Equatable {
    private static let domain = "baros-sync-current-owner-v1:"
    private static let sentryPrefix = "owner_v1_"

    let sentryValue: String

    init(currentOwnerTokenIdentifier: String) {
        let digest = SHA256.hash(data: Data((Self.domain + currentOwnerTokenIdentifier).utf8))
        let digestPrefix = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        sentryValue = Self.sentryPrefix + digestPrefix
    }

    init?(sentryValue: String) {
        guard sentryValue.hasPrefix(Self.sentryPrefix), sentryValue.count == 41 else {
            return nil
        }
        let digest = sentryValue.dropFirst(Self.sentryPrefix.count)
        guard digest.allSatisfy({ character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }) else {
            return nil
        }
        self.sentryValue = sentryValue
    }
}

@MainActor
protocol SyncObservationSink: AnyObject {
    func setPseudonymousCurrentOwnerID(_ pseudonymousCurrentOwnerID: PseudonymousCurrentOwnerID?)
    func record(_ observation: SanitizedSyncObservation)
}

@MainActor
protocol SyncObserving: AnyObject {
    func setCurrentOwner(_ ownerTokenIdentifier: String?)
    func record(_ fact: SyncLifecycleFact)
}

@MainActor
final class SyncObservability: SyncObserving {
    private let sink: any SyncObservationSink
    private var pseudonymousCurrentOwnerID: PseudonymousCurrentOwnerID?
    private var activeFailure: DurableSyncFailure?

    init(sink: any SyncObservationSink) {
        self.sink = sink
    }

    func setCurrentOwner(_ ownerTokenIdentifier: String?) {
        let newPseudonymousCurrentOwnerID = ownerTokenIdentifier.map {
            PseudonymousCurrentOwnerID(currentOwnerTokenIdentifier: $0)
        }
        guard newPseudonymousCurrentOwnerID != pseudonymousCurrentOwnerID else { return }

        pseudonymousCurrentOwnerID = newPseudonymousCurrentOwnerID
        activeFailure = nil
        sink.setPseudonymousCurrentOwnerID(newPseudonymousCurrentOwnerID)
        recordBreadcrumb(
            phase: .ownership,
            outcome: .changed,
            errorCode: .currentOwnerChanged
        )
    }

    func record(_ fact: SyncLifecycleFact) {
        switch fact {
        case .syncRequested(let isRetry):
            recordBreadcrumb(
                phase: .scheduler,
                outcome: isRetry ? .retrying : .requested,
                errorCode: isRetry ? .syncRetryRequested : .syncRequested
            )
        case .syncPhaseCompleted(let phase):
            recordBreadcrumb(
                phase: phase,
                outcome: .completed,
                errorCode: .syncPhaseCompleted
            )
        case let .transient(phase, errorCode):
            recordBreadcrumb(
                phase: phase,
                outcome: .paused,
                errorCode: errorCode
            )
        case .durableFailure(let failure):
            activeFailure = failure
            let observation = Self.makeFailureObservation(
                failure,
                pseudonymousCurrentOwnerID: pseudonymousCurrentOwnerID
            )
            recordEventWithLifecycleBreadcrumb(observation)
        case .syncSucceeded(let counts):
            guard let activeFailure else { return }
            self.activeFailure = nil
            let observation = Self.makeRecoveryObservation(
                from: activeFailure,
                counts: counts,
                pseudonymousCurrentOwnerID: pseudonymousCurrentOwnerID
            )
            recordEventWithLifecycleBreadcrumb(observation)
        }
    }

    private func recordBreadcrumb(
        phase: SyncObservationPhase,
        outcome: SyncObservationOutcome,
        errorCode: SyncStableErrorCode
    ) {
        sink.record(SanitizedSyncObservation(
            kind: .breadcrumb,
            level: .info,
            phase: phase,
            entityKind: nil,
            operation: nil,
            outcome: outcome,
            failureCategory: nil,
            errorCode: errorCode,
            counts: SyncObservationCounts(),
            fingerprint: [],
            pseudonymousCurrentOwnerID: pseudonymousCurrentOwnerID
        ))
    }

    private func recordEventWithLifecycleBreadcrumb(_ observation: SanitizedSyncObservation) {
        sink.record(Self.makeLifecycleBreadcrumb(from: observation))
        sink.record(observation)
    }

    private static func makeFailureObservation(
        _ failure: DurableSyncFailure,
        pseudonymousCurrentOwnerID: PseudonymousCurrentOwnerID?
    ) -> SanitizedSyncObservation {
        SanitizedSyncObservation(
            kind: .durableFailure,
            level: .error,
            phase: failure.phase,
            entityKind: failure.entityKind,
            operation: failure.operation,
            outcome: .failure,
            failureCategory: failure.category,
            errorCode: failure.errorCode,
            counts: failure.counts,
            fingerprint: fingerprint(
                prefix: "baros-sync-v1",
                phase: failure.phase,
                entityKind: failure.entityKind,
                operation: failure.operation,
                category: failure.category,
                errorCode: failure.errorCode,
                outcome: .failure
            ),
            pseudonymousCurrentOwnerID: pseudonymousCurrentOwnerID
        )
    }

    private static func makeRecoveryObservation(
        from failure: DurableSyncFailure,
        counts: SyncObservationCounts,
        pseudonymousCurrentOwnerID: PseudonymousCurrentOwnerID?
    ) -> SanitizedSyncObservation {
        SanitizedSyncObservation(
            kind: .recovery,
            level: .info,
            phase: .recovery,
            entityKind: failure.entityKind,
            operation: failure.operation,
            outcome: .recovered,
            failureCategory: failure.category,
            errorCode: failure.errorCode,
            counts: counts,
            fingerprint: fingerprint(
                prefix: "baros-sync-recovery-v1",
                phase: .recovery,
                entityKind: failure.entityKind,
                operation: failure.operation,
                category: failure.category,
                errorCode: failure.errorCode,
                outcome: .recovered
            ),
            pseudonymousCurrentOwnerID: pseudonymousCurrentOwnerID
        )
    }

    private static func makeLifecycleBreadcrumb(
        from observation: SanitizedSyncObservation
    ) -> SanitizedSyncObservation {
        SanitizedSyncObservation(
            kind: .breadcrumb,
            level: observation.kind == .durableFailure ? .warning : .info,
            phase: observation.phase,
            entityKind: observation.entityKind,
            operation: observation.operation,
            outcome: observation.outcome,
            failureCategory: observation.failureCategory,
            errorCode: observation.errorCode,
            counts: observation.counts,
            fingerprint: [],
            pseudonymousCurrentOwnerID: observation.pseudonymousCurrentOwnerID
        )
    }

    private static func fingerprint(
        prefix: String,
        phase: SyncObservationPhase,
        entityKind: SyncEntityKind?,
        operation: SyncOperation?,
        category: SyncFailureCategory,
        errorCode: SyncStableErrorCode,
        outcome: SyncObservationOutcome
    ) -> [String] {
        [
            prefix,
            phase.rawValue,
            entityKind?.rawValue ?? "none",
            operation?.rawValue ?? "none",
            category.rawValue,
            errorCode.rawValue,
            outcome.rawValue,
        ]
    }
}

@MainActor
final class DisabledSyncObservability: SyncObserving {
    static let shared = DisabledSyncObservability()

    private init() {}

    func setCurrentOwner(_: String?) {}
    func record(_: SyncLifecycleFact) {}
}

enum TransientSyncConditionClassifier {
    static func errorCode(for error: Error) -> SyncStableErrorCode? {
        guard let code = urlErrorCode(from: error) else { return nil }
        switch code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .requestTimedOut
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return .networkUnavailable
        default:
            return nil
        }
    }

    private static func urlErrorCode(from error: Error) -> URLError.Code? {
        if let urlError = error as? URLError {
            return urlError.code
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError.Code(rawValue: nsError.code)
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return urlErrorCode(from: underlyingError)
        }
        return nil
    }
}

struct SentryRuntimeConfiguration: Equatable {
    let isEnabled: Bool
    let dsn: String
    let environment: String
    let releaseName: String?
    let dist: String?

    init(info: [String: Any]) {
        let dsn = (info["SentryDSN"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let environmentValue = (info["BarosEnvironment"] as? String) ?? ""
        let explicitFlag: Bool = switch info["SentryEnabled"] {
        case let value as Bool:
            value
        case let value as String:
            ["1", "true", "yes"].contains(value.lowercased())
        default:
            false
        }
        let isProduction = environmentValue.caseInsensitiveCompare("Production") == .orderedSame
        let bundleIdentifier = info["CFBundleIdentifier"] as? String
        let marketingVersion = info["CFBundleShortVersionString"] as? String
        let buildNumber = info["CFBundleVersion"] as? String

        self.isEnabled = explicitFlag && isProduction && !dsn.isEmpty
        self.dsn = dsn
        self.environment = "production"
        self.dist = buildNumber
        if let bundleIdentifier, let marketingVersion, let buildNumber,
           !bundleIdentifier.isEmpty, !marketingVersion.isEmpty, !buildNumber.isEmpty {
            self.releaseName = "\(bundleIdentifier)@\(marketingVersion)+\(buildNumber)"
        } else {
            self.releaseName = nil
        }
    }
}
