import Foundation
import SwiftData
@testable import BarosCore

enum SimClockProfile {
    case honest, jitter, fast, farFuture, slow, deadClock, jumpy
}

struct SimFleetConfig {
    var seed: UInt32
    var clocks: [SimClockProfile]
    var steps = 220
    var dropRequestRate = 0.08
    var dropResponseRate = 0.08
    var offlineRate = 0.4
    var poison = false
    /// Seeds each device with deletes an older server undid (#97), and makes
    /// every device run the one-time update step.
    var seedsSplitBrain = false
}

struct SimFleetReport {
    var seed: UInt32
    var failures: [String]
    var trace: [String]
    var serverWrites = 0
    var records = 0
    var visibleOnServer = 0
}

/// The Swift port of `convex/syncSim/fleet.sim.ts`, with the app's real
/// coordinator on every device. Its oracle is the same:
/// - I1: every device shows exactly what the server holds;
/// - I2: outboxes drain, and a poison entry ends failed or dead-lettered;
/// - I3: every device can edit a live record and delete a workout;
/// - I4: nothing deleted comes back, nothing created is lost, no value is
///   invented, and no write survives that a later write replaced after seeing it.
@MainActor
final class SimFleet {
    static let simulationEpoch = Double(1_767_225_600) // 2026-01-01
    private static let fastClockThresholdSeconds = 2.0

    let config: SimFleetConfig
    var rng: SimRng
    var time = SimFleet.simulationEpoch
    private(set) var server: SimServer!
    let log = SimOperationLog()
    private(set) var devices: [SimDevice] = []

    init(config: SimFleetConfig) throws {
        self.config = config
        rng = SimRng(seed: config.seed)
        server = SimServer(clock: { [unowned self] in time })
        for (index, profile) in config.clocks.enumerated() {
            let device = try SimDevice(
                name: "d\(index)",
                server: server,
                log: log,
                seed: config.seed &* 31 &+ UInt32(index) &+ 1,
                simTime: { [unowned self] in time }
            )
            device.clockOffset = initialOffset(profile)
            device.dropRequestRate = config.dropRequestRate
            device.dropResponseRate = config.dropResponseRate
            devices.append(device)
        }
    }

    private func initialOffset(_ profile: SimClockProfile) -> Double {
        switch profile {
        case .honest, .jumpy: 0
        case .jitter: rng.real(-2, 2)
        case .fast: rng.real(60, 3600)
        case .farFuture: 30 * 24 * 3600
        case .slow: -rng.real(60, 24 * 3600)
        // A dead RTC restarts the clock at the reference date.
        case .deadClock: Double(978_307_200) - SimFleet.simulationEpoch
        }
    }

    func run() async throws -> SimFleetReport {
        if config.seedsSplitBrain {
            try seedSplitBrain()
        }
        try await chaos()
        var failures: [String] = []
        if try await !quiesce() {
            failures.append("Q devices did not reach a stable state within the round limit")
        }
        failures += check()
        if failures.isEmpty {
            failures += try await checkEditability()
            failures += check()
        }
        return SimFleetReport(
            seed: config.seed,
            failures: failures,
            trace: log.trace,
            serverWrites: server.writeCount,
            records: log.created.count,
            visibleOnServer: serverVisible().count
        )
    }

    // MARK: Chaos

    private func advanceTime() {
        time += rng.chance(0.03) ? rng.real(600, 8 * 3600) : rng.real(0.002, 20)
    }

    func chaos() async throws {
        for _ in 0 ..< config.steps {
            advanceTime()
            let index = rng.int(devices.count)
            let device = devices[index]
            if device.isRunning && rng.chance(0.65) {
                await device.stepRun()
                continue
            }
            let action = rng.weighted([
                ("user", 6),
                ("sync", 3),
                ("toggleOnline", config.offlineRate),
                ("clockJump", config.clocks[index] == .jumpy ? 1 : 0),
                ("poison", config.poison && server.poisonIDs.isEmpty ? 0.3 : 0),
            ])
            switch action {
            case "user":
                device.randomUserOperation()
            case "sync":
                await device.startRun()
            case "toggleOnline":
                device.online.toggle()
                log.trace.append("\(device.name) \(device.online ? "online" : "offline")")
            case "clockJump":
                // Someone sets the date by hand, forwards or backwards.
                device.clockOffset = rng.pick([-90 * 86400, -3600, 0, 3600, 45 * 86400])
                log.trace.append("\(device.name) clock offset \(device.clockOffset)")
            default:
                let waiting = Set(device.activeEntries().map { $0.entityID.uuidString.lowercased() })
                // Any kind: a poisoned workout must not hold back other workouts (#96).
                let candidates = device.allRecords().filter { waiting.contains($0.id) }
                if !candidates.isEmpty {
                    let poisoned = rng.pick(candidates.sorted { $0.key < $1.key })
                    server.poisonIDs.insert(poisoned.id)
                    log.trace.append("server poisons \(poisoned.key)")
                }
            }
        }
    }

    /// Faults off, everyone online, clocks left as they are. Sync until stable.
    func quiesce(maxRounds: Int = 14) async throws -> Bool {
        for device in devices {
            device.online = true
            device.dropRequestRate = 0
            device.dropResponseRate = 0
            try await device.finishRun()
        }
        var previous = ""
        for _ in 0 ..< maxRounds {
            // Long enough for every backoff to expire.
            time += 7 * 3600
            for device in devices {
                await device.startRun()
                try await device.finishRun()
            }
            let fingerprint = devices.map { device in
                device.visible().sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
                    + "#" + device.outboxSummary().joined(separator: ",")
            }.joined(separator: "\n")
            if fingerprint == previous { return true }
            previous = fingerprint
        }
        return false
    }

    // MARK: Older-server damage

    /// The #97 split brain an older server left behind: records device 0
    /// deleted that the server still holds live.
    /// - A workout every device holds, so other devices may also edit or
    ///   delete it during the run.
    /// - An exercise and a workout only device 0 ever held, behind every
    ///   device's cursor, which only device 0's client can heal.
    private func seedSplitBrain() throws {
        let created = time - 3600
        func seedSession(_ id: UUID, content: String) throws -> WorkoutSessionSyncPayload {
            let payload = WorkoutSessionSyncPayload(
                clientId: id.uuidString.lowercased(), createdAt: created, updatedAt: created, deletedAt: nil,
                title: content, startedAt: created, endedAt: created + 60, durationSeconds: 60, notes: "",
                referenceNotes: nil, statusRaw: "completed", sourceRaw: "blank", sourceSessionID: nil, healthLinkID: nil
            )
            _ = try server.upsert(.session(payload))
            let key = simKey(.workoutSession, id.uuidString.lowercased())
            log.noteCreate(key, parentKey: nil, value: String(content.prefix { $0 != "|" }))
            log.deleted.insert(key)
            log.trace.append("seeded split-brain \(key)")
            return payload
        }
        func localSession(_ id: UUID, content: String, deleted: Bool) -> WorkoutSession {
            let session = WorkoutSession(
                id: id, title: content, startedAt: Date(timeIntervalSince1970: created),
                endedAt: Date(timeIntervalSince1970: created + 60), durationSeconds: 60, status: .completed,
                source: .blank, createdAt: Date(timeIntervalSince1970: created),
                updatedAt: Date(timeIntervalSince1970: deleted ? created + 1 : created), syncOwnerTokenIdentifier: simOwner
            )
            // Deleted here; the older server bounced the stale tombstone.
            session.deletedAt = deleted ? Date(timeIntervalSince1970: created + 1) : nil
            return session
        }
        let shared = UUID()
        let private0 = UUID()
        let exerciseID = UUID()
        _ = try seedSession(shared, content: "seed-v0|seed-w0")
        _ = try seedSession(private0, content: "seed-v1|seed-w1")
        let exercisePayload = ExerciseSyncPayload(
            clientId: exerciseID.uuidString.lowercased(), createdAt: created, updatedAt: created, deletedAt: nil,
            seedIdentifier: nil, name: "seed-v2|seed-w2", categoryRaw: "strength", equipmentRaw: "barbell",
            primaryMuscleRaw: "Chest", primaryMuscleGroupRaw: "chest", notes: "", isArchived: false, isSeeded: false
        )
        _ = try server.upsert(.exercise(exercisePayload))
        let exerciseKey = simKey(.exercise, exerciseID.uuidString.lowercased())
        log.noteCreate(exerciseKey, parentKey: nil, value: "seed-v2")
        log.deleted.insert(exerciseKey)
        log.trace.append("seeded split-brain \(exerciseKey)")

        for (index, device) in devices.enumerated() {
            device.context.insert(localSession(shared, content: "seed-v0|seed-w0", deleted: index == 0))
            if index == 0 {
                device.context.insert(localSession(private0, content: "seed-v1|seed-w1", deleted: true))
                device.context.insert(Exercise(
                    id: exerciseID, name: "seed-v2|seed-w2", category: .strength, equipment: .barbell,
                    primaryMuscle: "Chest", syncOwnerTokenIdentifier: simOwner,
                    createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: created + 1),
                    deletedAt: Date(timeIntervalSince1970: created + 1)
                ))
            }
            // An installed build that synced everything before updating.
            let state = try SyncCursorState.state(for: simOwner, context: device.context)
            state.hasBootstrappedSettingsExercises = true
            state.hasBootstrappedWorkoutGraph = true
            state.workoutSessionsCursor = server.allRows.filter { $0.kind == .workoutSession }.map(\.serverUpdatedAt).max() ?? 0
            state.exercisesCursor = server.allRows.filter { $0.kind == .exercise }.map(\.serverUpdatedAt).max() ?? 0
            try device.context.save()
        }
    }

    // MARK: Oracle

    private func serverVisible() -> [String: String] {
        var visible: [String: String] = [:]
        func isLive(_ kind: SyncEntityKind, _ id: String?) -> Bool {
            guard let id, let row = server.row(kind, id), row.deletedAt == nil else { return false }
            switch kind {
            case .loggedExercise: return isLive(.workoutSession, row.payload.parentID)
            case .loggedSet: return isLive(.loggedExercise, row.payload.parentID)
            default: return true
            }
        }
        for row in server.allRows where isLive(row.kind, row.clientId) {
            visible[simKey(row.kind, row.clientId)] =
                "\(row.payload.content)|parent=\(row.payload.parentID ?? "nil")|exercise=\(row.payload.exerciseID ?? "nil")"
        }
        return visible
    }

    /// A poisoned record, or one that depends on it: a record under it, or a
    /// logged exercise naming it, which waits for it by design.
    private func isPoisonRelated(_ key: String) -> Bool {
        var current: String? = key
        while let key = current {
            let id = String(key[key.index(after: key.firstIndex(of: ":")!)...])
            if server.poisonIDs.contains(id) { return true }
            if let exerciseKey = log.exerciseReferences[key], isPoisonRelated(exerciseKey) { return true }
            current = log.created[key] ?? nil
        }
        return false
    }

    func check() -> [String] {
        var failures: [String] = []
        let expected = serverVisible()

        for device in devices {
            let actual = device.visible()
            var diff: [String] = []
            for (key, value) in expected.sorted(by: { $0.key < $1.key }) where !isPoisonRelated(key) && actual[key] != value {
                diff.append("\(key): device=\(actual[key] ?? "absent") server=\(value)")
            }
            for (key, value) in actual.sorted(by: { $0.key < $1.key }) where !isPoisonRelated(key) && expected[key] == nil {
                diff.append("\(key): device=\(value) server=absent")
            }
            if !diff.isEmpty {
                failures.append("I1 \(device.name) diverges from the server: \(diff.prefix(6).joined(separator: "; "))")
            }
        }

        for device in devices {
            let entries = device.activeEntries()
            // Records under a poisoned parent wait for it, by design.
            let stuck = entries.filter { entry in
                guard let kind = entry.entityKind else { return true }
                return !isPoisonRelated(simKey(kind, entry.entityID.uuidString.lowercased()))
            }
            if !stuck.isEmpty {
                failures.append("I2 \(device.name) outbox not drained: \(device.outboxSummary().prefix(6).joined(separator: "; "))")
            }
            for entry in entries where server.poisonIDs.contains(entry.entityID.uuidString.lowercased()) {
                if entry.status != .failed && entry.status != .blocked {
                    failures.append("I5 \(device.name) poison entry is \(entry.statusRaw), expected failed or blocked")
                }
            }
        }

        // A tombstoned parent never has a live child on the server.
        for row in server.allRows where row.deletedAt == nil {
            let parentKind: SyncEntityKind? = switch row.kind {
            case .loggedExercise: .workoutSession
            case .loggedSet: .loggedExercise
            default: nil
            }
            if let parentKind, let parentID = row.payload.parentID,
               let parent = server.row(parentKind, parentID), parent.deletedAt != nil {
                failures.append("S live \(simKey(row.kind, row.clientId)) under tombstoned \(simKey(parentKind, parentID))")
            }
        }

        for key in log.created.keys.sorted() where !isPoisonRelated(key) {
            let deleted = log.isDeletedByPolicy(key)
            let visible = expected[key] != nil
            if deleted && visible { failures.append("I4 resurrected: \(key) was deleted but is visible") }
            if !deleted && !visible { failures.append("I4 lost: \(key) was created, never deleted, and is not visible") }
        }
        for (key, snapshot) in expected.sorted(by: { $0.key < $1.key }) where !isPoisonRelated(key) {
            let parts = snapshot.split(separator: "|", omittingEmptySubsequences: false)
            let value = String(parts[0])
            let tag = parts.count > 1 ? String(parts[1]) : ""
            if !(log.writtenValues[key]?.contains(value) ?? false) {
                failures.append("I4 invented value \(value) for \(key)")
            }
            if log.superseded[key]?.contains(tag) ?? false {
                failures.append("I4 causally superseded write \(tag) (\(value)) survived for \(key)")
            }
        }
        return failures
    }

    /// I3: every device can edit any live record, then delete a workout.
    func checkEditability() async throws -> [String] {
        var failures: [String] = []
        for editor in devices {
            let candidates = editor.visibleRecords().filter { !isPoisonRelated($0.key) }
            guard !candidates.isEmpty else { continue }
            let record = candidates[rng.int(candidates.count)]
            time += 1
            let value = editor.edit(record)
            _ = try await quiesce()
            for device in devices {
                let seen = device.visible()[record.key]
                if seen == nil || !seen!.hasPrefix("\(value)|") {
                    failures.append("I3 edit of \(record.key) by \(editor.name) not visible on \(device.name) (sees \(seen ?? "nil"))")
                }
            }
        }
        for deleter in devices {
            let sessions = deleter.visibleRecords(.workoutSession).filter { !isPoisonRelated($0.key) }
            guard !sessions.isEmpty else { continue }
            let session = sessions[rng.int(sessions.count)]
            time += 1
            deleter.delete(session)
            _ = try await quiesce()
            for device in devices where device.visible()[session.key] != nil {
                failures.append("I3 delete of \(session.key) by \(deleter.name) did not reach \(device.name)")
            }
        }
        return failures
    }
}
