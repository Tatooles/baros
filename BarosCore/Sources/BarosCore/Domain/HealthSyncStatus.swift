import Foundation

enum HealthSyncStatus: String, CaseIterable, Codable, Identifiable {
    case notSynced
    case synced
    case failed

    var id: String { rawValue }
}
