import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import schema from "./schema";
import {
  runFleet,
  type ClientRule,
  type ClockProfile,
  type ConvexHarness,
  type FleetConfig,
  type FleetReport,
} from "./syncSim/fleet.sim";

declare global {
  interface ImportMeta {
    glob(pattern: string): Record<string, () => Promise<any>>;
  }
}

const modules = import.meta.glob("./**/*.{ts,js}");

// SYNC_SIM_SEED=<n> replays one seed for every fleet; SYNC_SIM_RUNS=<n> sets
// how many seeds each fleet runs (default below).
const simulationEnv = process.env as Record<string, string | undefined>;
const replaySeed =
  simulationEnv.SYNC_SIM_SEED === undefined ? undefined : Number(simulationEnv.SYNC_SIM_SEED);
const runsPerFleet = Number(simulationEnv.SYNC_SIM_RUNS ?? 25);

type FleetShape = {
  name: string;
  devices: { rule: ClientRule; clock: ClockProfile }[];
  poison?: boolean;
  dropResponseRate?: number;
  offlineRate?: number;
};

const fleets: FleetShape[] = [
  {
    name: "current builds, honest clocks",
    devices: [
      { rule: "current", clock: "honest" },
      { rule: "current", clock: "jitter" },
      { rule: "current", clock: "honest" },
    ],
  },
  {
    name: "current builds, hostile clocks",
    devices: [
      { rule: "current", clock: "farFuture" },
      { rule: "current", clock: "deadClock" },
      { rule: "current", clock: "jumpy" },
      { rule: "current", clock: "slow" },
    ],
  },
  {
    name: "installed builds only",
    devices: [
      { rule: "legacy", clock: "honest" },
      { rule: "legacy", clock: "jitter" },
      { rule: "legacy", clock: "fast" },
    ],
  },
  {
    name: "mixed fleet, hostile clocks",
    devices: [
      { rule: "legacy", clock: "farFuture" },
      { rule: "current", clock: "honest" },
      { rule: "legacy", clock: "slow" },
      { rule: "current", clock: "jumpy" },
    ],
  },
  {
    name: "current builds with a poison entry",
    devices: [
      { rule: "current", clock: "honest" },
      { rule: "current", clock: "fast" },
      { rule: "current", clock: "slow" },
    ],
    poison: true,
  },
  {
    // Lost responses make devices retry uploads the server already applied,
    // while fast clocks make those retries look newer than they are.
    name: "lost responses with fast clocks",
    devices: [
      { rule: "current", clock: "farFuture" },
      { rule: "current", clock: "fast" },
      { rule: "current", clock: "honest" },
      { rule: "legacy", clock: "fast" },
      { rule: "current", clock: "jumpy" },
    ],
    dropResponseRate: 0.35,
    offlineRate: 1.2,
  },
];

function seedsFor(fleetIndex: number): number[] {
  if (replaySeed !== undefined) return [replaySeed];
  return Array.from({ length: runsPerFleet }, (_, run) => 1000 * (fleetIndex + 1) + run);
}

function describeFailure(shape: FleetShape, report: FleetReport): string {
  return [
    `Sync simulation failed for fleet "${shape.name}", seed ${report.seed}.`,
    `Replay: SYNC_SIM_SEED=${report.seed} pnpm vitest run convex/syncConvergence.test.ts -t "${shape.name}"`,
    ...report.failures.slice(0, 12),
    "Operations on the failing records:",
    ...relevantTrace(report).slice(-40),
  ].join("\n");
}

function relevantTrace(report: FleetReport): string[] {
  const ids = new Set(
    report.failures.flatMap((failure) => failure.match(/d\d[LC]-[a-z]+\d+/g) ?? []),
  );
  const lines = report.trace.filter((line) => [...ids].some((id) => line.includes(id)));
  return lines.length > 0 ? lines : report.trace.slice(-25);
}

describe("randomized multi-device sync convergence", () => {
  fleets.forEach((shape, fleetIndex) => {
    test(shape.name, async () => {
      const failing: string[] = [];
      for (const seed of seedsFor(fleetIndex)) {
        const config: FleetConfig = {
          seed,
          devices: shape.devices,
          steps: 220,
          dropRequestRate: 0.08,
          dropResponseRate: shape.dropResponseRate ?? 0.08,
          offlineRate: shape.offlineRate ?? 0.4,
          poison: shape.poison,
        };
        const report = await runFleet(convexTest(schema, modules) as unknown as ConvexHarness, config);
        if (report.failures.length > 0) {
          failing.push(describeFailure(shape, report));
          if (failing.length >= 3) break;
        }
      }
      expect(failing, failing.join("\n\n")).toEqual([]);
    }, 120_000);
  });
});
