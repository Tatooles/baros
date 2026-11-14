import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import {
  runFleet,
  type ClientRule,
  type ClockProfile,
  type ConvexHarness,
  type Fleet,
  type FleetHooks,
} from "./syncSim/fleet.sim";
import {
  seedFutureStampedExercise,
  seedOrphanedLiveSet,
  seedResurrectedWorkout,
} from "./syncSim/damage.sim";

declare global {
  interface ImportMeta {
    glob(pattern: string): Record<string, () => Promise<any>>;
  }
}

const modules = import.meta.glob("./**/*.{ts,js}");

const owner = {
  subject: "user_a",
  issuer: "https://glad-krill-22.clerk.accounts.dev",
  tokenIdentifier: "https://glad-krill-22.clerk.accounts.dev|user_a",
};
const now = Date.UTC(2026, 2, 1) / 1000;
const day = 24 * 60 * 60;
const ms = (seconds: number) => Math.round(seconds * 1000);

type Summary = {
  runId: string;
  scannedRows: number;
  affectedOwners: number;
  byKind: Record<string, { found: number; repairable: number; repaired: number; changedRows: number }>;
  sample: { kind: string; tableName: string; rowId: string; clientId: string; repairable: boolean }[];
};

const base = { ownerTokenIdentifier: owner.tokenIdentifier, createdAt: now - 3 * day };

function sessionRow(clientId: string, fields: { updatedAt: number; deletedAt: number | null; serverUpdatedAt: number }) {
  return {
    ...base,
    ...fields,
    clientId,
    title: "Push Day",
    startedAt: now - 3 * day,
    endedAt: now - 3 * day + 3600,
    durationSeconds: 3600,
    notes: "",
    referenceNotes: null,
    statusRaw: "completed" as const,
    sourceRaw: "blank" as const,
    sourceSessionID: null,
    healthLinkID: null,
  };
}

function loggedExerciseRow(
  clientId: string,
  sessionClientId: string,
  fields: { updatedAt: number; deletedAt: number | null; serverUpdatedAt: number },
) {
  return {
    ...base,
    ...fields,
    clientId,
    sessionClientId,
    exerciseClientId: null,
    orderIndex: 0,
    exerciseSnapshotName: "Bench Press",
    exerciseSnapshotEquipmentRaw: "barbell",
    exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
    hasSnapshotMetadata: true,
    notes: "",
    referenceNotes: null,
  };
}

function setRow(
  clientId: string,
  loggedExerciseClientId: string,
  fields: { updatedAt: number; deletedAt: number | null; serverUpdatedAt: number },
) {
  return {
    ...base,
    ...fields,
    clientId,
    loggedExerciseClientId,
    orderIndex: 0,
    weight: 135,
    reps: 10,
    rpe: null,
    kindRaw: "working" as const,
    isCompleted: true,
    completedAt: now - 3 * day + 600,
    notes: "",
    healthLinkID: null,
  };
}

const t1 = now - 2 * day;
const t2 = t1 + 3600;

// One owner's data with one example of every damage kind, plus healthy rows
// that look similar and must not be touched.
async function seedDamage(t: ReturnType<typeof convexTest>) {
  await t.run(async (ctx) => {
    // Suspected resurrection: live workout, logged exercise deleted after it ended.
    await ctx.db.insert("workoutSessions", sessionRow("revived", { updatedAt: t2, deletedAt: null, serverUpdatedAt: ms(t2) }));
    await ctx.db.insert("loggedExercises", loggedExerciseRow("revived-le", "revived", { updatedAt: t1, deletedAt: t1, serverUpdatedAt: ms(t1) }));
    await ctx.db.insert("loggedSets", setRow("revived-set", "revived-le", { updatedAt: t1, deletedAt: t1, serverUpdatedAt: ms(t1) + 1 }));

    // Healthy: a discarded workout with no end time and an exercise removed
    // after it started. Only finished workouts have a fixed exercise list.
    await ctx.db.insert("workoutSessions", {
      ...sessionRow("discarded", { updatedAt: t2, deletedAt: null, serverUpdatedAt: ms(t2) + 1 }),
      statusRaw: "discarded",
      endedAt: null,
    });
    await ctx.db.insert("loggedExercises", loggedExerciseRow("swapped", "discarded", {
      updatedAt: t1,
      deletedAt: t1,
      serverUpdatedAt: ms(t1) + 10,
    }));

    // Healthy: an exercise removed mid-workout, then the duration shortened,
    // so the removal is after the end. The other exercise is still live.
    await ctx.db.insert("workoutSessions", sessionRow("shortened", { updatedAt: t2, deletedAt: null, serverUpdatedAt: ms(t2) + 2 }));
    await ctx.db.insert("loggedExercises", loggedExerciseRow("removed-late", "shortened", {
      updatedAt: t1,
      deletedAt: t1,
      serverUpdatedAt: ms(t1) + 11,
    }));
    await ctx.db.insert("loggedExercises", loggedExerciseRow("kept", "shortened", {
      updatedAt: now - 3 * day,
      deletedAt: null,
      serverUpdatedAt: ms(now - 3 * day) + 2,
    }));

    // Healthy: a logged exercise removed during the workout, before it ended.
    await ctx.db.insert("workoutSessions", sessionRow("healthy", { updatedAt: now - 3 * day, deletedAt: null, serverUpdatedAt: ms(now - 3 * day) }));
    await ctx.db.insert("loggedExercises", loggedExerciseRow("removed-mid-workout", "healthy", {
      updatedAt: now - 3 * day + 60,
      deletedAt: now - 3 * day + 60,
      serverUpdatedAt: ms(now - 3 * day + 60) + 1,
    }));

    // Live set under a deleted workout and logged exercise.
    await ctx.db.insert("workoutSessions", sessionRow("deleted", { updatedAt: t1, deletedAt: t1, serverUpdatedAt: ms(t1) + 5 }));
    await ctx.db.insert("loggedExercises", loggedExerciseRow("deleted-le", "deleted", { updatedAt: t1, deletedAt: t1, serverUpdatedAt: ms(t1) + 4 }));
    await ctx.db.insert("loggedSets", setRow("orphan-set", "deleted-le", { updatedAt: t1 - 1, deletedAt: null, serverUpdatedAt: ms(t1) + 3 }));

    // Live logged exercise under a deleted workout.
    await ctx.db.insert("workoutSessions", sessionRow("deleted-2", { updatedAt: t1, deletedAt: t1, serverUpdatedAt: ms(t1) + 7 }));
    await ctx.db.insert("loggedExercises", loggedExerciseRow("orphan-le", "deleted-2", { updatedAt: t1 - 1, deletedAt: null, serverUpdatedAt: ms(t1) + 6 }));
    await ctx.db.insert("loggedSets", setRow("orphan-le-set", "orphan-le", { updatedAt: t1 - 1, deletedAt: null, serverUpdatedAt: ms(t1) + 8 }));

    // A set whose logged exercise does not exist.
    await ctx.db.insert("loggedSets", setRow("parentless-set", "missing-le", { updatedAt: t1, deletedAt: null, serverUpdatedAt: ms(t1) + 9 }));

    // #98: written by a clock a month fast.
    await ctx.db.insert("exercises", {
      ...base,
      clientId: "future-exercise",
      seedIdentifier: null,
      name: "Bench Press",
      categoryRaw: "strength",
      equipmentRaw: "barbell",
      primaryMuscleRaw: "Chest",
      primaryMuscleGroupRaw: "chest",
      notes: "",
      isArchived: false,
      isSeeded: false,
      updatedAt: t1 + 30 * day,
      deletedAt: null,
      serverUpdatedAt: ms(t1),
    });
  });
}

async function snapshot(t: ReturnType<typeof convexTest>) {
  return await t.run(async (ctx) => ({
    workoutSessions: await ctx.db.query("workoutSessions").collect(),
    loggedExercises: await ctx.db.query("loggedExercises").collect(),
    loggedSets: await ctx.db.query("loggedSets").collect(),
    exercises: await ctx.db.query("exercises").collect(),
    syncRepairLog: await ctx.db.query("syncRepairLog").collect(),
  }));
}

async function row(t: ReturnType<typeof convexTest>, table: "workoutSessions" | "loggedExercises" | "loggedSets" | "exercises", clientId: string) {
  return await t.run(async (ctx) =>
    (await ctx.db.query(table).collect()).find((candidate) => candidate.clientId === clientId),
  );
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(now * 1000);
});

afterEach(() => {
  vi.useRealTimers();
});

describe("sync damage audit and repair", () => {
  test("a dry run finds every damage kind and writes nothing", async () => {
    const t = convexTest(schema, modules);
    await seedDamage(t);
    const before = await snapshot(t);

    const summary = (await t.action(internal.syncRepair.runSyncDamageRepair, {})) as Summary;

    expect(await snapshot(t)).toEqual(before);
    expect(summary.affectedOwners).toBe(1);
    expect(summary.byKind.suspectedResurrection).toMatchObject({ found: 1, repairable: 0, repaired: 0 });
    expect(summary.byKind.liveChildUnderDeletedParent).toMatchObject({ found: 3, repairable: 3, repaired: 0 });
    expect(summary.byKind.liveChildWithMissingParent).toMatchObject({ found: 1, repairable: 0 });
    expect(summary.byKind.futureTimestamp).toMatchObject({ found: 1, repairable: 0 });
    expect(summary.sample.map((finding) => finding.clientId)).not.toContain("healthy");
    expect(summary.sample.map((finding) => finding.clientId)).not.toContain("discarded");
    expect(summary.sample.map((finding) => finding.clientId)).not.toContain("shortened");
    expect(JSON.stringify(summary)).not.toContain(owner.tokenIdentifier);
  });

  test("applying deletes orphaned children and only reports the other kinds", async () => {
    const t = convexTest(schema, modules);
    await seedDamage(t);

    const summary = (await t.action(internal.syncRepair.runSyncDamageRepair, { dryRun: false })) as Summary;

    expect(summary.byKind.liveChildUnderDeletedParent.repaired).toBeGreaterThanOrEqual(2);
    expect(summary.byKind.suspectedResurrection).toMatchObject({ found: 1, repairable: 0, repaired: 0 });
    expect((await row(t, "loggedSets", "orphan-set"))!.deletedAt).toBe(t1);
    expect((await row(t, "loggedExercises", "orphan-le"))!.deletedAt).toBe(t1);
    expect((await row(t, "loggedSets", "orphan-le-set"))!.deletedAt).toBe(t1);
    expect((await row(t, "workoutSessions", "revived"))!.deletedAt).toBeNull();
    // Report-only kinds keep their rows exactly as they were.
    expect((await row(t, "loggedSets", "parentless-set"))!.deletedAt).toBeNull();
    expect((await row(t, "exercises", "future-exercise"))!.updatedAt).toBe(t1 + 30 * day);
  });

  test("the repair is idempotent and logs every row it changed", async () => {
    const t = convexTest(schema, modules);
    await seedDamage(t);
    const options = { dryRun: false };

    const first = (await t.action(internal.syncRepair.runSyncDamageRepair, options)) as Summary;
    const afterFirst = await snapshot(t);
    const second = (await t.action(internal.syncRepair.runSyncDamageRepair, options)) as Summary;

    for (const counts of Object.values(second.byKind)) {
      expect(counts.repaired).toBe(0);
    }
    expect(await snapshot(t)).toEqual(afterFirst);
    const log = (await t.query(internal.syncRepair.syncRepairLogForRun, { runId: first.runId })) as {
      clientId: string;
      before: { deletedAt: number | null };
      after: { deletedAt: number | null };
    }[];
    const changed = Object.values(first.byKind).reduce((total, counts) => total + counts.changedRows, 0);
    expect(log).toHaveLength(changed);
    expect(log.map((entry) => entry.clientId)).toEqual(expect.arrayContaining(["orphan-set", "orphan-le", "orphan-le-set"]));
    for (const entry of log) {
      expect(entry.before.deletedAt).toBeNull();
      expect(entry.after.deletedAt).not.toBeNull();
    }
  });

  test("a deleted workout keeps its content and can be restored as a copy every build downloads", async () => {
    const t = convexTest(schema, modules);
    await seedDamage(t);
    await t.action(internal.syncRepair.runSyncDamageRepair, { dryRun: false });
    const deleted = (await row(t, "workoutSessions", "deleted"))!;

    const dryRun = await t.mutation(internal.syncRepair.restoreWorkoutAsCopy, { sessionRowId: deleted._id });
    expect(dryRun).toMatchObject({ dryRun: true, loggedExercises: 1, sets: 1 });

    const restored = await t.mutation(internal.syncRepair.restoreWorkoutAsCopy, {
      sessionRowId: deleted._id,
      dryRun: false,
    });
    const changes = await t.withIdentity(owner).mutation(api.sync.fetchChangesOnce, {
      cursors: { userSettings: 0, exercises: 0, workoutSessions: ms(now) - 1, loggedExercises: ms(now) - 1, loggedSets: ms(now) - 1 },
    });
    const copies = {
      sessions: changes.workoutSessions.filter((candidate) => candidate.clientId === restored.newSessionClientId),
      loggedExercises: changes.loggedExercises.filter(
        (candidate) => candidate.sessionClientId === restored.newSessionClientId,
      ),
    };
    expect(copies.sessions).toEqual([expect.objectContaining({ deletedAt: null, title: "Push Day" })]);
    expect(copies.loggedExercises).toEqual([expect.objectContaining({ deletedAt: null })]);
    const copiedSets = changes.loggedSets.filter(
      (candidate) => candidate.loggedExerciseClientId === copies.loggedExercises[0].clientId,
    );
    expect(copiedSets).toEqual([expect.objectContaining({ deletedAt: null, weight: 135 })]);
  });

  test("restoring brings back children a fast clock deleted just before the workout", async () => {
    const t = convexTest(schema, modules);
    const client = t.withIdentity(owner);
    await t.run(async (ctx) => {
      await ctx.db.insert("workoutSessions", sessionRow("fast", { updatedAt: t1, deletedAt: null, serverUpdatedAt: ms(t1) }));
      await ctx.db.insert("loggedExercises", loggedExerciseRow("fast-le", "fast", { updatedAt: t1, deletedAt: null, serverUpdatedAt: ms(t1) + 1 }));
      await ctx.db.insert("loggedSets", setRow("fast-set", "fast-le", { updatedAt: t1, deletedAt: null, serverUpdatedAt: ms(t1) + 2 }));
      // Removed by a history edit days before the workout was deleted.
      await ctx.db.insert("loggedSets", setRow("removed-earlier", "fast-le", {
        updatedAt: t1 - 3 * day,
        deletedAt: t1 - 3 * day,
        serverUpdatedAt: ms(t1) + 3,
      }));
      // A logged exercise removed days before, with a set of its own.
      await ctx.db.insert("loggedExercises", loggedExerciseRow("removed-earlier-le", "fast", {
        updatedAt: t1 - 3 * day,
        deletedAt: t1 - 3 * day,
        serverUpdatedAt: ms(t1) + 4,
      }));
      await ctx.db.insert("loggedSets", setRow("removed-earlier-le-set", "removed-earlier-le", {
        updatedAt: t1 - 3 * day,
        deletedAt: t1 - 3 * day,
        serverUpdatedAt: ms(t1) + 5,
      }));
    });
    // A device an hour fast deletes the workout; its set, logged exercise and
    // workout tombstones arrive one after another and are capped at arrival.
    const deviceDeletedAt = now + 3600;
    const uploads = [
      ["loggedSets", "fast-set"],
      ["loggedExercises", "fast-le"],
      ["workoutSessions", "fast"],
    ] as const;
    for (const [index, [entityKind, clientId]] of uploads.entries()) {
      vi.setSystemTime((now + index) * 1000);
      await client.mutation(api.sync.tombstone, { entityKind, clientId, deletedAt: deviceDeletedAt });
    }
    const session = (await row(t, "workoutSessions", "fast"))!;
    expect((await row(t, "loggedSets", "fast-set"))!.deletedAt).toBeLessThan(session.deletedAt!);

    const byDefault = await t.mutation(internal.syncRepair.restoreWorkoutAsCopy, { sessionRowId: session._id });
    expect(byDefault).toMatchObject({ loggedExercises: 1, sets: 1, leftOut: { loggedExercises: 1, sets: 2 } });

    const wider = await t.mutation(internal.syncRepair.restoreWorkoutAsCopy, {
      sessionRowId: session._id,
      childrenDeletedSince: t1 - 4 * day,
    });
    expect(wider).toMatchObject({ loggedExercises: 2, sets: 3, leftOut: { loggedExercises: 0, sets: 0 } });
  });

  test("a restored copy starts with no conflict history from the original", async () => {
    const t = convexTest(schema, modules);
    await seedDamage(t);
    const deleted = (await row(t, "workoutSessions", "deleted"))!;
    // The original was last written by a current build a month fast.
    await t.run(async (ctx) => {
      await ctx.db.patch(deleted._id, { syncOrder: now + 30 * day });
    });
    const restored = await t.mutation(internal.syncRepair.restoreWorkoutAsCopy, {
      sessionRowId: deleted._id,
      dryRun: false,
    });
    const copy = (await row(t, "workoutSessions", restored.newSessionClientId!))!;
    const { _id, _creationTime, ownerTokenIdentifier, serverUpdatedAt, syncOrder, ...fields } = copy;

    // Two devices pull the copy; A edits, then B edits concurrently, later.
    const client = t.withIdentity(owner);
    vi.setSystemTime((now + 1) * 1000);
    const deviceA = await client.mutation(api.sync.upsertWorkoutSession, {
      record: { ...fields, title: "A", updatedAt: now + 1, baseUpdatedAt: copy.updatedAt },
    });
    vi.setSystemTime((now + 2) * 1000);
    const deviceB = await client.mutation(api.sync.upsertWorkoutSession, {
      record: { ...fields, title: "B", updatedAt: now + 2, baseUpdatedAt: copy.updatedAt },
    });

    expect(deviceA.status).toBe("updated");
    expect(deviceB.status).toBe("updated");
    expect((await row(t, "workoutSessions", restored.newSessionClientId!))!.title).toBe("B");
    void [_id, _creationTime, ownerTokenIdentifier, serverUpdatedAt, syncOrder];
  });

  test("restoring refuses a workout that is not deleted", async () => {
    const t = convexTest(schema, modules);
    await seedDamage(t);
    const healthy = (await row(t, "workoutSessions", "healthy"))!;
    await expect(
      t.mutation(internal.syncRepair.restoreWorkoutAsCopy, { sessionRowId: healthy._id, dryRun: false }),
    ).rejects.toThrow("That workout is not deleted.");
  });
});

// The same damage, on a fleet of devices with their local stores and outboxes.
describe("sync damage repair across devices", () => {
  type Shape = { rule: ClientRule; clock: ClockProfile }[];

  async function runScenario(
    devices: Shape,
    hooks: FleetHooks,
    options: { seed?: number; steps?: number; onFinish?: (fleet: Fleet) => void } = {},
  ) {
    return await runFleet(
      convexTest(schema, modules) as unknown as ConvexHarness,
      {
        seed: options.seed ?? 7,
        devices,
        steps: options.steps ?? 0,
        dropRequestRate: options.steps ? 0.08 : 0,
        dropResponseRate: options.steps ? 0.08 : 0,
        offlineRate: options.steps ? 0.4 : 0,
      },
      { hooks, onFinish: options.onFinish },
    );
  }

  // The production repair, run against the simulated server mid-run.
  const applyRepair = async (fleet: Fleet) => {
    await fleet.server.t.action(internal.syncRepair.runSyncDamageRepair, { dryRun: false });
  };

  const installedFleet: Shape = [
    { rule: "legacy", clock: "honest" },
    { rule: "legacy", clock: "jitter" },
    { rule: "current", clock: "honest" },
  ];
  const resurrection: FleetHooks["prepare"] = async (fleet) => {
    const [deleter, reviver, observer] = fleet.devices;
    await seedResurrectedWorkout(fleet, { deleter, reviver, observers: [observer] });
  };

  test("a revived workout stays split while the deleting device runs an installed build", async () => {
    const report = await runScenario(installedFleet, { prepare: resurrection });
    expect(report.failures.join("\n")).toMatch(/I1 d0L diverges/);
    expect(report.failures.join("\n")).toMatch(/I4 resurrected: workoutSessions:dmg-ws1/);
  });

  test("the reviving device's stuck set edit drains on the new server even before any repair", async () => {
    let reviverOutbox: string[] = ["not run"];
    await runScenario(installedFleet, { prepare: resurrection }, {
      onFinish: (fleet) => {
        reviverOutbox = fleet.devices[1].outboxSummary();
      },
    });
    expect(reviverOutbox).toEqual([]);
  });

  test("a deleting device on the current build heals a revived workout by itself", async () => {
    const report = await runScenario(
      [
        { rule: "current", clock: "honest" },
        { rule: "legacy", clock: "honest" },
        { rule: "legacy", clock: "jitter" },
      ],
      { prepare: resurrection, currentBuildsReassertDeletes: true },
    );
    expect(report.failures).toEqual([]);
  });

  test("a future-stamped record a current build deleted is deleted everywhere after it updates", async () => {
    const report = await runScenario(
      [
        { rule: "legacy", clock: "farFuture" },
        { rule: "current", clock: "honest" },
        { rule: "legacy", clock: "honest" },
      ],
      {
        prepare: async (fleet) => {
          const [fastDevice, deleter, observer] = fleet.devices;
          await seedFutureStampedExercise(fleet, { fastDevice, deleter, observers: [observer] });
        },
        currentBuildsReassertDeletes: true,
      },
    );
    expect(report.failures).toEqual([]);
  });

  test("a future-stamped record an installed build deleted stays split until that device updates", async () => {
    const report = await runScenario(
      [
        { rule: "legacy", clock: "farFuture" },
        { rule: "legacy", clock: "honest" },
      ],
      {
        prepare: async (fleet) => {
          const [fastDevice, deleter] = fleet.devices;
          await seedFutureStampedExercise(fleet, { fastDevice, deleter, observers: [] });
        },
        repair: applyRepair,
      },
    );
    // The server cannot tell this delete ever happened; only the device can.
    expect(report.failures.join("\n")).toMatch(/I1 d1L diverges/);
  });

  test("a live set left under a deleted workout is repaired without anyone noticing", async () => {
    const without = await runScenario(installedFleet, { prepare: seedOrphanedLiveSet });
    expect(without.failures.join("\n")).toMatch(/S live loggedSets:dmg-set3/);
    expect(without.failures.join("\n")).not.toMatch(/I1/);

    const repaired = await runScenario(installedFleet, {
      prepare: seedOrphanedLiveSet,
      repair: applyRepair,
    });
    expect(repaired.failures).toEqual([]);
  });

  test("repairing during live traffic from a mixed fleet converges", async () => {
    const failing: string[] = [];
    for (let seed = 1; seed <= 12; seed++) {
      const report = await runScenario(
        [
          { rule: "current", clock: "slow" },
          { rule: "legacy", clock: "fast" },
          { rule: "legacy", clock: "honest" },
          { rule: "current", clock: "jumpy" },
        ],
        {
          prepare: async (fleet) => {
            const [deleter, reviver, observer, other] = fleet.devices;
            await seedResurrectedWorkout(fleet, { deleter, reviver, observers: [observer, other] });
            await seedOrphanedLiveSet(fleet);
          },
          currentBuildsReassertDeletes: true,
          repair: applyRepair,
          repairAtStep: 90,
        },
        { seed, steps: 180 },
      );
      if (report.failures.length > 0) {
        failing.push(`seed ${seed}: ${report.failures.slice(0, 4).join("; ")}`);
      }
    }
    expect(failing).toEqual([]);
  }, 120_000);
});
