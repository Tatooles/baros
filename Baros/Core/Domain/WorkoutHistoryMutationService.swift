import Foundation
import SwiftData

enum WorkoutHistoryMutationError: LocalizedError, Equatable {
    case cannotEditWorkout
    case ownerMismatch
    case ownerlessBootstrapBlocked
    case invalidDuration
    case missingLoggedExercise
    case missingLoggedSet

    var errorDescription: String? {
        switch self {
        case .cannotEditWorkout:
            return "Only completed workouts can be edited."
        case .ownerMismatch:
            return "This workout belongs to a different signed-in account."
        case .ownerlessBootstrapBlocked:
            return "This workout cannot be safely claimed for the current account."
        case .invalidDuration:
            return "Enter a valid duration in minutes."
        case .missingLoggedExercise:
            return "One of the edited exercises no longer exists."
        case .missingLoggedSet:
            return "One of the edited sets no longer exists."
        }
    }
}

struct CompletedWorkoutEditDraft {
    var title: String
    var notes: String
    var durationSeconds: Int
    var exercises: [CompletedWorkoutEditExerciseDraft]

    init(session: WorkoutSession) {
        title = session.title
        notes = session.notes
        durationSeconds = session.effectiveDurationSeconds()
        exercises = session.sortedLoggedExercises.map(CompletedWorkoutEditExerciseDraft.init(loggedExercise:))
    }
}

enum CompletedWorkoutDurationInput {
    static func minutesText(for durationSeconds: Int) -> String {
        String(max(0, durationSeconds) / 60)
    }

    static func durationSeconds(
        from minutesText: String,
        initialMinutesText: String,
        initialDurationSeconds: Int
    ) throws -> Int {
        let normalizedText = minutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText != initialMinutesText else {
            return max(0, initialDurationSeconds)
        }

        guard let minutes = Int(normalizedText), minutes >= 0, minutes <= Int.max / 60 else {
            throw WorkoutHistoryMutationError.invalidDuration
        }

        return minutes * 60
    }
}

struct CompletedWorkoutEditExerciseDraft: Identifiable {
    let id: UUID
    let exerciseSnapshotName: String
    let metadataDisplayText: String?
    var sets: [CompletedWorkoutEditSetDraft]

    init(loggedExercise: LoggedExercise) {
        id = loggedExercise.id
        exerciseSnapshotName = loggedExercise.exerciseSnapshotName
        metadataDisplayText = loggedExercise.metadataDisplayText
        sets = loggedExercise.sortedSets.map(CompletedWorkoutEditSetDraft.init(set:))
    }
}

struct CompletedWorkoutEditSetDraft: Identifiable {
    let id: UUID?
    var orderIndex: Int
    var weight: Double?
    var reps: Int?
    var rpe: Double?
    var kind: SetKind
    var isCompleted: Bool
    var completedAt: Date?
    var notes: String
    var isRemoved: Bool

    init(set: LoggedSet) {
        id = set.id
        orderIndex = set.orderIndex
        weight = set.weight
        reps = set.reps
        rpe = set.rpe
        kind = set.kind
        isCompleted = set.isCompleted
        completedAt = set.completedAt
        notes = set.notes
        isRemoved = false
    }

    init(
        orderIndex: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        kind: SetKind = .working,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        notes: String = "",
        isRemoved: Bool = false
    ) {
        id = nil
        self.orderIndex = orderIndex
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.kind = kind
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.notes = notes
        self.isRemoved = isRemoved
    }
}

@MainActor
struct WorkoutHistoryMutationService {
    private let recorder = SyncOutboxRecorder()

    func saveCompletedWorkoutEdit(
        _ draft: CompletedWorkoutEditDraft,
        for session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        try validateEditable(session, ownerTokenIdentifier: ownerTokenIdentifier)

        var didChange = false
        var didChangeSessionFields = false
        var didChangeChildRecords = false
        let shouldRecordOwnerlessOutbox = try shouldRecordOwnerlessOutbox(
            for: session,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )

        let normalizedDurationSeconds = max(0, draft.durationSeconds)
        let willChangeSessionFields = session.title != draft.title ||
            session.notes != draft.notes ||
            session.effectiveDurationSeconds() != normalizedDurationSeconds

        if willChangeSessionFields {
            try claimOwnerlessWorkoutGraphIfNeeded(
                session,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }

        if session.title != draft.title {
            session.title = draft.title
            didChangeSessionFields = true
        }

        if session.notes != draft.notes {
            session.notes = draft.notes
            didChangeSessionFields = true
        }

        if session.effectiveDurationSeconds() != normalizedDurationSeconds {
            session.durationSeconds = normalizedDurationSeconds
            session.endedAt = session.startedAt.addingTimeInterval(TimeInterval(normalizedDurationSeconds))
            didChangeSessionFields = true
        }

        if didChangeSessionFields {
            session.updatedAt = now
            try recordUpdateIfNeeded(
                entityKind: .workoutSession,
                entityID: session.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                shouldRecordOwnerlessOutbox: shouldRecordOwnerlessOutbox,
                context: context,
                now: now
            )
            didChange = true
        }

        let visibleLoggedExercises = session.sortedLoggedExercises
        var loggedExercisesByID: [UUID: LoggedExercise] = [:]
        for loggedExercise in visibleLoggedExercises {
            loggedExercisesByID[loggedExercise.id] = loggedExercise
        }

        for exerciseDraft in draft.exercises {
            guard let loggedExercise = loggedExercisesByID[exerciseDraft.id] else {
                throw WorkoutHistoryMutationError.missingLoggedExercise
            }

            let visibleSets = loggedExercise.sortedSets
            var visibleSetsByID: [UUID: LoggedSet] = [:]
            for set in visibleSets {
                visibleSetsByID[set.id] = set
            }

            for setDraft in exerciseDraft.sets {
                guard let setID = setDraft.id else { continue }
                guard let set = visibleSetsByID[setID] else {
                    throw WorkoutHistoryMutationError.missingLoggedSet
                }

                if setDraft.isRemoved {
                    try claimOwnerlessWorkoutGraphIfNeeded(
                        session,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        context: context,
                        now: now
                    )
                    set.markDeleted(now: now)
                    try recordDeleteIfNeeded(
                        entityKind: .loggedSet,
                        entityID: set.id,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        shouldRecordOwnerlessOutbox: shouldRecordOwnerlessOutbox,
                        context: context,
                        now: now
                    )
                    didChange = true
                    didChangeChildRecords = true
                } else if hasChanges(setDraft, for: set) {
                    try claimOwnerlessWorkoutGraphIfNeeded(
                        session,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        context: context,
                        now: now
                    )
                    _ = apply(setDraft, to: set, now: now)
                    try recordUpdateIfNeeded(
                        entityKind: .loggedSet,
                        entityID: set.id,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        shouldRecordOwnerlessOutbox: shouldRecordOwnerlessOutbox,
                        context: context,
                        now: now
                    )
                    didChange = true
                    didChangeChildRecords = true
                }
            }

            if setsNeedReindex(for: loggedExercise) {
                try claimOwnerlessWorkoutGraphIfNeeded(
                    session,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )
                _ = try reindexVisibleSets(
                    for: loggedExercise,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    shouldRecordOwnerlessOutbox: shouldRecordOwnerlessOutbox,
                    context: context,
                    now: now
                )
                didChange = true
                didChangeChildRecords = true
            }

            let newSetDrafts = exerciseDraft.sets.filter { $0.id == nil && !$0.isRemoved && !isEmptyNewSet($0) }
            for setDraft in newSetDrafts {
                try claimOwnerlessWorkoutGraphIfNeeded(
                    session,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )
                let nextOrderIndex = (loggedExercise.sortedSets.map(\.orderIndex).max() ?? -1) + 1
                let set = LoggedSet(
                    orderIndex: nextOrderIndex,
                    weight: setDraft.weight,
                    reps: setDraft.reps,
                    rpe: setDraft.rpe,
                    kind: setDraft.kind,
                    isCompleted: setDraft.isCompleted,
                    completedAt: setDraft.isCompleted ? (setDraft.completedAt ?? now) : nil,
                    notes: setDraft.notes,
                    createdAt: now,
                    updatedAt: now
                )
                set.loggedExercise = loggedExercise
                context.insert(set)
                loggedExercise.sets.append(set)
                try recordCreateIfNeeded(
                    entityKind: .loggedSet,
                    entityID: set.id,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    shouldRecordOwnerlessOutbox: shouldRecordOwnerlessOutbox,
                    context: context,
                    now: now
                )
                didChange = true
                didChangeChildRecords = true
            }
        }

        if didChangeChildRecords && !didChangeSessionFields {
            session.updatedAt = now
            try recordUpdateIfNeeded(
                entityKind: .workoutSession,
                entityID: session.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                shouldRecordOwnerlessOutbox: shouldRecordOwnerlessOutbox,
                context: context,
                now: now
            )
        }

        guard didChange else { return }
        try context.save()
    }

    func deleteWorkoutHistory(
        _ session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        try validateEditable(session, ownerTokenIdentifier: ownerTokenIdentifier)

        session.syncOwnerTokenIdentifier = ownerTokenIdentifier ?? session.syncOwnerTokenIdentifier
        session.markDeletedCascade(now: now)
        try recorder.recordDelete(
            entityKind: .workoutSession,
            entityID: session.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )

        for loggedExercise in session.loggedExercises {
            try recorder.recordDelete(
                entityKind: .loggedExercise,
                entityID: loggedExercise.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )

            for set in loggedExercise.sets {
                try recorder.recordDelete(
                    entityKind: .loggedSet,
                    entityID: set.id,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )
            }
        }

        try context.save()
    }

    private func validateEditable(_ session: WorkoutSession, ownerTokenIdentifier: String?) throws {
        guard session.status == .completed, !session.isDeleted else {
            throw WorkoutHistoryMutationError.cannotEditWorkout
        }

        guard session.allowsHistoryMutation(ownerTokenIdentifier: ownerTokenIdentifier) else {
            throw WorkoutHistoryMutationError.ownerMismatch
        }
    }

    private func claimOwnerlessWorkoutGraphIfNeeded(
        _ session: WorkoutSession,
        ownerTokenIdentifier: String?,
        context: ModelContext,
        now: Date
    ) throws {
        guard let ownerTokenIdentifier, session.syncOwnerTokenIdentifier == nil else { return }
        guard try OwnerlessWorkoutGraphBootstrapPolicy.canBootstrap(
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ) else {
            throw WorkoutHistoryMutationError.ownerlessBootstrapBlocked
        }

        session.syncOwnerTokenIdentifier = ownerTokenIdentifier
        try recorder.recordCreate(
            entityKind: .workoutSession,
            entityID: session.id,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
        for loggedExercise in session.sortedLoggedExercises where !loggedExercise.isDeleted {
            try recorder.recordCreate(
                entityKind: .loggedExercise,
                entityID: loggedExercise.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
            for set in loggedExercise.sortedSets where !set.isDeleted {
                try recorder.recordCreate(
                    entityKind: .loggedSet,
                    entityID: set.id,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )
            }
        }
    }

    private func hasChanges(_ draft: CompletedWorkoutEditSetDraft, for set: LoggedSet) -> Bool {
        !Self.weightsAreEqual(set.weight, draft.weight) ||
            set.reps != draft.reps ||
            !Self.weightsAreEqual(set.rpe, draft.rpe) ||
            set.kind != draft.kind ||
            set.isCompleted != draft.isCompleted ||
            set.notes != draft.notes
    }

    private func apply(_ draft: CompletedWorkoutEditSetDraft, to set: LoggedSet, now: Date) -> Bool {
        var didChange = false

        if !Self.weightsAreEqual(set.weight, draft.weight) {
            set.weight = draft.weight
            didChange = true
        }

        if set.reps != draft.reps {
            set.reps = draft.reps
            didChange = true
        }

        if !Self.weightsAreEqual(set.rpe, draft.rpe) {
            set.rpe = draft.rpe
            didChange = true
        }

        if set.kind != draft.kind {
            set.kindRaw = draft.kind.rawValue
            didChange = true
        }

        if set.isCompleted != draft.isCompleted {
            set.isCompleted = draft.isCompleted
            set.completedAt = draft.isCompleted ? now : nil
            didChange = true
        }

        if set.notes != draft.notes {
            set.notes = draft.notes
            didChange = true
        }

        guard didChange else { return false }
        set.updatedAt = now
        return true
    }

    private func setsNeedReindex(for loggedExercise: LoggedExercise) -> Bool {
        loggedExercise.sortedSets.enumerated().contains { index, set in
            set.orderIndex != index
        }
    }

    private func reindexVisibleSets(
        for loggedExercise: LoggedExercise,
        ownerTokenIdentifier: String?,
        shouldRecordOwnerlessOutbox: Bool,
        context: ModelContext,
        now: Date
    ) throws -> Bool {
        var didChange = false
        for (index, set) in loggedExercise.sortedSets.enumerated() where set.orderIndex != index {
            set.orderIndex = index
            set.updatedAt = now
            try recordUpdateIfNeeded(
                entityKind: .loggedSet,
                entityID: set.id,
                ownerTokenIdentifier: ownerTokenIdentifier,
                shouldRecordOwnerlessOutbox: shouldRecordOwnerlessOutbox,
                context: context,
                now: now
            )
            didChange = true
        }
        return didChange
    }

    private func shouldRecordOwnerlessOutbox(
        for session: WorkoutSession,
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) throws -> Bool {
        guard ownerTokenIdentifier == nil, session.syncOwnerTokenIdentifier == nil else {
            return false
        }

        return try hasActiveOwnerlessOutboxEntry(
            entityKind: .workoutSession,
            entityID: session.id,
            context: context
        )
    }

    private func hasActiveOwnerlessOutboxEntry(
        entityKind: SyncEntityKind,
        entityID: UUID,
        context: ModelContext
    ) throws -> Bool {
        let entityKindRaw = entityKind.rawValue
        let completedStatus = SyncOutboxStatus.completed.rawValue
        return try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.entityKindRaw == entityKindRaw
                    && entry.entityID == entityID
                    && entry.ownerTokenIdentifier == nil
                    && entry.statusRaw != completedStatus
                    && entry.operationRaw != ""
            }
        ))
        .contains { $0.isActive && $0.operation != nil }
    }

    private func recordCreateIfNeeded(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String?,
        shouldRecordOwnerlessOutbox: Bool,
        context: ModelContext,
        now: Date
    ) throws {
        guard ownerTokenIdentifier != nil || shouldRecordOwnerlessOutbox else { return }
        try recorder.recordCreate(
            entityKind: entityKind,
            entityID: entityID,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
    }

    private func recordUpdateIfNeeded(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String?,
        shouldRecordOwnerlessOutbox: Bool,
        context: ModelContext,
        now: Date
    ) throws {
        guard ownerTokenIdentifier != nil || shouldRecordOwnerlessOutbox else { return }
        try recorder.recordUpdate(
            entityKind: entityKind,
            entityID: entityID,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
    }

    private func recordDeleteIfNeeded(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String?,
        shouldRecordOwnerlessOutbox: Bool,
        context: ModelContext,
        now: Date
    ) throws {
        guard ownerTokenIdentifier != nil || shouldRecordOwnerlessOutbox else { return }
        try recorder.recordDelete(
            entityKind: entityKind,
            entityID: entityID,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context,
            now: now
        )
    }

    private func isEmptyNewSet(_ draft: CompletedWorkoutEditSetDraft) -> Bool {
        draft.weight == nil &&
            draft.reps == nil &&
            draft.rpe == nil &&
            draft.kind == .working &&
            !draft.isCompleted &&
            draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func weightsAreEqual(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return abs(lhs - rhs) < 0.0001
        default:
            return false
        }
    }
}
