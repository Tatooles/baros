import Foundation

public enum SyncOutboxStatus: String, CaseIterable, Codable, Equatable, Hashable {
    case pending
    case inFlight
    case failed
    /// Dead-lettered: the server rejected the entry repeatedly over at least
    /// a day. It stays queued and visible, and is not sent again until the
    /// person retries it or edits the record again.
    case blocked
    case completed
}
