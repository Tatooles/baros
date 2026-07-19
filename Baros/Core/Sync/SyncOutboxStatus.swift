import Foundation

enum SyncOutboxStatus: String, CaseIterable, Codable, Equatable, Hashable {
    case pending
    case inFlight
    case failed
    case completed
}
