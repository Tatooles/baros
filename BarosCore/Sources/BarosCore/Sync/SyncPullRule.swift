import Foundation

/// What this device still means to send for a record.
enum SyncLocalIntent: Equatable {
    /// No active outbox entry: the local copy is the last version this device
    /// synced.
    case none
    /// An outbox entry is waiting, in flight, or backing off after a failure.
    case pending
    /// The outbox entry was dead-lettered and waits for the person to retry.
    case blocked
}

enum SyncPullDecision: Equatable {
    /// Copy the server's version verbatim.
    case applyIncoming
    /// Keep the local copy. When `rewindCursor` is set, the run pulls the
    /// record again after its push, so a push that ends without a server
    /// verdict cannot leave the server's version unpulled.
    case keepLocal(rewindCursor: Bool)
    /// Keep the local delete and queue it again. The server holds a live copy
    /// of something this device deleted, which only an older server could
    /// have produced (#97).
    case reassertLocalDelete
}

/// The pull rule. The server decides every conflict (`convex/sync/merge.ts`),
/// so a device copies its version unless it still has something to send.
///
/// - A server tombstone always applies: deletes win.
/// - A local delete against a live server copy is sent again. User settings
///   are the exception; their local delete is kept as before.
/// - When both copies are live, local intent keeps the local copy until its
///   upload gets a verdict. Otherwise the server's version applies, whatever
///   the timestamps say.
/// - During the first-run bootstrap, before bootstrap entries exist, a local
///   copy newer than the server's is kept so the bootstrap upload lets the
///   server decide, as before this rule.
enum SyncPullRule {
    static func decide(
        localUpdatedAt: Date,
        localIsDeleted: Bool,
        incomingUpdatedAt: Date,
        incomingIsDeleted: Bool,
        localIntent: SyncLocalIntent,
        isBootstrapping: Bool,
        reassertsLocalDeletes: Bool
    ) -> SyncPullDecision {
        if incomingIsDeleted {
            return .applyIncoming
        }
        if localIsDeleted {
            if localIntent == .none && reassertsLocalDeletes {
                return .reassertLocalDelete
            }
            return .keepLocal(rewindCursor: false)
        }
        switch localIntent {
        case .pending:
            return .keepLocal(rewindCursor: true)
        case .blocked:
            // A dead-lettered entry gets no verdict until the person retries
            // it. Rewinding for it would re-pull every later change on every
            // run. Its retry ends with a verdict: an "ignored_stale" result
            // rewinds the cursor then.
            return .keepLocal(rewindCursor: false)
        case .none:
            if isBootstrapping && incomingUpdatedAt <= localUpdatedAt {
                return .keepLocal(rewindCursor: true)
            }
            return .applyIncoming
        }
    }
}
