import Foundation
import SwiftData

@Model
final class WorkoutTemplate: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var healthLinkID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isArchived: Bool = false,
        healthLinkID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.healthLinkID = healthLinkID
    }
}
