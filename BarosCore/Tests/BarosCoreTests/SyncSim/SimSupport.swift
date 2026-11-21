import Foundation

/// Seeded PRNG (mulberry32), as in `convex/syncSim/rng.sim.ts`.
struct SimRng {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed == 0 ? 0x9E37_79B9 : seed
    }

    mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    mutating func int(_ maxExclusive: Int) -> Int {
        Int(next() * Double(maxExclusive))
    }

    mutating func real(_ min: Double, _ max: Double) -> Double {
        min + next() * (max - min)
    }

    mutating func chance(_ probability: Double) -> Bool {
        next() < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        precondition(!items.isEmpty, "pick from an empty list")
        return items[int(items.count)]
    }

    mutating func weighted(_ weights: [(String, Double)]) -> String {
        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = next() * total
        for (key, weight) in weights {
            roll -= weight
            if roll < 0 { return key }
        }
        return weights[weights.count - 1].0
    }
}

/// Pauses a device's sync run at each network call, so a seeded scheduler can
/// interleave devices one step at a time. Everything runs on the main actor.
@MainActor
final class SimGate {
    private var parked: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    /// Called by the run: wait here until the scheduler steps it.
    func park() async {
        await withCheckedContinuation { continuation in
            parked = continuation
            wake()
        }
    }

    /// Called by the scheduler: let the run go on to its next pause or its end.
    func step() async {
        guard let parked else { return }
        self.parked = nil
        await withCheckedContinuation { continuation in
            waiter = continuation
            parked.resume()
        }
    }

    /// Starts a run and waits for its first pause or its end.
    func start(_ body: @escaping @MainActor () async -> Void) async -> Task<Void, Never> {
        var task: Task<Void, Never>!
        await withCheckedContinuation { continuation in
            waiter = continuation
            task = Task { @MainActor in
                await body()
                self.wake()
            }
        }
        return task
    }

    private func wake() {
        let waiter = waiter
        self.waiter = nil
        waiter?.resume()
    }
}

/// Moves a value across an isolation boundary inside the single-threaded simulator.
struct SimUnchecked<Value>: @unchecked Sendable {
    let value: Value
}
