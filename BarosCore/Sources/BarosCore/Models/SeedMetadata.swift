import Foundation
import SwiftData

@Model
final class SeedMetadata: Identifiable {
    @Attribute(.unique) var id: UUID
    var key: String
    var version: Int
    var appliedAt: Date

    init(id: UUID = UUID(), key: String, version: Int, appliedAt: Date = .now) {
        self.id = id
        self.key = key
        self.version = version
        self.appliedAt = appliedAt
    }
}
