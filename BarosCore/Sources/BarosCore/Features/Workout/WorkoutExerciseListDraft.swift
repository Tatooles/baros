import Foundation

public struct WorkoutExerciseListSnapshot: Equatable {
    struct SetState: Equatable {
        let id: UUID
        let orderIndex: Int
        let weight: Double?
        let reps: Int?
        let durationSeconds: Int?
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
            durationSeconds = set.durationSeconds
            rpe = set.rpe
            isCompleted = set.isCompleted
            completedAt = set.completedAt
            kind = set.kindRaw
            notes = set.notes
            updatedAt = set.updatedAt
        }

        var hasLoggedValues: Bool { isCompleted || weight != nil || reps != nil || durationSeconds != nil || rpe != nil }
    }

    public struct ExerciseState: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let metadata: String?
        let orderIndex: Int
        let notes: String
        let referenceNotes: String?
        public var supersetGroupID: UUID?
        let updatedAt: Date
        let sets: [SetState]
        public var isNew = false
        private var plannedSetCount: Int?

        init(_ exercise: LoggedExercise) {
            id = exercise.id
            name = exercise.exerciseSnapshotName
            metadata = exercise.metadataDisplayText
            orderIndex = exercise.orderIndex
            notes = exercise.notes
            referenceNotes = exercise.referenceNotes
            supersetGroupID = exercise.supersetGroupID
            updatedAt = exercise.updatedAt
            sets = exercise.sortedSets.map(SetState.init)
        }

        init(addition: WorkoutExerciseListDraft.Addition) {
            id = addition.id
            name = addition.exercise.name
            metadata = addition.exercise.metadataDisplayText
            orderIndex = 0
            notes = ""
            referenceNotes = nil
            supersetGroupID = nil
            updatedAt = .distantPast
            sets = []
            isNew = true
            plannedSetCount = addition.initialSetKinds.count
        }

        public var loggedSetCount: Int { sets.filter(\.hasLoggedValues).count }
        var progressText: String { "\(sets.filter(\.isCompleted).count)/\(plannedSetCount ?? sets.count) sets" }
        public var accessibilityValue: String {
            [metadata, isNew ? "New" : nil, progressText].compactMap { $0 }.joined(separator: ", ")
        }
    }

    let sessionID: UUID
    let owner: String?
    let status: String
    let deletedAt: Date?
    let exercises: [ExerciseState]

    public init(session: WorkoutSession) {
        sessionID = session.id
        owner = session.syncOwnerTokenIdentifier
        status = session.statusRaw
        deletedAt = session.deletedAt
        exercises = session.sortedLoggedExercises.map(ExerciseState.init)
    }
}

public struct WorkoutExerciseListDraft {
    public struct Addition {
        public let id = UUID()
        public let exercise: Exercise
        var initialSetKinds: [SetKind] = [.working]
    }
    public var additions: [Addition] = []

    public let baseline: WorkoutExerciseListSnapshot
    public var orderedIDs: [UUID]
    public private(set) var supersetGroupIDs: [UUID: UUID]

    public init(session: WorkoutSession) {
        baseline = WorkoutExerciseListSnapshot(session: session)
        orderedIDs = baseline.exercises.map(\.id)
        supersetGroupIDs = baseline.exercises.reduce(into: [:]) { $0[$1.id] = $1.supersetGroupID }
    }

    public var exercises: [WorkoutExerciseListSnapshot.ExerciseState] {
        let pending = additions.map(WorkoutExerciseListSnapshot.ExerciseState.init(addition:))
        let byID = Dictionary(uniqueKeysWithValues: (baseline.exercises + pending).map { ($0.id, $0) })
        return orderedIDs.compactMap { id in
            var exercise = byID[id]
            exercise?.supersetGroupID = supersetGroupIDs[id]
            return exercise
        }
    }

    /// Whether saving would change the workout: its exercises, their order, or its supersets.
    public var hasChanges: Bool {
        orderedIDs != baseline.exercises.map(\.id)
            || !SupersetGrouping.sameSupersets(
                orderedIDs.map { supersetGroupIDs[$0] }, baseline.exercises.map(\.supersetGroupID)
            )
    }

    /// Sets with entered values that saving would delete, and how many removed
    /// exercises they come from.
    public var pendingSetLoss: (sets: Int, exercises: Int) {
        let lossy = removedExercises.filter { $0.loggedSetCount > 0 }
        return (lossy.reduce(0) { $0 + $1.loggedSetCount }, lossy.count)
    }

    /// The removed exercises whose entered sets saving would delete.
    public var lossyRemovedExerciseNames: [String] {
        removedExercises.filter { $0.loggedSetCount > 0 }.map(\.name)
    }

    var removedExercises: [WorkoutExerciseListSnapshot.ExerciseState] {
        let remaining = Set(orderedIDs)
        return baseline.exercises.filter { !remaining.contains($0.id) }
    }

    public mutating func append(
        _ exercises: [Exercise],
        asSuperset: Bool = false,
        initialSetKinds: (Exercise) -> [SetKind] = { _ in [.working] }
    ) {
        let pending = exercises.map { Addition(exercise: $0, initialSetKinds: initialSetKinds($0)) }
        additions.append(contentsOf: pending)
        orderedIDs.append(contentsOf: pending.map(\.id))
        if let group = SupersetGrouping.groupForAdding(pending.count, asSuperset: asSuperset) {
            for addition in pending { supersetGroupIDs[addition.id] = group }
        }
    }

    public mutating func regroup(_ groupIDs: [UUID?]) {
        supersetGroupIDs = zip(orderedIDs, groupIDs).reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
}
