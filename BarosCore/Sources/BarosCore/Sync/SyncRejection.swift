import Foundation

/// A sync mutation the server refused. The Convex adapter throws this for
/// every server-side error, with the `ConvexError` data code when there is one
/// (`convex/sync/errors.ts`).
public struct SyncServerRejection: Error, LocalizedError, Equatable, Sendable {
    /// The `ConvexError` code, or nil for an uncoded server error. Convex
    /// rejects arguments that fail validation before any handler code runs,
    /// so those arrive uncoded.
    let code: String?
    let message: String

    public init(code: String?, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }

    /// Reads a `ConvexError` payload such as `{"code":"missingParent","message":"..."}`.
    public static func fromConvexErrorData(_ data: String) -> SyncServerRejection {
        struct Payload: Decodable {
            let code: String?
            let message: String?
        }
        let payload = try? JSONDecoder().decode(Payload.self, from: Data(data.utf8))
        return SyncServerRejection(code: payload?.code, message: payload?.message ?? data)
    }
}

/// How one failed push changes what the coordinator does next.
enum SyncPushFailureKind: Equatable {
    /// The network, not the server. Stop the run and retry the entry as it was.
    case transient(SyncStableErrorCode)
    /// Nothing will succeed for this account right now, and the record is
    /// fine. Do not count it against the entry.
    case accountWide(code: String)
    /// The server will not accept this record as sent: `missingParent`,
    /// `missingExerciseReference` or `invalidPayload`.
    case record(code: String)
    /// An uncoded server error, or a code this build does not know. It may
    /// be permanent, so it counts toward dead-lettering, but it may also be a
    /// server outage, so a streak of them stops the run.
    case unknown
    /// A failure on this device, not the server's verdict, such as a local
    /// store error. It never counts toward dead-lettering.
    case local

    var code: String? {
        switch self {
        case let .accountWide(code), let .record(code): code
        case .transient, .unknown, .local: nil
        }
    }
}

enum SyncPushFailureClassifier {
    static let recordCodes: Set<String> = ["missingParent", "missingExerciseReference", "invalidPayload"]
    static let accountWideCodes: Set<String> = ["unauthenticated", "accountDeletionInProgress"]

    static func classify(_ error: Error) -> SyncPushFailureKind {
        if let transient = TransientSyncConditionClassifier.errorCode(for: error) {
            return .transient(transient)
        }
        guard let rejection = error as? SyncServerRejection else {
            return .local
        }
        guard let code = rejection.code else {
            return .unknown
        }
        if accountWideCodes.contains(code) {
            return .accountWide(code: code)
        }
        if recordCodes.contains(code) {
            return .record(code: code)
        }
        return .unknown
    }
}

/// When a rejected entry is sent again, and when it is dead-lettered.
enum SyncRejectionPolicy {
    /// An entry is dead-lettered only after this many rejections...
    static let rejectionsBeforeBlocking = 8
    /// ...spread over at least this long, so a bad day on the server never
    /// strands a healthy record.
    static let blockingWindow: TimeInterval = 24 * 60 * 60
    static let firstBackoff: TimeInterval = 30
    static let maxBackoff: TimeInterval = 6 * 60 * 60
    /// A run stops after this many account-wide rejections. One can be a race
    /// with a token refresh; two mean the account cannot write right now.
    static let accountWideRejectionsBeforeStopping = 2
    /// A run stops after this many uncoded rejections in a row with no
    /// success, which looks like the server, not the records.
    static let uncodedRejectionStreakBeforeStopping = 5

    static func backoff(afterRejections rejectionCount: Int) -> TimeInterval {
        let exponent = min(max(0, rejectionCount - 1), 20)
        return min(maxBackoff, firstBackoff * pow(2, Double(exponent)))
    }

    static func shouldBlock(rejectionCount: Int, firstRejectedAt: Date?, now: Date) -> Bool {
        guard let firstRejectedAt else { return false }
        return rejectionCount >= rejectionsBeforeBlocking
            && now.timeIntervalSince(firstRejectedAt) >= blockingWindow
    }

    /// Whether a backed-off entry may be sent now. A clock that moved
    /// backwards leaves a retry time further out than any backoff; that entry
    /// is sent rather than stranded.
    static func isDue(nextAttemptAt: Date?, now: Date) -> Bool {
        guard let nextAttemptAt else { return true }
        return nextAttemptAt <= now || nextAttemptAt.timeIntervalSince(now) > maxBackoff
    }
}
