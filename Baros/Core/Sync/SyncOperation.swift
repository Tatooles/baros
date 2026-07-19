import Foundation

enum SyncOperation: String, CaseIterable, Codable, Equatable, Hashable {
    case create
    case update
    case delete
}
