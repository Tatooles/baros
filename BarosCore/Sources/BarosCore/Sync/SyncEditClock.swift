import Foundation

/// The one rule for stamping a local edit of a synced record.
///
/// An edit is stamped above both the local version it replaces and the
/// server version it started from (`syncBaseUpdatedAt`), whatever the device
/// clock says. The server reads an upload stamped at or below its base as a
/// re-send with no edit (`convex/sync/merge.ts`), so an edit stamped any
/// lower would be dropped. Every edit site goes through `stampEdit(now:)`.
enum SyncEditClock {
    /// The smallest step that keeps an edit strictly above what it replaced.
    /// Matches the server's `versionStepSeconds`.
    static let step: TimeInterval = 0.001

    static func stamp(previous: Date, syncBase: Double?, now: Date) -> Date {
        var stamp = max(now, previous.addingTimeInterval(step))
        if let syncBase {
            stamp = max(stamp, Date(timeIntervalSince1970: syncBase + step))
        }
        return stamp
    }
}

/// A synced model whose local edits are stamped by `SyncEditClock`.
protocol SyncEditStamped: AnyObject {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var syncBaseUpdatedAt: Double? { get set }
}

extension SyncEditStamped {
    /// Stamps a local edit and returns the stamp.
    @discardableResult
    func stampEdit(now: Date) -> Date {
        let stamp = SyncEditClock.stamp(previous: updatedAt, syncBase: syncBaseUpdatedAt, now: now)
        updatedAt = stamp
        return stamp
    }
}
