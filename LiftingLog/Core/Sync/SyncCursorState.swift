import Foundation
import SwiftData

@Model
final class SyncCursorState: Identifiable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique)
    var ownerTokenIdentifier: String
    var userSettingsCursor: Double
    var exercisesCursor: Double
    var hasBootstrappedSettingsExercises: Bool = false

    init(
        id: UUID = UUID(),
        ownerTokenIdentifier: String,
        userSettingsCursor: Double = 0,
        exercisesCursor: Double = 0,
        hasBootstrappedSettingsExercises: Bool = false
    ) {
        self.id = id
        self.ownerTokenIdentifier = ownerTokenIdentifier
        self.userSettingsCursor = userSettingsCursor
        self.exercisesCursor = exercisesCursor
        self.hasBootstrappedSettingsExercises = hasBootstrappedSettingsExercises
    }

    static func state(for ownerTokenIdentifier: String, context: ModelContext) throws -> SyncCursorState {
        let descriptor = FetchDescriptor<SyncCursorState>(
            predicate: #Predicate { state in
                state.ownerTokenIdentifier == ownerTokenIdentifier
            }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let state = SyncCursorState(ownerTokenIdentifier: ownerTokenIdentifier)
        context.insert(state)
        return state
    }
}
