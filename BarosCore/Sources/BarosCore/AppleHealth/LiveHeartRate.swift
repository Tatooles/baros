import Foundation

/// The latest heart rate from the session recording an Active Workout: an iPhone session fed by
/// AirPods Pro 3, Powerbeats Pro 2, or a Bluetooth strap, or (later) the Baros Watch app.
public struct LiveHeartRate: Equatable, Sendable {
    /// Readings older than this are hidden, so a disconnected sensor doesn't leave a stale number.
    public static let freshness: TimeInterval = 30

    public let beatsPerMinute: Int
    public let measuredAt: Date

    public init(beatsPerMinute: Int, measuredAt: Date) {
        self.beatsPerMinute = beatsPerMinute
        self.measuredAt = measuredAt
    }

    /// The value to show at `now`, or `nil` to show nothing. Baros never shows an empty heart-rate slot.
    public func displayedBeatsPerMinute(at now: Date) -> Int? {
        let age = now.timeIntervalSince(measuredAt)
        guard beatsPerMinute > 0, age >= -1, age <= Self.freshness else { return nil }
        return beatsPerMinute
    }
}
