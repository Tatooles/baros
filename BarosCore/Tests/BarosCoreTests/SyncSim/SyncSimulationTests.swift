import Foundation
import XCTest

/// Randomized multi-device convergence with the app's real sync coordinator,
/// the Swift twin of `convex/syncConvergence.test.ts`.
///
/// `SYNC_SIM_RUNS=<n>` sets how many seeds each fleet runs (default below);
/// `SYNC_SIM_SEED=<n>` replays one seed for every fleet.
@MainActor
final class SyncSimulationTests: XCTestCase {
    private struct Shape {
        let name: String
        let clocks: [SimClockProfile]
        var poison = false
        var dropResponseRate = 0.08
        var offlineRate = 0.4
        var seedsSplitBrain = false
    }

    private static let shapes: [Shape] = [
        Shape(name: "honest clocks", clocks: [.honest, .jitter, .honest]),
        Shape(name: "hostile clocks", clocks: [.farFuture, .deadClock, .jumpy, .slow]),
        Shape(name: "poison entry", clocks: [.honest, .fast, .slow], poison: true),
        Shape(name: "lost responses with fast clocks", clocks: [.farFuture, .fast, .honest, .jumpy], dropResponseRate: 0.35, offlineRate: 1.2),
        Shape(name: "healing an older server's split brain", clocks: [.honest, .fast, .slow], seedsSplitBrain: true),
    ]

    private static var runsPerFleet: Int {
        Int(ProcessInfo.processInfo.environment["SYNC_SIM_RUNS"] ?? "") ?? 6
    }

    private static var replaySeed: UInt32? {
        ProcessInfo.processInfo.environment["SYNC_SIM_SEED"].flatMap { UInt32($0) }
    }

    func testHonestClocks() async throws { try await run(Self.shapes[0], fleetIndex: 0) }
    func testHostileClocks() async throws { try await run(Self.shapes[1], fleetIndex: 1) }
    func testPoisonEntry() async throws { try await run(Self.shapes[2], fleetIndex: 2) }
    func testLostResponsesWithFastClocks() async throws { try await run(Self.shapes[3], fleetIndex: 3) }
    func testHealingSplitBrain() async throws { try await run(Self.shapes[4], fleetIndex: 4) }

    private func run(_ shape: Shape, fleetIndex: Int) async throws {
        let seeds: [UInt32] = Self.replaySeed.map { [$0] }
            ?? (0 ..< Self.runsPerFleet).map { UInt32(1000 * (fleetIndex + 1) + $0) }
        var failing: [String] = []
        for seed in seeds {
            let fleet = try SimFleet(config: SimFleetConfig(
                seed: seed,
                clocks: shape.clocks,
                dropResponseRate: shape.dropResponseRate,
                offlineRate: shape.offlineRate,
                poison: shape.poison,
                seedsSplitBrain: shape.seedsSplitBrain
            ))
            let report = try await fleet.run()
            if ProcessInfo.processInfo.environment["SYNC_SIM_VERBOSE"] != nil {
                print("sim \(shape.name) seed \(seed): \(report.records) records, \(report.serverWrites) server writes, \(report.visibleOnServer) visible, \(report.failures.count) failures")
            }
            if !report.failures.isEmpty {
                failing.append(describe(shape, report))
                if failing.count >= 2 { break }
            }
        }
        XCTAssertTrue(failing.isEmpty, failing.joined(separator: "\n\n"))
    }

    private func describe(_ shape: Shape, _ report: SimFleetReport) -> String {
        let ids = Set(report.failures.flatMap { failure in
            failure.split(whereSeparator: { " :;()".contains($0) }).filter { $0.count == 36 && $0.contains("-") }.map(String.init)
        })
        let trace = report.trace.filter { line in ids.contains { line.contains($0) } }
        return ([
            "Sync simulation failed for fleet \"\(shape.name)\", seed \(report.seed).",
            "Replay: SYNC_SIM_SEED=\(report.seed) swift test --package-path BarosCore --filter SyncSimulationTests",
        ] + report.failures.prefix(10) + ["Operations on the failing records:"] + (trace.isEmpty ? report.trace : trace).suffix(40))
            .joined(separator: "\n")
    }
}
