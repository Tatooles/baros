import Foundation

/// A line-for-line port of the server's conflict rule, `convex/sync/merge.ts`,
/// for the simulated server. `SimMergeVectorTests` checks it against vectors
/// generated from the TypeScript, so the two cannot drift apart.
enum SimMergeRule {
    static let versionStepSeconds = 0.001
    static let sameTimeToleranceSeconds = 1e-6

    struct StoredVersion: Equatable {
        /// Zero marks a placeholder tombstone.
        var createdAt: Double?
        var updatedAt: Double
        var deletedAt: Double?
        /// Milliseconds.
        var serverUpdatedAt: Double
        var syncOrder: Double?
    }

    enum Base: Equatable {
        /// An installed build, which sends no base.
        case absent
        /// A current build's record never synced.
        case null
        case value(Double)
    }

    struct IncomingVersion: Equatable {
        var updatedAt: Double
        var deletedAt: Double?
        var base: Base
    }

    enum UpsertDecision: Equatable {
        case insert(updatedAt: Double, deletedAt: Double?, syncOrder: Double, accepted: Bool)
        case patch(takeIncomingFields: Bool, updatedAt: Double, deletedAt: Double?, syncOrder: Double?, accepted: Bool)
        case ignore
    }

    enum TombstoneDecision: Equatable {
        case insertPlaceholder(updatedAt: Double, deletedAt: Double)
        case alreadyDeleted
        case tombstone(updatedAt: Double, deletedAt: Double)
    }

    static func effectiveStoredTime(_ stored: StoredVersion, nowSeconds: Double = .infinity) -> Double {
        min(stored.updatedAt, stored.serverUpdatedAt / 1000, nowSeconds)
    }

    static func isPlaceholder(_ stored: StoredVersion) -> Bool {
        stored.createdAt == 0
    }

    static func storedSyncOrder(_ stored: StoredVersion, nowSeconds: Double) -> Double {
        stored.syncOrder ?? effectiveStoredTime(stored, nowSeconds: nowSeconds)
    }

    static func nextSyncOrder(_ stored: StoredVersion?, _ incoming: IncomingVersion, nowSeconds: Double) -> Double {
        let own = incoming.base != .absent
            ? incoming.updatedAt
            : effectiveIncomingTime(incoming, nowSeconds: nowSeconds)
        guard let stored else { return own }
        return max(own, storedSyncOrder(stored, nowSeconds: nowSeconds) + versionStepSeconds)
    }

    static func effectiveIncomingTime(_ incoming: IncomingVersion, nowSeconds: Double) -> Double {
        min(incoming.updatedAt, nowSeconds)
    }

    static func clampToServerTime(_ timestamp: Double, nowSeconds: Double) -> Double {
        min(timestamp, nowSeconds)
    }

    static func sameTime(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= sameTimeToleranceSeconds
    }

    static func incomingFieldsWin(_ stored: StoredVersion, _ incoming: IncomingVersion, nowSeconds: Double) -> Bool {
        switch incoming.base {
        case let .value(base):
            if base >= stored.updatedAt - sameTimeToleranceSeconds {
                return true
            }
            if incoming.updatedAt <= base + sameTimeToleranceSeconds {
                return false
            }
            return incoming.updatedAt > storedSyncOrder(stored, nowSeconds: nowSeconds)
        case .null:
            return incoming.updatedAt > storedSyncOrder(stored, nowSeconds: nowSeconds)
        case .absent:
            if incoming.updatedAt > nowSeconds && incoming.updatedAt <= stored.updatedAt {
                return false
            }
            let incomingTime = effectiveIncomingTime(incoming, nowSeconds: nowSeconds)
            let storedTime = effectiveStoredTime(stored, nowSeconds: nowSeconds)
            if incomingTime != storedTime {
                return incomingTime > storedTime
            }
            return incoming.updatedAt > stored.updatedAt
        }
    }

    static func decideUpsert(
        _ stored: StoredVersion?,
        _ incoming: IncomingVersion,
        nowSeconds: Double,
        sameContent: Bool,
        parentDeletedAt: Double?
    ) -> UpsertDecision {
        let uploaderHoldsLive = incoming.deletedAt == nil
        let requestedDeletedAt = incoming.deletedAt ?? parentDeletedAt
        func deletionVersion(_ base: Double) -> Double {
            uploaderHoldsLive ? base + versionStepSeconds : base
        }
        let syncOrder = nextSyncOrder(stored, incoming, nowSeconds: nowSeconds)

        guard let stored else {
            guard let requestedDeletedAt else {
                return .insert(updatedAt: incoming.updatedAt, deletedAt: nil, syncOrder: syncOrder, accepted: true)
            }
            return .insert(
                updatedAt: deletionVersion(incoming.updatedAt),
                deletedAt: clampToServerTime(requestedDeletedAt, nowSeconds: nowSeconds),
                syncOrder: syncOrder,
                accepted: !uploaderHoldsLive
            )
        }

        if stored.deletedAt == nil, requestedDeletedAt == nil, sameContent, sameTime(incoming.updatedAt, stored.updatedAt) {
            return .ignore
        }
        let fieldsWin = incomingFieldsWin(stored, incoming, nowSeconds: nowSeconds)

        if let storedDeletedAt = stored.deletedAt {
            if fieldsWin || isPlaceholder(stored) {
                return .patch(
                    takeIncomingFields: true,
                    updatedAt: max(deletionVersion(incoming.updatedAt), stored.updatedAt + versionStepSeconds),
                    deletedAt: storedDeletedAt,
                    syncOrder: syncOrder,
                    accepted: !uploaderHoldsLive
                )
            }
            if uploaderHoldsLive && incoming.updatedAt >= stored.updatedAt {
                return .patch(
                    takeIncomingFields: false,
                    updatedAt: incoming.updatedAt + versionStepSeconds,
                    deletedAt: storedDeletedAt,
                    syncOrder: nil,
                    accepted: false
                )
            }
            return .ignore
        }

        if let requestedDeletedAt {
            let inherited = uploaderHoldsLive
            return .patch(
                takeIncomingFields: fieldsWin,
                updatedAt: max(stored.updatedAt + versionStepSeconds, deletionVersion(incoming.updatedAt)),
                deletedAt: clampToServerTime(requestedDeletedAt, nowSeconds: nowSeconds),
                syncOrder: fieldsWin ? syncOrder : nil,
                accepted: !inherited && fieldsWin
            )
        }

        if fieldsWin {
            return .patch(
                takeIncomingFields: true,
                updatedAt: max(incoming.updatedAt, stored.updatedAt + versionStepSeconds),
                deletedAt: nil,
                syncOrder: syncOrder,
                accepted: true
            )
        }
        if incoming.updatedAt < stored.updatedAt {
            return .ignore
        }
        return .patch(
            takeIncomingFields: false,
            updatedAt: sameContent ? incoming.updatedAt : incoming.updatedAt + versionStepSeconds,
            deletedAt: nil,
            syncOrder: nil,
            accepted: false
        )
    }

    static func decideTombstone(_ stored: StoredVersion?, deletedAt: Double, nowSeconds: Double) -> TombstoneDecision {
        guard let stored else {
            return .insertPlaceholder(
                updatedAt: max(deletedAt, nowSeconds),
                deletedAt: clampToServerTime(deletedAt, nowSeconds: nowSeconds)
            )
        }
        if stored.deletedAt != nil {
            return .alreadyDeleted
        }
        let clamped = clampToServerTime(deletedAt, nowSeconds: nowSeconds)
        return .tombstone(updatedAt: max(clamped, stored.updatedAt + versionStepSeconds), deletedAt: clamped)
    }

    static func cascadedChildVersion(childUpdatedAt: Double, parentUpdatedAt: Double, parentDeletedAt: Double) -> (updatedAt: Double, deletedAt: Double) {
        (max(childUpdatedAt + versionStepSeconds, parentUpdatedAt), parentDeletedAt)
    }
}
