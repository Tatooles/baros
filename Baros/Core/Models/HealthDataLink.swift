import Foundation
import SwiftData

@Model
final class HealthDataLink: Identifiable {
    @Attribute(.unique) var id: UUID
    var providerRaw: String
    var localEntityKindRaw: String
    var localEntityID: UUID
    var externalIdentifier: String
    var externalType: String
    var syncStatusRaw: String
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        providerRaw: String,
        localEntityKindRaw: String,
        localEntityID: UUID,
        externalIdentifier: String,
        externalType: String,
        syncStatus: HealthSyncStatus,
        lastSyncedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerRaw = providerRaw
        self.localEntityKindRaw = localEntityKindRaw
        self.localEntityID = localEntityID
        self.externalIdentifier = externalIdentifier
        self.externalType = externalType
        self.syncStatusRaw = syncStatus.rawValue
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var syncStatus: HealthSyncStatus {
        get { HealthSyncStatus(rawValue: syncStatusRaw) ?? .notSynced }
        set {
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
