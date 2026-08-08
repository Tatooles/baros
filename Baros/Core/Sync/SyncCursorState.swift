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
    /// Whether the ownerless-adoption decision has ever been made for this owner.
    ///
    /// Distinguishes "evaluated, and nothing was declined" from a cursor row written by a version
    /// that predates `declinedOwnerlessWorkoutIDs`, where an empty list must not be read as
    /// consent to adopt everything.
    var hasEvaluatedOwnerlessWorkoutAdoption: Bool = false
    /// Logged Workouts this owner deliberately left as Unclaimed Local Data, plus workouts whose
    /// first ownerless intent was created after an older cursor row but before that legacy row's
    /// adoption decision could be evaluated.
    ///
    /// `hasBootstrappedWorkoutGraph` is a one-time flag, so on its own it cannot tell "already
    /// decided not to adopt the workouts that existed then" apart from "never look at Unclaimed
    /// Local Data again". Naming the declined sessions keeps them local while letting every later
    /// ownerless session be adopted. Identifiers are recorded rather than a cutoff timestamp
    /// because no field records when a session became a Logged Workout: `createdAt` is stamped
    /// when the Active Workout starts, and `endedAt` is rewritten by duration edits.
    ///
    /// Bounded in practice: entries are added only while recording a decline or protecting the
    /// one-time upgrade window before that decline is evaluated.
    var declinedOwnerlessWorkoutIDs: [UUID] = []

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
        hasEvaluatedOwnerlessWorkoutAdoption: Bool = false,
        declinedOwnerlessWorkoutIDs: [UUID] = []
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
        self.hasEvaluatedOwnerlessWorkoutAdoption = hasEvaluatedOwnerlessWorkoutAdoption
        self.declinedOwnerlessWorkoutIDs = declinedOwnerlessWorkoutIDs
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
