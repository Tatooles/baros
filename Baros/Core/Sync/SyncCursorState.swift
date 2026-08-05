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
    /// Instant at which workout-graph bootstrap deliberately left Unclaimed Local Data unclaimed
    /// for this owner, because the account already carried remote workout history.
    ///
    /// `hasBootstrappedWorkoutGraph` is a one-time flag, so on its own it cannot tell "already
    /// decided not to adopt the workouts that existed then" apart from "never look at Unclaimed
    /// Local Data again". Recording *when* the decision was made keeps the pre-existing sessions
    /// local while still letting later ownerless sessions be adopted.
    var ownerlessWorkoutAdoptionDeclinedAt: Date?

    init(
        id: UUID = UUID(),
        ownerTokenIdentifier: String,
        userSettingsCursor: Double = 0,
        exercisesCursor: Double = 0,
        workoutSessionsCursor: Double = 0,
        loggedExercisesCursor: Double = 0,
        loggedSetsCursor: Double = 0,
        hasBootstrappedSettingsExercises: Bool = false,
        hasBootstrappedWorkoutGraph: Bool = false,
        ownerlessWorkoutAdoptionDeclinedAt: Date? = nil
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
        self.ownerlessWorkoutAdoptionDeclinedAt = ownerlessWorkoutAdoptionDeclinedAt
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
