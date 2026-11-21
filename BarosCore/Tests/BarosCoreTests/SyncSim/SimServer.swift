import Foundation
@testable import BarosCore

/// An in-memory server with the sync behavior of `convex/sync.ts` for the
/// four workout kinds: the merge rule (`SimMergeRule`), parent checks with
/// their error codes, cascading deletes, placeholder tombstones and the
/// paged change feed. One owner.
@MainActor
final class SimServer {
    struct Row {
        var kind: SyncEntityKind
        var clientId: String
        var createdAt: Double
        var updatedAt: Double
        var deletedAt: Double?
        var serverUpdatedAt: Double
        var syncOrder: Double?
        var payload: SimPayload

        var version: SimMergeRule.StoredVersion {
            SimMergeRule.StoredVersion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                serverUpdatedAt: serverUpdatedAt,
                syncOrder: syncOrder
            )
        }
    }

    enum ParentState {
        case live
        case deleted(Double)
        case missing(code: String)
    }

    static let syncedKinds: [SyncEntityKind] = [.exercise, .workoutSession, .loggedExercise, .loggedSet]
    /// Small pages, so every pull pages.
    var pageLimit = 4
    private(set) var rows: [SyncEntityKind: [String: Row]] = [:]
    /// Records whose uploads are rejected as an invalid payload, to model poison.
    var poisonIDs: Set<String> = []
    private let clock: () -> Double
    private(set) var writeCount = 0

    init(clock: @escaping () -> Double) {
        self.clock = clock
    }

    func row(_ kind: SyncEntityKind, _ id: String) -> Row? {
        rows[kind]?[id]
    }

    var allRows: [Row] {
        rows.values.flatMap(\.values)
    }

    // MARK: Mutations

    func upsert(_ payload: SimPayload) throws -> SyncMutationResult {
        let kind = payload.kind
        let clientId = payload.clientId
        if poisonIDs.contains(clientId) {
            throw SyncServerRejection(code: "invalidPayload", message: "Simulated validation rejection")
        }
        let now = clock()
        let existing = row(kind, clientId)
        let keepsRecordLive = payload.deletedAt == nil && (existing == nil || existing?.deletedAt == nil)
        let parent: ParentState = keepsRecordLive ? parentState(of: payload) : .live
        let parentDeletedAt: Double? = if case let .deleted(deletedAt) = parent { deletedAt } else { nil }
        let decision = SimMergeRule.decideUpsert(
            existing?.version,
            SimMergeRule.IncomingVersion(
                updatedAt: payload.updatedAt,
                deletedAt: payload.deletedAt,
                base: payload.baseUpdatedAt.map { .value($0) } ?? .null
            ),
            nowSeconds: now,
            sameContent: existing.map { $0.payload.sameSyncedContent(as: payload) } ?? false,
            parentDeletedAt: parentDeletedAt
        )
        if case let .missing(code) = parent, keepsUploadLive(decision) {
            throw SyncServerRejection(code: code, message: "Simulated \(code)")
        }

        var nextVersion = serverVersionAllocator(now: now)
        switch decision {
        case .ignore:
            let existing = existing!
            if let deletedAt = existing.deletedAt {
                cascade(kind, clientId: clientId, updatedAt: existing.updatedAt, deletedAt: deletedAt, nextVersion: &nextVersion)
            }
            return SyncMutationResult(status: "ignored_stale", serverUpdatedAt: existing.serverUpdatedAt, updatedAt: existing.updatedAt)
        case let .insert(updatedAt, deletedAt, syncOrder, accepted):
            let serverUpdatedAt = nextVersion()
            rows[kind, default: [:]][clientId] = Row(
                kind: kind, clientId: clientId, createdAt: payload.createdAt, updatedAt: updatedAt,
                deletedAt: deletedAt, serverUpdatedAt: serverUpdatedAt, syncOrder: syncOrder, payload: payload
            )
            writeCount += 1
            if let deletedAt {
                cascade(kind, clientId: clientId, updatedAt: updatedAt, deletedAt: deletedAt, nextVersion: &nextVersion)
            }
            return SyncMutationResult(status: accepted ? "inserted" : "ignored_stale", serverUpdatedAt: serverUpdatedAt, updatedAt: updatedAt)
        case let .patch(takeIncomingFields, updatedAt, deletedAt, syncOrder, accepted):
            var row = existing!
            let serverUpdatedAt = nextVersion()
            if takeIncomingFields {
                row.payload = payload
                row.createdAt = payload.createdAt
            }
            row.updatedAt = updatedAt
            row.deletedAt = deletedAt
            row.serverUpdatedAt = serverUpdatedAt
            if let syncOrder { row.syncOrder = syncOrder }
            rows[kind]![clientId] = row
            writeCount += 1
            if let deletedAt {
                cascade(kind, clientId: clientId, updatedAt: updatedAt, deletedAt: deletedAt, nextVersion: &nextVersion)
            }
            return SyncMutationResult(status: accepted ? "updated" : "ignored_stale", serverUpdatedAt: serverUpdatedAt, updatedAt: updatedAt)
        }
    }

    func tombstone(_ kind: SyncEntityKind, clientId: String, deletedAt: Double) -> SyncMutationResult {
        let now = clock()
        let existing = row(kind, clientId)
        var nextVersion = serverVersionAllocator(now: now)
        switch SimMergeRule.decideTombstone(existing?.version, deletedAt: deletedAt, nowSeconds: now) {
        case let .insertPlaceholder(updatedAt, clampedDeletedAt):
            let serverUpdatedAt = nextVersion()
            rows[kind, default: [:]][clientId] = Row(
                kind: kind, clientId: clientId, createdAt: 0, updatedAt: updatedAt, deletedAt: clampedDeletedAt,
                serverUpdatedAt: serverUpdatedAt, syncOrder: nil, payload: .placeholder(kind, clientId: clientId)
            )
            writeCount += 1
            cascade(kind, clientId: clientId, updatedAt: updatedAt, deletedAt: clampedDeletedAt, nextVersion: &nextVersion)
            return SyncMutationResult(status: "tombstoned", serverUpdatedAt: serverUpdatedAt)
        case .alreadyDeleted:
            let existing = existing!
            cascade(kind, clientId: clientId, updatedAt: existing.updatedAt, deletedAt: existing.deletedAt!, nextVersion: &nextVersion)
            return SyncMutationResult(status: "tombstoned", serverUpdatedAt: existing.serverUpdatedAt)
        case let .tombstone(updatedAt, clampedDeletedAt):
            var row = existing!
            let serverUpdatedAt = nextVersion()
            row.updatedAt = updatedAt
            row.deletedAt = clampedDeletedAt
            row.serverUpdatedAt = serverUpdatedAt
            rows[kind]![clientId] = row
            writeCount += 1
            cascade(kind, clientId: clientId, updatedAt: updatedAt, deletedAt: clampedDeletedAt, nextVersion: &nextVersion)
            return SyncMutationResult(status: "tombstoned", serverUpdatedAt: serverUpdatedAt)
        }
    }

    // MARK: Change feed

    func fetchChanges(cursors: SyncChangeCursors, limit: Int) -> SyncFetchChangesResponse {
        let limit = min(limit, pageLimit)
        func page(_ kind: SyncEntityKind, after cursor: Double) -> (rows: [Row], hasMore: Bool) {
            let sorted = (rows[kind] ?? [:]).values
                .filter { $0.serverUpdatedAt > cursor }
                .sorted { $0.serverUpdatedAt < $1.serverUpdatedAt }
            return (Array(sorted.prefix(limit)), sorted.count > limit)
        }
        let exercises = page(.exercise, after: cursors.exercises)
        let sessions = page(.workoutSession, after: cursors.workoutSessions)
        let loggedExercises = page(.loggedExercise, after: cursors.loggedExercises)
        let sets = page(.loggedSet, after: cursors.loggedSets)
        func next(_ page: [Row], _ cursor: Double) -> Double {
            page.reduce(cursor) { max($0, $1.serverUpdatedAt) }
        }
        return SyncFetchChangesResponse(
            userSettings: [],
            exercises: exercises.rows.map { $0.payload.exerciseRecord(row: $0) },
            workoutSessions: sessions.rows.map { $0.payload.sessionRecord(row: $0) },
            loggedExercises: loggedExercises.rows.map { $0.payload.loggedExerciseRecord(row: $0) },
            loggedSets: sets.rows.map { $0.payload.setRecord(row: $0) },
            workoutTemplates: cursors.workoutTemplates == nil ? nil : [],
            cursors: SyncChangeCursors(
                userSettings: cursors.userSettings,
                exercises: next(exercises.rows, cursors.exercises),
                workoutSessions: next(sessions.rows, cursors.workoutSessions),
                loggedExercises: next(loggedExercises.rows, cursors.loggedExercises),
                loggedSets: next(sets.rows, cursors.loggedSets),
                workoutTemplates: cursors.workoutTemplates
            ),
            hasMore: SyncHasMore(
                userSettings: false,
                exercises: exercises.hasMore,
                workoutSessions: sessions.hasMore,
                loggedExercises: loggedExercises.hasMore,
                loggedSets: sets.hasMore,
                workoutTemplates: cursors.workoutTemplates == nil ? nil : false
            )
        )
    }

    // MARK: Internals

    /// Each written row gets its own change-feed version, never below wall
    /// time in milliseconds.
    private func serverVersionAllocator(now: Double) -> () -> Double {
        var next: Double?
        return { [self] in
            if next == nil {
                let maxExisting = allRows.map(\.serverUpdatedAt).max() ?? 0
                next = max((now * 1000).rounded(.down), maxExisting + 1)
            }
            defer { next! += 1 }
            return next!
        }
    }

    private func keepsUploadLive(_ decision: SimMergeRule.UpsertDecision) -> Bool {
        switch decision {
        case let .insert(_, deletedAt, _, _): deletedAt == nil
        case let .patch(takeIncomingFields, _, deletedAt, _, _): takeIncomingFields && deletedAt == nil
        case .ignore: false
        }
    }

    private func parentState(of payload: SimPayload) -> ParentState {
        func state(_ row: Row?) -> ParentState {
            guard let row else { return .missing(code: "missingParent") }
            if let deletedAt = row.deletedAt { return .deleted(deletedAt) }
            return .live
        }
        switch payload {
        case let .loggedExercise(record):
            let session = state(row(.workoutSession, record.sessionClientId))
            guard case .live = session, let exerciseID = record.exerciseClientId else { return session }
            // A tombstoned exercise is still a valid reference.
            return row(.exercise, exerciseID) == nil ? .missing(code: "missingExerciseReference") : .live
        case let .set(record):
            let loggedExercise = row(.loggedExercise, record.loggedExerciseClientId)
            let loggedExerciseState = state(loggedExercise)
            guard let loggedExercise, case .live = loggedExerciseState,
                  case let .loggedExercise(parentRecord) = loggedExercise.payload else {
                return loggedExerciseState
            }
            return state(row(.workoutSession, parentRecord.sessionClientId))
        default:
            return .live
        }
    }

    private func cascade(
        _ kind: SyncEntityKind,
        clientId: String,
        updatedAt: Double,
        deletedAt: Double,
        nextVersion: inout () -> Double
    ) {
        let childKind: SyncEntityKind
        switch kind {
        case .workoutSession: childKind = .loggedExercise
        case .loggedExercise: childKind = .loggedSet
        default: return
        }
        let children = (rows[childKind] ?? [:]).values.filter { $0.payload.parentID == clientId }
        for child in children.sorted(by: { $0.clientId < $1.clientId }) {
            var child = child
            if child.deletedAt == nil {
                let version = SimMergeRule.cascadedChildVersion(
                    childUpdatedAt: child.updatedAt, parentUpdatedAt: updatedAt, parentDeletedAt: deletedAt
                )
                child.updatedAt = version.updatedAt
                child.deletedAt = version.deletedAt
                child.serverUpdatedAt = nextVersion()
                rows[childKind]![child.clientId] = child
                writeCount += 1
            }
            if childKind == .loggedExercise {
                cascade(.loggedExercise, clientId: child.clientId, updatedAt: child.updatedAt,
                        deletedAt: child.deletedAt ?? deletedAt, nextVersion: &nextVersion)
            }
        }
    }
}

/// An upload as the server stores it.
enum SimPayload {
    case exercise(ExerciseSyncPayload)
    case session(WorkoutSessionSyncPayload)
    case loggedExercise(LoggedExerciseSyncPayload)
    case set(LoggedSetSyncPayload)

    var kind: SyncEntityKind {
        switch self {
        case .exercise: .exercise
        case .session: .workoutSession
        case .loggedExercise: .loggedExercise
        case .set: .loggedSet
        }
    }

    var clientId: String {
        switch self {
        case let .exercise(record): record.clientId
        case let .session(record): record.clientId
        case let .loggedExercise(record): record.clientId
        case let .set(record): record.clientId
        }
    }

    var createdAt: Double {
        switch self {
        case let .exercise(record): record.createdAt
        case let .session(record): record.createdAt
        case let .loggedExercise(record): record.createdAt
        case let .set(record): record.createdAt
        }
    }

    var updatedAt: Double {
        switch self {
        case let .exercise(record): record.updatedAt
        case let .session(record): record.updatedAt
        case let .loggedExercise(record): record.updatedAt
        case let .set(record): record.updatedAt
        }
    }

    var deletedAt: Double? {
        switch self {
        case let .exercise(record): record.deletedAt
        case let .session(record): record.deletedAt
        case let .loggedExercise(record): record.deletedAt
        case let .set(record): record.deletedAt
        }
    }

    var baseUpdatedAt: Double? {
        switch self {
        case let .exercise(record): record.baseUpdatedAt
        case let .session(record): record.baseUpdatedAt
        case let .loggedExercise(record): record.baseUpdatedAt
        case let .set(record): record.baseUpdatedAt
        }
    }

    var parentID: String? {
        switch self {
        case let .loggedExercise(record): record.sessionClientId
        case let .set(record): record.loggedExerciseClientId
        default: nil
        }
    }

    /// The field the simulator writes: "value|tag".
    var content: String {
        switch self {
        case let .exercise(record): record.name
        case let .session(record): record.title
        case let .loggedExercise(record): record.notes
        case let .set(record): record.notes
        }
    }

    var exerciseID: String? {
        if case let .loggedExercise(record) = self { return record.exerciseClientId }
        return nil
    }

    /// Whether every stored field but the version equals the upload's, as the
    /// server's `sameSyncedFields`.
    func sameSyncedContent(as other: SimPayload) -> Bool {
        func fields(_ payload: SimPayload) -> NSDictionary? {
            let encoder = JSONEncoder()
            let data: Data? = switch payload {
            case let .exercise(record): try? encoder.encode(record)
            case let .session(record): try? encoder.encode(record)
            case let .loggedExercise(record): try? encoder.encode(record)
            case let .set(record): try? encoder.encode(record)
            }
            guard let data, var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            object["updatedAt"] = nil
            object["baseUpdatedAt"] = nil
            return object as NSDictionary
        }
        guard kind == other.kind, let lhs = fields(self), let rhs = fields(other) else { return false }
        return lhs.isEqual(rhs)
    }

    static func placeholder(_ kind: SyncEntityKind, clientId: String) -> SimPayload {
        switch kind {
        case .exercise:
            .exercise(ExerciseSyncPayload(
                clientId: clientId, createdAt: 0, updatedAt: 0, deletedAt: nil, seedIdentifier: nil, name: "",
                categoryRaw: "other", equipmentRaw: "other", primaryMuscleRaw: "", primaryMuscleGroupRaw: "other",
                notes: "", isArchived: false, isSeeded: false
            ))
        case .workoutSession:
            .session(WorkoutSessionSyncPayload(
                clientId: clientId, createdAt: 0, updatedAt: 0, deletedAt: nil, title: "", startedAt: 0, endedAt: nil,
                durationSeconds: 0, notes: "", referenceNotes: nil, statusRaw: "discarded", sourceRaw: "blank",
                sourceSessionID: nil, healthLinkID: nil
            ))
        case .loggedExercise:
            .loggedExercise(LoggedExerciseSyncPayload(
                clientId: clientId, createdAt: 0, updatedAt: 0, deletedAt: nil, sessionClientId: "", exerciseClientId: nil,
                orderIndex: 0, exerciseSnapshotName: "", exerciseSnapshotEquipmentRaw: "other",
                exerciseSnapshotPrimaryMuscleGroupRaw: "other", hasSnapshotMetadata: false, notes: "",
                referenceNotes: nil, sourceLoggedExerciseID: nil
            ))
        default:
            .set(LoggedSetSyncPayload(
                clientId: clientId, createdAt: 0, updatedAt: 0, deletedAt: nil, loggedExerciseClientId: "", orderIndex: 0,
                weight: nil, reps: nil, rpe: nil, kindRaw: "working", isCompleted: false, completedAt: nil, notes: "",
                healthLinkID: nil, sourceLoggedSetID: nil
            ))
        }
    }

    func exerciseRecord(row: SimServer.Row) -> ExerciseSyncRecord {
        guard case let .exercise(record) = self else { fatalError("not an exercise") }
        return ExerciseSyncRecord(
            clientId: record.clientId, createdAt: row.createdAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt,
            serverUpdatedAt: row.serverUpdatedAt, seedIdentifier: record.seedIdentifier, name: record.name,
            categoryRaw: record.categoryRaw, equipmentRaw: record.equipmentRaw, primaryMuscleRaw: record.primaryMuscleRaw,
            primaryMuscleGroupRaw: record.primaryMuscleGroupRaw, notes: record.notes, isArchived: record.isArchived,
            isSeeded: record.isSeeded, trackingMethodRaw: record.trackingMethodRaw
        )
    }

    func sessionRecord(row: SimServer.Row) -> WorkoutSessionSyncRecord {
        guard case let .session(record) = self else { fatalError("not a session") }
        return WorkoutSessionSyncRecord(
            clientId: record.clientId, createdAt: row.createdAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt,
            serverUpdatedAt: row.serverUpdatedAt, title: record.title, startedAt: record.startedAt, endedAt: record.endedAt,
            durationSeconds: record.durationSeconds, notes: record.notes, referenceNotes: record.referenceNotes,
            statusRaw: record.statusRaw, sourceRaw: record.sourceRaw, sourceSessionID: record.sourceSessionID,
            healthLinkID: record.healthLinkID, sourceTemplateID: record.sourceTemplateID
        )
    }

    func loggedExerciseRecord(row: SimServer.Row) -> LoggedExerciseSyncRecord {
        guard case let .loggedExercise(record) = self else { fatalError("not a logged exercise") }
        return LoggedExerciseSyncRecord(
            clientId: record.clientId, createdAt: row.createdAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt,
            serverUpdatedAt: row.serverUpdatedAt, sessionClientId: record.sessionClientId,
            exerciseClientId: record.exerciseClientId, orderIndex: record.orderIndex,
            exerciseSnapshotName: record.exerciseSnapshotName,
            exerciseSnapshotEquipmentRaw: record.exerciseSnapshotEquipmentRaw,
            exerciseSnapshotPrimaryMuscleGroupRaw: record.exerciseSnapshotPrimaryMuscleGroupRaw,
            hasSnapshotMetadata: record.hasSnapshotMetadata, notes: record.notes, referenceNotes: record.referenceNotes,
            sourceLoggedExerciseID: record.sourceLoggedExerciseID, supersetGroupID: record.supersetGroupID,
            trackingMethodRaw: record.trackingMethodRaw
        )
    }

    func setRecord(row: SimServer.Row) -> LoggedSetSyncRecord {
        guard case let .set(record) = self else { fatalError("not a set") }
        return LoggedSetSyncRecord(
            clientId: record.clientId, createdAt: row.createdAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt,
            serverUpdatedAt: row.serverUpdatedAt, loggedExerciseClientId: record.loggedExerciseClientId,
            orderIndex: record.orderIndex, weight: record.weight, reps: record.reps, rpe: record.rpe,
            kindRaw: record.kindRaw, isCompleted: record.isCompleted, completedAt: record.completedAt, notes: record.notes,
            healthLinkID: record.healthLinkID, sourceLoggedSetID: record.sourceLoggedSetID,
            durationSeconds: record.durationSeconds
        )
    }
}
