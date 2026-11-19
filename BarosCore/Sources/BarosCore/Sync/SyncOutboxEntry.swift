import Foundation
import SwiftData

@Model
public final class SyncOutboxEntry: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var entityKindRaw: String
    var entityID: UUID
    public var operationRaw: String
    public var statusRaw: String
    public var ownerTokenIdentifier: String?
    var createdAt: Date
    public var updatedAt: Date
    var lastAttemptAt: Date?
    public var attemptCount: Int
    public var lastErrorMessage: String?
    /// Server rejections since the entry was last retried by hand. Separate
    /// from `attemptCount`, which older builds grew without bound on entries
    /// that never sent.
    public var rejectionCount: Int = 0
    var firstRejectedAt: Date?
    /// Earliest time the entry is sent again after a rejection.
    var nextAttemptAt: Date?
    /// The server's error code for the last rejection, or nil when uncoded.
    public var lastRejectionCode: String?

    init(
        id: UUID = UUID(),
        entityKind: SyncEntityKind,
        entityID: UUID,
        operation: SyncOperation,
        status: SyncOutboxStatus = .pending,
        ownerTokenIdentifier: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        lastAttemptAt: Date? = nil,
        attemptCount: Int = 0,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.entityKindRaw = entityKind.rawValue
        self.entityID = entityID
        self.operationRaw = operation.rawValue
        self.statusRaw = status.rawValue
        self.ownerTokenIdentifier = ownerTokenIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
        self.lastErrorMessage = lastErrorMessage
    }

    convenience init(
        id: UUID = UUID(),
        entityKind: SyncEntityKind,
        entityID: UUID,
        operation: SyncOperation,
        ownerTokenIdentifier: String? = nil,
        now: Date = .now
    ) {
        self.init(
            id: id,
            entityKind: entityKind,
            entityID: entityID,
            operation: operation,
            status: .pending,
            ownerTokenIdentifier: ownerTokenIdentifier,
            createdAt: now,
            updatedAt: now
        )
    }

    public var entityKind: SyncEntityKind? {
        get { SyncEntityKind(rawValue: entityKindRaw) }
        set { entityKindRaw = newValue?.rawValue ?? "" }
    }

    var operation: SyncOperation? {
        get { SyncOperation(rawValue: operationRaw) }
        set { operationRaw = newValue?.rawValue ?? "" }
    }

    public var status: SyncOutboxStatus? {
        get { SyncOutboxStatus(rawValue: statusRaw) }
        set { statusRaw = newValue?.rawValue ?? "" }
    }

    public var isActive: Bool {
        guard let status else { return false }
        return status != .completed
    }

    var hasBeenAttempted: Bool {
        attemptCount > 0 || lastAttemptAt != nil || status == .inFlight || status == .failed || status == .blocked
    }

    /// A new local edit sends the entry now, even one that was blocked.
    func refreshPending(now: Date) {
        status = .pending
        updatedAt = now
        lastErrorMessage = nil
        nextAttemptAt = nil
    }

    /// Clears the rejection history so the entry is sent again as new.
    func resetRejections() {
        rejectionCount = 0
        firstRejectedAt = nil
        nextAttemptAt = nil
        lastRejectionCode = nil
    }
}

/// Identifies the record an outbox entry is for.
struct SyncOutboxKey: Hashable {
    let kind: SyncEntityKind
    let id: UUID
}

extension SyncOutboxEntry {
    var outboxKey: SyncOutboxKey? {
        entityKind.map { SyncOutboxKey(kind: $0, id: entityID) }
    }
}
