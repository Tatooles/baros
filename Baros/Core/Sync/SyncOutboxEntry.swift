import Foundation
import SwiftData

@Model
final class SyncOutboxEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var entityKindRaw: String
    var entityID: UUID
    var operationRaw: String
    var statusRaw: String
    var ownerTokenIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var lastAttemptAt: Date?
    var attemptCount: Int
    var lastErrorMessage: String?

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

    var entityKind: SyncEntityKind? {
        get { SyncEntityKind(rawValue: entityKindRaw) }
        set { entityKindRaw = newValue?.rawValue ?? "" }
    }

    var operation: SyncOperation? {
        get { SyncOperation(rawValue: operationRaw) }
        set { operationRaw = newValue?.rawValue ?? "" }
    }

    var status: SyncOutboxStatus? {
        get { SyncOutboxStatus(rawValue: statusRaw) }
        set { statusRaw = newValue?.rawValue ?? "" }
    }

    var isActive: Bool {
        guard let status else { return false }
        return status != .completed
    }

    var hasBeenAttempted: Bool {
        attemptCount > 0 || lastAttemptAt != nil || status == .inFlight || status == .failed
    }

    func refreshPending(now: Date) {
        status = .pending
        updatedAt = now
        lastErrorMessage = nil
    }
}
