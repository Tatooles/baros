import Foundation

/// Value-only baseline shared by confirmation and persistence. In particular,
/// set edits do not always touch parent timestamps, so compare the leaves too.
struct WorkoutExerciseListSnapshot: Equatable {
    struct SetState: Equatable {
        let id: UUID
        let orderIndex: Int
        let weight: Double?
        let reps: Int?
        let rpe: Double?
        let isCompleted: Bool
        let completedAt: Date?
        let kind: String
        let notes: String
        let updatedAt: Date

        init(_ set: LoggedSet) {
            id = set.id
            orderIndex = set.orderIndex
            weight = set.weight
            reps = set.reps
            rpe = set.rpe
            isCompleted = set.isCompleted
            completedAt = set.completedAt
            kind = set.kindRaw
            notes = set.notes
            updatedAt = set.updatedAt
        }

        var hasLoggedValues: Bool { isCompleted || weight != nil || reps != nil }
    }

    struct ExerciseState: Identifiable, Equatable {
        let id: UUID
        let name: String
        let metadata: String?
        let orderIndex: Int
        let notes: String
        let referenceNotes: String?
        let updatedAt: Date
        let sets: [SetState]

        init(_ exercise: LoggedExercise) {
            id = exercise.id
            name = exercise.exerciseSnapshotName
            metadata = exercise.metadataDisplayText
            orderIndex = exercise.orderIndex
            notes = exercise.notes
            referenceNotes = exercise.referenceNotes
            updatedAt = exercise.updatedAt
            sets = exercise.sortedSets.map(SetState.init)
        }

        var loggedSetCount: Int { sets.filter(\.hasLoggedValues).count }
        var progressText: String { "\(sets.filter(\.isCompleted).count)/\(sets.count) sets" }
        var accessibilityValue: String {
            [metadata, progressText].compactMap { $0 }.joined(separator: ", ")
        }
    }

    let sessionID: UUID
    let owner: String?
    let status: String
    let deletedAt: Date?
    let exercises: [ExerciseState]

    init(session: WorkoutSession) {
        sessionID = session.id
        owner = session.syncOwnerTokenIdentifier
        status = session.statusRaw
        deletedAt = session.deletedAt
        exercises = session.sortedLoggedExercises.map(ExerciseState.init)
    }
}

struct WorkoutExerciseListDraft {
    let baseline: WorkoutExerciseListSnapshot
    var orderedIDs: [UUID]

    init(session: WorkoutSession) {
        baseline = WorkoutExerciseListSnapshot(session: session)
        orderedIDs = baseline.exercises.map(\.id)
    }

    var exercises: [WorkoutExerciseListSnapshot.ExerciseState] {
        let byID = Dictionary(uniqueKeysWithValues: baseline.exercises.map { ($0.id, $0) })
        return orderedIDs.compactMap { byID[$0] }
    }

    var removedExercises: [WorkoutExerciseListSnapshot.ExerciseState] {
        let remaining = Set(orderedIDs)
        return baseline.exercises.filter { !remaining.contains($0.id) }
    }

    var needsRemovalConfirmation: Bool { removedExercises.contains { $0.loggedSetCount > 0 } }

    var removalMessage: String {
        let details = removedExercises.map { exercise in
            let count = exercise.loggedSetCount
            return "\(exercise.name) — \(count) logged \(count == 1 ? "set" : "sets")"
        }.joined(separator: "\n")
        return "These exercises and their sets will be removed from this workout:\n\n\(details)"
    }
}
