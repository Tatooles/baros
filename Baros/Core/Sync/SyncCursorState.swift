import Foundation
import SwiftData

@Model
final class SyncCursorState: Identifiable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique)
    var ownerTokenIdentifier: String
    var userSettingsCursor: Double
    var exercisesCursor: Double
    var workoutSessionsCursor: Double = 0
    var loggedExercisesCursor: Double = 0
    var loggedSetsCursor: Double = 0
    var hasBootstrappedSettingsExercises: Bool = false
    var hasBootstrappedWorkoutGraph: Bool = false

    init(
        id: UUID = UUID(),
        ownerTokenIdentifier: String,
        userSettingsCursor: Double = 0,
        exercisesCursor: Double = 0,
        workoutSessionsCursor: Double = 0,
        loggedExercisesCursor: Double = 0,
        loggedSetsCursor: Double = 0,
        hasBootstrappedSettingsExercises: Bool = false,
        hasBootstrappedWorkoutGraph: Bool = false
    ) {
        self.id = id
        self.ownerTokenIdentifier = ownerTokenIdentifier
        self.userSettingsCursor = userSettingsCursor
        self.exercisesCursor = exercisesCursor
        self.workoutSessionsCursor = workoutSessionsCursor
        self.loggedExercisesCursor = loggedExercisesCursor
        self.loggedSetsCursor = loggedSetsCursor
        self.hasBootstrappedSettingsExercises = hasBootstrappedSettingsExercises
        self.hasBootstrappedWorkoutGraph = hasBootstrappedWorkoutGraph
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
