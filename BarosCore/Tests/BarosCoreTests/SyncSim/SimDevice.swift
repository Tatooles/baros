import Foundation
import SwiftData
@testable import BarosCore

let simOwner = "https://sim.clerk.test|sim_owner"

/// What the harness knows about every user operation, for the oracle.
@MainActor
final class SimOperationLog {
    /// Record key -> parent key.
    var created: [String: String?] = [:]
    var deleted: Set<String> = []
    var writtenValues: [String: Set<String>] = [:]
    /// Logged exercise key -> the exercise key it names.
    var exerciseReferences: [String: String] = [:]
    /// Tags of writes that a later write replaced after its device had seen them.
    var superseded: [String: Set<String>] = [:]
    var trace: [String] = []

    func noteCreate(_ key: String, parentKey: String?, value: String) {
        created[key] = parentKey
        writtenValues[key, default: []].insert(value)
    }

    func isDeletedByPolicy(_ key: String) -> Bool {
        var current: String? = key
        while let key = current {
            if deleted.contains(key) { return true }
            current = created[key] ?? nil
        }
        return false
    }
}

func simKey(_ kind: SyncEntityKind, _ id: String) -> String {
    "\(kind.rawValue):\(id)"
}

/// One simulated iPhone: its own SwiftData store and the app's real
/// `SyncCoordinator`, talking to the simulated server through a client that
/// pauses at every network call and can lose requests and responses.
@MainActor
final class SimDevice {
    let name: String
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    private(set) var coordinator: SyncCoordinator!
    private let server: SimServer
    private let log: SimOperationLog
    private let simTime: () -> Double
    private let recorder = SyncOutboxRecorder()
    let gate = SimGate()
    var rng: SimRng
    var clockOffset: Double = 0
    var online = true
    var dropRequestRate = 0.0
    var dropResponseRate = 0.0
    private(set) var runTask: Task<Void, Never>?
    private var counter = 0

    init(name: String, server: SimServer, log: SimOperationLog, seed: UInt32, simTime: @escaping () -> Double) throws {
        self.name = name
        self.server = server
        self.log = log
        self.simTime = simTime
        rng = SimRng(seed: seed)
        container = try SwiftDataTestSupport.makeInMemoryContainer()
        coordinator = SyncCoordinator(
            client: SimDeviceClient(device: self),
            maxPendingPushEntriesPerRun: 8,
            clock: { [unowned self] in self.nowDate }
        )
    }

    var now: Double { simTime() + clockOffset }
    var nowDate: Date { Date(timeIntervalSince1970: now) }
    var isRunning: Bool { runTask != nil }

    // MARK: Network

    func performCall<T>(_ operation: (SimServer) throws -> T) async throws -> T {
        await gate.park()
        guard online else { throw URLError(.notConnectedToInternet) }
        if rng.chance(dropRequestRate) { throw URLError(.networkConnectionLost) }
        let result = try operation(server)
        // The response is in flight: other devices and local edits run now.
        await gate.park()
        if rng.chance(dropResponseRate) { throw URLError(.networkConnectionLost) }
        return result
    }

    func startRun() async {
        guard runTask == nil else { return }
        runTask = await gate.start { [unowned self] in
            _ = try? await coordinator.run(ownerTokenIdentifier: simOwner, context: context)
            runTask = nil
        }
    }

    func stepRun() async {
        guard runTask != nil else { return }
        await gate.step()
    }

    func finishRun(maxSteps: Int = 20_000) async throws {
        var steps = 0
        while runTask != nil {
            await gate.step()
            steps += 1
            if steps > maxSteps { throw SimError.runDidNotFinish(name) }
        }
    }

    // MARK: Records

    enum Record {
        case exercise(Exercise)
        case session(WorkoutSession)
        case loggedExercise(LoggedExercise)
        case set(LoggedSet)

        var kind: SyncEntityKind {
            switch self {
            case .exercise: .exercise
            case .session: .workoutSession
            case .loggedExercise: .loggedExercise
            case .set: .loggedSet
            }
        }

        var stamped: any SyncEditStamped {
            switch self {
            case let .exercise(model): model
            case let .session(model): model
            case let .loggedExercise(model): model
            case let .set(model): model
            }
        }

        var id: String { stamped.id.uuidString.lowercased() }
        var key: String { simKey(kind, id) }

        var content: String {
            get {
                switch self {
                case let .exercise(model): model.name
                case let .session(model): model.title
                case let .loggedExercise(model): model.notes
                case let .set(model): model.notes
                }
            }
            nonmutating set {
                switch self {
                case let .exercise(model): model.name = newValue
                case let .session(model): model.title = newValue
                case let .loggedExercise(model): model.notes = newValue
                case let .set(model): model.notes = newValue
                }
            }
        }

        var session: WorkoutSession? {
            switch self {
            case .exercise: nil
            case let .session(model): model
            case let .loggedExercise(model): model.session
            case let .set(model): model.loggedExercise?.session
            }
        }
    }

    func allRecords() -> [Record] {
        let exercises = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map(Record.exercise)
        let sessions = ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []).map(Record.session)
        let loggedExercises = ((try? context.fetch(FetchDescriptor<LoggedExercise>())) ?? []).map(Record.loggedExercise)
        let sets = ((try? context.fetch(FetchDescriptor<LoggedSet>())) ?? []).map(Record.set)
        return exercises + sessions + loggedExercises + sets
    }

    /// What a person sees: records that are live with every ancestor live.
    func visible() -> [String: String] {
        var visible: [String: String] = [:]
        for record in allRecords() {
            switch record {
            case let .exercise(model):
                if model.deletedAt == nil {
                    visible[record.key] = "\(model.name)|parent=nil|exercise=nil"
                }
            case let .session(model):
                if model.deletedAt == nil {
                    visible[record.key] = "\(model.title)|parent=nil|exercise=nil"
                }
            case let .loggedExercise(model):
                if model.deletedAt == nil, let session = model.session, session.deletedAt == nil {
                    let exercise = model.exercise?.id.uuidString.lowercased() ?? "nil"
                    visible[record.key] = "\(model.notes)|parent=\(session.id.uuidString.lowercased())|exercise=\(exercise)"
                }
            case let .set(model):
                if model.deletedAt == nil, let loggedExercise = model.loggedExercise, loggedExercise.deletedAt == nil,
                   let session = loggedExercise.session, session.deletedAt == nil {
                    visible[record.key] = "\(model.notes)|parent=\(loggedExercise.id.uuidString.lowercased())|exercise=nil"
                }
            }
        }
        return visible
    }

    func visibleRecords(_ kind: SyncEntityKind? = nil) -> [Record] {
        let visible = visible()
        return allRecords()
            .filter { visible[$0.key] != nil && (kind == nil || $0.kind == kind) }
            .sorted { $0.key < $1.key }
    }

    func record(forKey key: String) -> Record? {
        allRecords().first { $0.key == key }
    }

    func activeEntries() -> [SyncOutboxEntry] {
        ((try? context.fetch(FetchDescriptor<SyncOutboxEntry>())) ?? []).filter { $0.isActive }
    }

    func outboxSummary() -> [String] {
        activeEntries()
            .map { "\($0.entityKindRaw):\($0.entityID.uuidString.lowercased()) \($0.operationRaw) \($0.statusRaw) rejections=\($0.rejectionCount)" }
            .sorted()
    }

    // MARK: User operations

    private func nextContent() -> String {
        counter += 1
        let value = "\(name)-v\(counter)"
        counter += 1
        return "\(value)|\(name)-w\(counter)"
    }

    private static func value(of content: String) -> String {
        String(content.prefix { $0 != "|" })
    }

    private static func tag(of content: String) -> String {
        content.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
    }

    private func save() {
        try? context.save()
    }

    func createExercise() {
        let content = nextContent()
        let exercise = Exercise(
            name: content, category: .strength, equipment: .barbell, primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: simOwner, createdAt: nowDate, updatedAt: nowDate
        )
        context.insert(exercise)
        try? recorder.recordCreate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
        let record = Record.exercise(exercise)
        log.noteCreate(record.key, parentKey: nil, value: Self.value(of: content))
        log.trace.append("\(name) create \(record.key)")
        save()
    }

    func createWorkout() {
        let content = nextContent()
        let session = WorkoutSession(
            title: content, startedAt: nowDate, endedAt: nowDate.addingTimeInterval(60), durationSeconds: 60,
            status: .completed, source: .blank, createdAt: nowDate, updatedAt: nowDate, syncOwnerTokenIdentifier: simOwner
        )
        context.insert(session)
        var created: [(Record, String?)] = [(.session(session), nil)]
        let liveExercises = allRecords().compactMap { record -> Exercise? in
            if case let .exercise(model) = record, model.deletedAt == nil { return model }
            return nil
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        for index in 0 ..< 1 + rng.int(2) {
            // A workout may reference an exercise another device deleted (#94).
            let exercise = !liveExercises.isEmpty && rng.chance(0.7) ? rng.pick(liveExercises) : nil
            let loggedExercise = LoggedExercise(
                orderIndex: index, exercise: exercise, exerciseSnapshotName: "Bench Press", notes: nextContent(),
                createdAt: nowDate, updatedAt: nowDate
            )
            loggedExercise.session = session
            session.loggedExercises.append(loggedExercise)
            context.insert(loggedExercise)
            created.append((.loggedExercise(loggedExercise), simKey(.workoutSession, session.id.uuidString.lowercased())))
            if let exercise {
                log.exerciseReferences[Record.loggedExercise(loggedExercise).key] = simKey(.exercise, exercise.id.uuidString.lowercased())
            }
            for setIndex in 0 ..< 1 + rng.int(2) {
                let set = LoggedSet(
                    orderIndex: setIndex, weight: 100, reps: 5, isCompleted: true, completedAt: nowDate,
                    notes: nextContent(), createdAt: nowDate, updatedAt: nowDate
                )
                set.loggedExercise = loggedExercise
                loggedExercise.sets.append(set)
                context.insert(set)
                created.append((.set(set), simKey(.loggedExercise, loggedExercise.id.uuidString.lowercased())))
            }
        }
        for (record, parentKey) in created {
            try? recorder.recordCreate(entityKind: record.kind, entityID: record.stamped.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
            log.noteCreate(record.key, parentKey: parentKey, value: Self.value(of: record.content))
        }
        log.trace.append("\(name) create workout \(simKey(.workoutSession, session.id.uuidString.lowercased())) (\(created.count) records)")
        save()
    }

    /// A completed-workout edit stamps the workout too, as the history editor does.
    private func touchSession(of record: Record) {
        guard let session = record.session, record.kind != .workoutSession else { return }
        let sessionRecord = Record.session(session)
        let content = nextContent()
        log.superseded[sessionRecord.key, default: []].insert(Self.tag(of: session.title))
        // Keep the visible value, change the tag: the session was written.
        session.title = "\(Self.value(of: session.title))|\(Self.tag(of: content))"
        session.stampEdit(now: nowDate)
        try? recorder.recordUpdate(entityKind: .workoutSession, entityID: session.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
    }

    @discardableResult
    func edit(_ record: Record) -> String {
        let content = nextContent()
        log.superseded[record.key, default: []].insert(Self.tag(of: record.content))
        record.content = content
        record.stamped.stampEdit(now: nowDate)
        try? recorder.recordUpdate(entityKind: record.kind, entityID: record.stamped.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
        touchSession(of: record)
        log.writtenValues[record.key, default: []].insert(Self.value(of: content))
        log.trace.append("\(name) edit \(record.key) -> \(content) @\(String(format: "%.3f", record.stamped.updatedAt.timeIntervalSince1970))")
        save()
        return Self.value(of: content)
    }

    func delete(_ record: Record) {
        switch record {
        case let .session(session):
            session.markDeletedCascade(now: nowDate)
            try? recorder.recordDelete(entityKind: .workoutSession, entityID: session.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
            for loggedExercise in session.loggedExercises {
                try? recorder.recordDelete(entityKind: .loggedExercise, entityID: loggedExercise.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
                for set in loggedExercise.sets {
                    try? recorder.recordDelete(entityKind: .loggedSet, entityID: set.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
                }
            }
        case let .exercise(model):
            model.markDeleted(now: nowDate)
            try? recorder.recordDelete(entityKind: .exercise, entityID: model.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
        case let .loggedExercise(model):
            model.markDeleted(now: nowDate)
            try? recorder.recordDelete(entityKind: .loggedExercise, entityID: model.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
            touchSession(of: record)
        case let .set(model):
            model.markDeleted(now: nowDate)
            try? recorder.recordDelete(entityKind: .loggedSet, entityID: model.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
            touchSession(of: record)
        }
        log.deleted.insert(record.key)
        log.trace.append("\(name) delete \(record.key)")
        save()
    }

    func randomUserOperation() {
        let visible = visibleRecords()
        let operation = rng.weighted([
            ("createWorkout", visible.count < 4 ? 4 : 1),
            ("createExercise", 1),
            ("edit", visible.isEmpty ? 0 : 5),
            ("addSet", visible.isEmpty ? 0 : 2),
            ("deleteSet", visible.isEmpty ? 0 : 1),
            ("deleteWorkout", visible.isEmpty ? 0 : 1.5),
            ("deleteExercise", visible.isEmpty ? 0 : 0.5),
        ])
        switch operation {
        case "createWorkout":
            createWorkout()
        case "createExercise":
            createExercise()
        case "edit":
            edit(rng.pick(visible))
        case "addSet":
            let loggedExercises = visibleRecords(.loggedExercise)
            guard !loggedExercises.isEmpty, case let .loggedExercise(loggedExercise) = rng.pick(loggedExercises) else { return }
            addSet(to: loggedExercise)
        case "deleteSet":
            let sets = visibleRecords(.loggedSet)
            if !sets.isEmpty { delete(rng.pick(sets)) }
        case "deleteWorkout":
            let sessions = visibleRecords(.workoutSession)
            if !sessions.isEmpty { delete(rng.pick(sessions)) }
        default:
            let exercises = visibleRecords(.exercise)
            guard !exercises.isEmpty, case let .exercise(exercise) = rng.pick(exercises) else { return }
            // Exercise.removalOutcome archives, a field edit, when local history uses it.
            let hasHistory = allRecords().contains { record in
                if case let .loggedExercise(model) = record { return model.exercise?.id == exercise.id }
                return false
            }
            if hasHistory { edit(.exercise(exercise)) } else { delete(.exercise(exercise)) }
        }
    }

    func addSet(to loggedExercise: LoggedExercise) {
        let set = LoggedSet(
            orderIndex: loggedExercise.sets.count, weight: 100, reps: 5, isCompleted: true, completedAt: nowDate,
            notes: nextContent(), createdAt: nowDate, updatedAt: nowDate
        )
        set.loggedExercise = loggedExercise
        loggedExercise.sets.append(set)
        context.insert(set)
        let record = Record.set(set)
        try? recorder.recordCreate(entityKind: .loggedSet, entityID: set.id, ownerTokenIdentifier: simOwner, context: context, now: nowDate)
        touchSession(of: record)
        log.noteCreate(record.key, parentKey: simKey(.loggedExercise, loggedExercise.id.uuidString.lowercased()), value: Self.value(of: record.content))
        log.trace.append("\(name) add set \(record.key)")
        save()
    }
}

enum SimError: Error {
    case runDidNotFinish(String)
}

/// The device's network client: every call pauses for the scheduler, then
/// reaches the simulated server.
final class SimDeviceClient: SyncClient, @unchecked Sendable {
    private unowned let device: SimDevice

    init(device: SimDevice) {
        self.device = device
    }

    private func call<T>(_ operation: @escaping @MainActor (SimServer) throws -> T) async throws -> T {
        try await device.performCallUnchecked(SimUnchecked(value: operation)).value
    }

    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult {
        SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult {
        try await call { try $0.upsert(.exercise(record)) }
    }

    func upsertWorkoutSession(_ record: WorkoutSessionSyncPayload) async throws -> SyncMutationResult {
        try await call { try $0.upsert(.session(record)) }
    }

    func upsertLoggedExercise(_ record: LoggedExerciseSyncPayload) async throws -> SyncMutationResult {
        try await call { try $0.upsert(.loggedExercise(record)) }
    }

    func upsertLoggedSet(_ record: LoggedSetSyncPayload) async throws -> SyncMutationResult {
        try await call { try $0.upsert(.set(record)) }
    }

    func upsertWorkoutTemplate(_ record: WorkoutTemplateSyncPayload) async throws -> SyncMutationResult {
        SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult {
        let id = clientId.uuidString.lowercased()
        let seconds = deletedAt.timeIntervalSince1970
        return try await call { $0.tombstone(entityKind, clientId: id, deletedAt: seconds) }
    }

    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse {
        let cursors = SimUnchecked(value: cursors)
        return try await call { $0.fetchChanges(cursors: cursors.value, limit: limit) }
    }

    func deleteAccountData(cancellationToken: UUID) async throws -> AccountDataDeletionResult {
        fatalError("not simulated")
    }

    func cancelAccountDeletion(cancellationToken: UUID) async throws -> AccountDeletionCancellationResult {
        fatalError("not simulated")
    }
}

extension SimDevice {
    func performCallUnchecked<T>(_ operation: SimUnchecked<@MainActor (SimServer) throws -> T>) async throws -> SimUnchecked<T> {
        SimUnchecked(value: try await performCall { try operation.value($0) })
    }
}
