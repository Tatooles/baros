import Foundation

/// What this device knows about one workout's Apple Health copy (ADR 0005, "The ledger").
public struct AppleHealthLedgerEntry: Codable, Equatable, Sendable {
    public enum Writer: String, Codable, Sendable {
        /// Started on this device, but no writer has been chosen yet.
        case undecided
        case iPhone
        /// Never saved to Health, for example after write permission was revoked.
        case none
    }

    public enum Phase: String, Codable, Sendable {
        /// Seen active on this device. Nothing was started.
        case observed
        /// A live session is recording.
        case recording
        /// The live session ended early. The fallback saves the workout at finish.
        case sessionLost
        /// A Health copy was saved. Later date or duration edits replace it; a tombstone deletes it.
        case saved
        /// The Baros workout was deleted and its Health copy was confirmed to exist; the delete may not
        /// have finished. A retry that finds nothing means Baros already deleted it.
        case deletingWithWorkout
        /// The Baros workout was deleted, so Baros deleted its Health copy. If the delete is reverted,
        /// the workout is saved again.
        case deletedWithWorkout
        /// Terminal: the person deleted the Health copy in the Health app. It is never restored.
        case removedInHealth
        /// Terminal: this workout never gets a Health copy from this device.
        case abandoned
    }

    public let workoutID: UUID
    public var writer: Writer
    public var phase: Phase
    public var sessionStartedAt: Date?
    public var lastWrittenVersion: Int64?
    public var lastWrittenStart: Date?
    public var lastWrittenEnd: Date?
    /// A save completed on this device, so a later missing copy means the person deleted it in Health.
    public var isSaveConfirmed: Bool

    public init(
        workoutID: UUID,
        writer: Writer = .undecided,
        phase: Phase = .observed,
        sessionStartedAt: Date? = nil,
        lastWrittenVersion: Int64? = nil,
        lastWrittenStart: Date? = nil,
        lastWrittenEnd: Date? = nil,
        isSaveConfirmed: Bool = false
    ) {
        self.workoutID = workoutID
        self.writer = writer
        self.phase = phase
        self.sessionStartedAt = sessionStartedAt
        self.lastWrittenVersion = lastWrittenVersion
        self.lastWrittenStart = lastWrittenStart
        self.lastWrittenEnd = lastWrittenEnd
        self.isSaveConfirmed = isSaveConfirmed
    }

    var isTerminal: Bool {
        phase == .removedInHealth || phase == .abandoned
    }
}

/// Device-local storage for the ledger. It is never a SwiftData model and never syncs (ADR 0005).
@MainActor
public final class AppleHealthLedgerStore {
    public nonisolated static let standardKey = "Baros.AppleHealth.ledger"

    private let defaults: UserDefaults
    private let key: String
    private var cache: [UUID: AppleHealthLedgerEntry]

    public init(defaults: UserDefaults = .standard, key: String = AppleHealthLedgerStore.standardKey) {
        self.defaults = defaults
        self.key = key
        cache = Self.load(from: defaults, key: key)
    }

    public var entries: [UUID: AppleHealthLedgerEntry] {
        cache
    }

    public func entry(for workoutID: UUID) -> AppleHealthLedgerEntry? {
        cache[workoutID]
    }

    public func save(_ entry: AppleHealthLedgerEntry) {
        guard cache[entry.workoutID] != entry else { return }
        cache[entry.workoutID] = entry
        persist()
    }

    public func removeAll() {
        cache = [:]
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        let stored = cache.values.sorted { $0.workoutID.uuidString < $1.workoutID.uuidString }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [UUID: AppleHealthLedgerEntry] {
        guard
            let data = defaults.data(forKey: key),
            let stored = try? JSONDecoder().decode([AppleHealthLedgerEntry].self, from: data)
        else { return [:] }
        return Dictionary(stored.map { ($0.workoutID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
