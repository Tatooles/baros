import Foundation
import SwiftData

@Model
public final class SyncCursorState: Identifiable {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique)
    var ownerTokenIdentifier: String
    var userSettingsCursor: Double
    var exercisesCursor: Double
    var workoutSessionsCursor: Double = 0
    var loggedExercisesCursor: Double = 0
    var loggedSetsCursor: Double = 0
    var workoutTemplatesCursor: Double = 0
    var hasBootstrappedSettingsExercises: Bool = false
    var hasBootstrappedWorkoutGraph: Bool = false
    /// Set once this owner has run the one-time step for updating to the
    /// server-decides sync rule: local deletes sent again and sync bases
    /// adopted (`SyncCoordinator.runConvergenceUpgradeIfNeeded`).
    var hasRunConvergenceUpgrade: Bool = false

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

    /// Moves a cursor back so the change at `serverUpdatedAt` is pulled again.
    func rewind(_ kind: SyncEntityKind, toBefore serverUpdatedAt: Double) {
        let target = max(0, serverUpdatedAt - 1)
        switch kind {
        case .userSettings:
            userSettingsCursor = min(userSettingsCursor, target)
        case .exercise:
            exercisesCursor = min(exercisesCursor, target)
        case .workoutSession:
            workoutSessionsCursor = min(workoutSessionsCursor, target)
        case .loggedExercise:
            loggedExercisesCursor = min(loggedExercisesCursor, target)
        case .loggedSet:
            loggedSetsCursor = min(loggedSetsCursor, target)
        case .workoutTemplate:
            workoutTemplatesCursor = min(workoutTemplatesCursor, target)
        case .healthDataLink, .seedMetadata:
            break
        }
    }
}
