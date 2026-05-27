import Foundation

enum SyncMergeDecision: Equatable {
    case applyIncoming
    case keepLocal
}

enum SyncConflictResolver {
    static func decision(
        localUpdatedAt: Date,
        localDeletedAt: Date?,
        incomingUpdatedAt: Date,
        incomingDeletedAt: Date?,
        allowsIncomingRestore: Bool = false
    ) -> SyncMergeDecision {
        if incomingUpdatedAt <= localUpdatedAt {
            return .keepLocal
        }

        if localDeletedAt != nil, incomingDeletedAt == nil, !allowsIncomingRestore {
            return .keepLocal
        }

        return .applyIncoming
    }
}
