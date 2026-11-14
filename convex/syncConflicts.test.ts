import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import { decideUpsert, effectiveStoredTime } from "./sync/merge";

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

const zeroCursors = {
  userSettings: 0,
  exercises: 0,
  workoutSessions: 0,
  loggedExercises: 0,
  loggedSets: 0,
};

// Server time for every test: 2026-03-01T00:00:00Z, in seconds.
const now = Date.UTC(2026, 2, 1) / 1000;
const minute = 60;
const month = 30 * 24 * 60 * 60;

function exercise(updatedAt: number, overrides: Record<string, unknown> = {}) {
  return {
    clientId: "exercise-1",
    seedIdentifier: null,
    name: "Bench Press",
    categoryRaw: "strength",
    equipmentRaw: "barbell",
    primaryMuscleRaw: "Chest",
    primaryMuscleGroupRaw: "chest",
    notes: "",
    isArchived: false,
    isSeeded: false,
    createdAt: now - 3600,
    updatedAt,
    deletedAt: null,
    ...overrides,
  };
}

function session(updatedAt: number, overrides: Record<string, unknown> = {}) {
  return {
    clientId: "session-1",
    title: "Push Day",
    startedAt: now - 3600,
    endedAt: now - 1800,
    durationSeconds: 1800,
    notes: "",
    referenceNotes: null,
    statusRaw: "completed" as const,
    sourceRaw: "blank" as const,
    sourceSessionID: null,
    healthLinkID: null,
    createdAt: now - 3600,
    updatedAt,
    deletedAt: null,
    ...overrides,
  };
}

function loggedExercise(updatedAt: number, overrides: Record<string, unknown> = {}) {
  return {
    clientId: "logged-exercise-1",
    sessionClientId: "session-1",
    exerciseClientId: "exercise-1",
    orderIndex: 0,
    exerciseSnapshotName: "Bench Press",
    exerciseSnapshotEquipmentRaw: "barbell",
    exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
    hasSnapshotMetadata: true,
    notes: "",
    referenceNotes: null,
    sourceLoggedExerciseID: null,
    createdAt: now - 3600,
    updatedAt,
    deletedAt: null,
    ...overrides,
  };
}

function set(updatedAt: number, overrides: Record<string, unknown> = {}) {
  return {
    clientId: "logged-set-1",
    loggedExerciseClientId: "logged-exercise-1",
    orderIndex: 0,
    weight: 135,
    reps: 10,
    rpe: null,
    kindRaw: "working" as const,
    isCompleted: true,
    completedAt: now - 3000,
    notes: "",
    healthLinkID: null,
    sourceLoggedSetID: null,
    createdAt: now - 3600,
    updatedAt,
    deletedAt: null,
    ...overrides,
  };
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(now * 1000);
});

afterEach(() => {
  vi.useRealTimers();
});

async function seedWorkout(client: ReturnType<ReturnType<typeof convexTest>["withIdentity"]>) {
  const createdAt = now - 600;
  await client.mutation(api.sync.upsertExercise, { record: exercise(createdAt) });
  await client.mutation(api.sync.upsertWorkoutSession, { record: session(createdAt) });
  await client.mutation(api.sync.upsertLoggedExercise, { record: loggedExercise(createdAt) });
  await client.mutation(api.sync.upsertLoggedSet, { record: set(createdAt) });
}

// Installed builds adopt a pulled record only when its updatedAt is greater
// than their own copy's (SyncConflictResolver).
function legacyClientAdopts(local: { updatedAt: number }, pulled: { updatedAt: number }): boolean {
  return pulled.updatedAt > local.updatedAt;
}

describe("#97 delete versus edit", () => {
  test("a newer edit from another device cannot revive a deleted workout", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await seedWorkout(client);

    // Device A deletes the workout; device B, offline, edits it later.
    await client.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: now - 300,
    });
    const deviceBEdit = session(now - 60, { title: "Edited offline" });
    const result = await client.mutation(api.sync.upsertWorkoutSession, { record: deviceBEdit });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    const stored = changes.workoutSessions[0];
    expect(result.status).toBe("ignored_stale");
    expect(stored.deletedAt).toBe(now - 300);
    // Device B's edit is kept on the tombstone, so it stays recoverable.
    expect(stored.title).toBe("Edited offline");
    // And device B, running an installed build, adopts the delete.
    expect(legacyClientAdopts(deviceBEdit, stored)).toBe(true);
  });

  test("deleting a workout deletes its logged exercises and sets on the server", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await seedWorkout(client);

    await client.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: now - 300,
    });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(changes.loggedExercises[0].deletedAt).toBe(now - 300);
    expect(changes.loggedSets[0].deletedAt).toBe(now - 300);
    expect(changes.loggedSets[0].updatedAt).toBeGreaterThan(now - 600);
    // The exercise library is not part of the workout.
    expect(changes.exercises[0].deletedAt).toBeNull();
  });

  test("a set added offline to a deleted workout is kept as deleted instead of rejected forever", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await seedWorkout(client);
    await client.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: now - 300,
    });

    // Older servers threw here, which blocked the device's whole queue (#96).
    const result = await client.mutation(api.sync.upsertLoggedSet, {
      record: set(now - 60, { clientId: "logged-set-2", weight: 155 }),
    });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    const added = changes.loggedSets.find((row) => row.clientId === "logged-set-2");
    expect(result.status).toBe("ignored_stale");
    expect(added).toMatchObject({ deletedAt: now - 300, weight: 155 });
    expect(added!.updatedAt).toBeGreaterThan(now - 60);
  });

  test("a set added to a live workout still needs its logged exercise to exist", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await seedWorkout(client);

    await expect(
      client.mutation(api.sync.upsertLoggedSet, {
        record: set(now - 60, { clientId: "logged-set-2", loggedExerciseClientId: "missing" }),
      }),
    ).rejects.toThrow("Cannot upsert active logged set without its logged exercise parent.");
  });

  test("deleting a workout again deletes children an older server left live", async () => {
    const t = convexTest(schema, modules);
    const client = t.withIdentity(owner);
    await seedWorkout(client);
    // Old server: the workout tombstone did not cascade.
    await t.run(async (ctx) => {
      const sessionRow = await ctx.db.query("workoutSessions").unique();
      await ctx.db.patch(sessionRow!._id, { deletedAt: now - 300, updatedAt: now - 300 });
    });

    const result = await client.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: now - 200,
    });

    const children = await t.run(async (ctx) => ({
      loggedExercise: await ctx.db.query("loggedExercises").unique(),
      set: await ctx.db.query("loggedSets").unique(),
    }));
    expect(result.status).toBe("tombstoned");
    expect(children.loggedExercise!.deletedAt).toBe(now - 300);
    expect(children.set!.deletedAt).toBe(now - 300);
  });

  test("a delete the server receives before the record still wins when the record arrives", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // After a partial account wipe, one device deletes a workout the server
    // no longer has; then another device re-uploads it.
    const tombstoned = await client.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: now - 120,
    });
    const reupload = await client.mutation(api.sync.upsertWorkoutSession, {
      record: session(now - 600, { title: "Re-uploaded" }),
    });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(tombstoned).toMatchObject({ status: "tombstoned" });
    expect(reupload.status).toBe("ignored_stale");
    expect(changes.workoutSessions[0]).toMatchObject({ deletedAt: now - 120, title: "Re-uploaded" });
    expect(changes.workoutSessions[0].updatedAt).toBeGreaterThan(now - 600);
  });

  test("an idle installed build holding a fast clock's copy adopts a current build's delete of it", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // After a partial cloud wipe, device B still holds a copy stamped a month
    // ahead. A current build that saw it deletes it, stamping above it.
    const deviceBCopy = session(now + month);
    await client.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: now + month + 0.001,
    });
    const placeholder = (await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors }))
      .workoutSessions[0];
    expect(placeholder.deletedAt).toBe(now);
    expect(legacyClientAdopts(deviceBCopy, placeholder)).toBe(true);
  });

  test("an idle installed build adopts a delete the server received before the record", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // Device B still holds the workout from before a partial cloud wipe.
    const deviceBCopy = session(now - 600);
    await client.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: now - 120,
    });
    const placeholder = (await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors }))
      .workoutSessions[0];
    expect(placeholder.deletedAt).toBe(now - 120);
    expect(legacyClientAdopts(deviceBCopy, placeholder)).toBe(true);
  });

  test("a large workout's cascade reaches a client that pulls in small pages", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await seedWorkout(client);
    for (let index = 2; index <= 30; index++) {
      await client.mutation(api.sync.upsertLoggedSet, {
        record: set(now - 600, { clientId: `logged-set-${index}`, orderIndex: index }),
      });
    }
    await client.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: now - 300,
    });

    const seen = new Map<string, number | null>();
    let cursors = { ...zeroCursors };
    for (let page = 0; page < 40; page++) {
      const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors, limit: 4 });
      for (const row of changes.loggedSets) seen.set(row.clientId, row.deletedAt);
      cursors = { ...cursors, ...changes.cursors };
      if (!Object.values(changes.hasMore).some(Boolean)) break;
    }
    expect(seen.size).toBe(30);
    expect([...seen.values()].every((deletedAt) => deletedAt === now - 300)).toBe(true);
  });

  test("rejections carry a stable code", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await seedWorkout(client);
    await expect(
      client.mutation(api.sync.upsertLoggedSet, {
        record: set(now - 60, { clientId: "logged-set-2", loggedExerciseClientId: "missing" }),
      }),
    ).rejects.toMatchObject({ data: { code: "missingParent" } });
  });

  test("an upload of an older deleted copy does not change a tombstone", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await seedWorkout(client);
    const tombstoned = await client.mutation(api.sync.tombstone, {
      entityKind: "loggedSets",
      clientId: "logged-set-1",
      deletedAt: now - 300,
    });

    const result = await client.mutation(api.sync.upsertLoggedSet, {
      record: set(now - 400, { deletedAt: now - 400 }),
    });
    expect(result).toMatchObject({ status: "ignored_stale", serverUpdatedAt: (tombstoned as { serverUpdatedAt: number }).serverUpdatedAt });
  });
});

describe("#98 client clocks", () => {
  test("a record stamped a month ahead can still be edited from a correct clock", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // Device A's clock is a month fast.
    const deviceAWrite = exercise(now + month, { name: "Bench" });
    await client.mutation(api.sync.upsertExercise, { record: deviceAWrite });

    vi.setSystemTime((now + minute) * 1000);
    const result = await client.mutation(api.sync.upsertExercise, {
      record: exercise(now + minute, { name: "Bench Press" }),
    });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(result.status).toBe("updated");
    expect(changes.exercises[0].name).toBe("Bench Press");
    // Device A, running an installed build, adopts the edit too.
    expect(legacyClientAdopts(deviceAWrite, changes.exercises[0])).toBe(true);
  });

  test("a record stamped a month ahead can still be deleted from a correct clock", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await client.mutation(api.sync.upsertExercise, { record: exercise(now + month) });

    vi.setSystemTime((now + minute) * 1000);
    const result = await client.mutation(api.sync.tombstone, {
      entityKind: "exercises",
      clientId: "exercise-1",
      deletedAt: now + minute,
    });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(result.status).toBe("tombstoned");
    expect(changes.exercises[0].deletedAt).toBe(now + minute);
    expect(changes.exercises[0].updatedAt).toBeGreaterThan(now + month);
  });

  test("rows already stored with future timestamps are judged by when they were written", async () => {
    const t = convexTest(schema, modules);
    // Written by an older server, which stored the fast clock as is.
    await t.run(async (ctx) => {
      await ctx.db.insert("exercises", {
        ...exercise(now + month, { name: "Bench" }),
        primaryMuscleGroupRaw: "chest",
        ownerTokenIdentifier: owner.tokenIdentifier,
        serverUpdatedAt: (now - 3600) * 1000,
      });
    });

    const result = await t.withIdentity(owner).mutation(api.sync.upsertExercise, {
      record: exercise(now - 60, { name: "Bench Press" }),
    });
    expect(result.status).toBe("updated");
  });

  test("a fast clock still loses to an edit that reached the server later", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // Device A runs five minutes fast; device B is correct and edits 1 s later.
    await client.mutation(api.sync.upsertExercise, { record: exercise(now + 5 * minute, { name: "A" }) });
    vi.setSystemTime((now + 1) * 1000);
    const result = await client.mutation(api.sync.upsertExercise, { record: exercise(now + 1, { name: "B" }) });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(result.status).toBe("updated");
    expect(changes.exercises[0].name).toBe("B");
  });

  test("an honest older edit still loses to a newer one", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await client.mutation(api.sync.upsertExercise, { record: exercise(now - 60, { name: "Newer" }) });
    const result = await client.mutation(api.sync.upsertExercise, {
      record: exercise(now - 120, { name: "Older offline edit" }),
    });
    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(result.status).toBe("ignored_stale");
    expect(changes.exercises[0].name).toBe("Newer");
  });

  test("after a fast clock's write, a later edit and then a delete both reach that device", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // The fast device runs an installed build and keeps its own copy.
    const fastDeviceCopy = exercise(now + month, { name: "Bench" });
    await client.mutation(api.sync.upsertExercise, { record: fastDeviceCopy });

    vi.setSystemTime((now + minute) * 1000);
    await client.mutation(api.sync.upsertExercise, { record: exercise(now + minute, { name: "Bench Press" }) });
    const afterEdit = (await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors })).exercises[0];
    expect(legacyClientAdopts(fastDeviceCopy, afterEdit)).toBe(true);

    vi.setSystemTime((now + 2 * minute) * 1000);
    await client.mutation(api.sync.tombstone, {
      entityKind: "exercises",
      clientId: "exercise-1",
      deletedAt: now + 2 * minute,
    });
    const afterDelete = (await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors })).exercises[0];
    expect(afterDelete.deletedAt).toBe(now + 2 * minute);
    expect(legacyClientAdopts(afterEdit, afterDelete)).toBe(true);
  });

  test("a retry of an upload the server ignored is still ignored when it arrives later", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // Two fast clocks write in the same server millisecond; the smaller
    // timestamp loses, and its device never hears back.
    await client.mutation(api.sync.upsertExercise, { record: exercise(now + 2000, { name: "Winner" }) });
    const loser = exercise(now + 1000, { name: "Loser" });
    expect((await client.mutation(api.sync.upsertExercise, { record: loser })).status).toBe("ignored_stale");

    vi.setSystemTime((now + 1) * 1000);
    const retry = await client.mutation(api.sync.upsertExercise, { record: loser });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(retry.status).toBe("ignored_stale");
    expect(changes.exercises[0].name).toBe("Winner");
  });

  test("a retried upload stays recognized after many later edits", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    const deviceAUpload = exercise(now + month, { name: "A" });
    await client.mutation(api.sync.upsertExercise, { record: deviceAUpload });
    for (let edit = 1; edit <= 20; edit++) {
      vi.setSystemTime((now + edit) * 1000);
      await client.mutation(api.sync.upsertExercise, {
        record: exercise(now + month + edit * 0.001, { name: `B${edit}` }),
      });
    }

    vi.setSystemTime((now + 30) * 1000);
    const retry = await client.mutation(api.sync.upsertExercise, { record: deviceAUpload });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(retry.status).toBe("ignored_stale");
    expect(changes.exercises[0].name).toBe("B20");
  });

  test("a retried upload cannot undo the edit that replaced it", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // Device A's clock is a month fast. Its upload applies, but the response is lost.
    const deviceAUpload = exercise(now + month, { name: "A" });
    await client.mutation(api.sync.upsertExercise, { record: deviceAUpload });

    // Device B pulls A's version and edits it.
    vi.setSystemTime((now + 1) * 1000);
    const replacing = await client.mutation(api.sync.upsertExercise, {
      record: exercise(now + month + 0.001, { name: "B" }),
    });
    expect(replacing.status).toBe("updated");

    // Device A retries the same upload.
    vi.setSystemTime((now + 2) * 1000);
    const retry = await client.mutation(api.sync.upsertExercise, { record: deviceAUpload });

    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(retry.status).toBe("ignored_stale");
    expect(changes.exercises[0].name).toBe("B");
  });

  test("an edit in the same millisecond as the version it replaced still wins", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await client.mutation(api.sync.upsertExercise, { record: exercise(now, { name: "First" }) });
    // A current build stamps 1 ms above what it saw, even with no time passing.
    const result = await client.mutation(api.sync.upsertExercise, {
      record: exercise(now + 0.001, { name: "Second" }),
    });
    expect(result.status).toBe("updated");
  });

  test("a current build's edit wins over a version from a faster clock", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    const faster = now + 45 * 24 * 3600;
    const stored = await client.mutation(api.sync.upsertExercise, { record: exercise(faster, { name: "Faster" }) });
    vi.setSystemTime((now + minute) * 1000);
    // Current builds stamp an edit above the version it replaces.
    const result = await client.mutation(api.sync.upsertExercise, {
      record: exercise(faster + 0.001, { name: "Fast", baseUpdatedAt: stored.updatedAt }),
    });
    expect(result.status).toBe("updated");
  });

  test("a current build's edit wins after seeing the stored version, even from a dead clock", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    const stored = await client.mutation(api.sync.upsertExercise, { record: exercise(now - 60, { name: "Bench" }) });
    // A dead clock reads 2001, far below the version it replaces.
    const deadClock = Date.UTC(2001, 0, 1) / 1000;
    const result = await client.mutation(api.sync.upsertExercise, {
      record: exercise(deadClock, { name: "Bench Press", baseUpdatedAt: stored.updatedAt }),
    });
    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(result.status).toBe("updated");
    expect(changes.exercises[0].name).toBe("Bench Press");
    // Still above the old version, for installed builds holding it.
    expect(changes.exercises[0].updatedAt).toBeGreaterThan(now - 60);
  });

  test("a late retry from a current build with a fast clock cannot undo a newer edit", async () => {
    for (const editor of ["current", "installed"] as const) {
      const client = convexTest(schema, modules).withIdentity(owner);
      const original = await client.mutation(api.sync.upsertExercise, { record: exercise(now - 100, { name: "Original" }) });
      // Device F runs a current build five minutes fast. Its upload applies,
      // but the response is lost.
      const deviceFUpload = exercise(now + 300, { name: "F", baseUpdatedAt: original.updatedAt });
      const applied = await client.mutation(api.sync.upsertExercise, { record: deviceFUpload });
      expect(applied.status).toBe("updated");

      // Device H, with a correct clock, sees F's version and edits it.
      vi.setSystemTime((now + 60) * 1000);
      const deviceHEdit =
        editor === "current"
          ? exercise(applied.updatedAt + 0.001, { name: "H", baseUpdatedAt: applied.updatedAt })
          : exercise(now + 60, { name: "H" });
      expect((await client.mutation(api.sync.upsertExercise, { record: deviceHEdit })).status).toBe("updated");

      // F retries long after real time passed its stamp.
      vi.setSystemTime((now + 600) * 1000);
      const retry = await client.mutation(api.sync.upsertExercise, { record: deviceFUpload });
      const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
      expect(retry.status, editor).toBe("ignored_stale");
      expect(changes.exercises[0].name, editor).toBe("H");
      vi.setSystemTime(now * 1000);
    }
  });

  test("limitation: an installed build re-sending a pulled version can revert an edit made within a few seconds of clock skew", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    // A device ten seconds fast wrote V. Installed build B pulled V, which
    // overwrote B's own pending edit, so B will re-send V.
    const version = exercise(now + 10, { name: "V" });
    const stored = await client.mutation(api.sync.upsertExercise, { record: version });
    // A current build edits V two seconds later.
    vi.setSystemTime((now + 2) * 1000);
    await client.mutation(api.sync.upsertExercise, {
      record: exercise(now + 10.001, { name: "C", baseUpdatedAt: stored.updatedAt }),
    });
    // B's re-send arrives after real time passed V's stamp. Without a base it
    // is judged on its effective time, which is now later than C's arrival.
    vi.setSystemTime((now + 20) * 1000);
    const resend = await client.mutation(api.sync.upsertExercise, { record: version });
    expect(resend.status).toBe("updated");
  });

  test("limitation: an installed build with a fast clock cannot replace a version from a faster one", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await client.mutation(api.sync.upsertExercise, { record: exercise(now + 45 * 24 * 3600, { name: "Faster" }) });
    vi.setSystemTime((now + minute) * 1000);
    // Indistinguishable from a late retry of an upload the server already
    // processed, so it loses until its clock passes the stored timestamp.
    const result = await client.mutation(api.sync.upsertExercise, {
      record: exercise(now + month + minute, { name: "Fast" }),
    });
    expect(result.status).toBe("ignored_stale");
  });

  test("upload results report the stored version for the next edit's base", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    const inserted = await client.mutation(api.sync.upsertExercise, { record: exercise(now - 60) });
    expect(inserted).toMatchObject({ status: "inserted", updatedAt: now - 60 });
    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(changes.exercises[0]).not.toHaveProperty("baseUpdatedAt");
  });

  test("an edit in a burst of writes within one millisecond still wins", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    const raw = now + month;
    expect((await client.mutation(api.sync.upsertExercise, { record: exercise(raw, { name: "1" }) })).status).toBe("inserted");
    expect((await client.mutation(api.sync.upsertExercise, { record: exercise(raw + 0.001, { name: "2" }) })).status).toBe("updated");
    expect((await client.mutation(api.sync.upsertExercise, { record: exercise(raw + 0.002, { name: "3" }) })).status).toBe("updated");
  });

  test("an unchanged upload whose timestamp lost precision is not a new write", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    const stored = await client.mutation(api.sync.upsertExercise, { record: exercise(now - 60) });
    const roundTripped = await client.mutation(api.sync.upsertExercise, {
      record: exercise(now - 60 + 1e-7),
    });
    expect(roundTripped).toMatchObject({ status: "ignored_stale", serverUpdatedAt: stored.serverUpdatedAt });
  });

  test("a future deletion time is clamped to server time", async () => {
    const client = convexTest(schema, modules).withIdentity(owner);
    await client.mutation(api.sync.upsertExercise, { record: exercise(now - 60) });
    await client.mutation(api.sync.tombstone, {
      entityKind: "exercises",
      clientId: "exercise-1",
      deletedAt: now + month,
    });
    const changes = await client.mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });
    expect(changes.exercises[0].deletedAt).toBe(now);
  });
});

describe("merge rule", () => {
  const stored = { updatedAt: now - 60, deletedAt: null, serverUpdatedAt: (now - 60) * 1000 };

  test("the effective stored time never exceeds the time the row was written", () => {
    expect(effectiveStoredTime({ ...stored, updatedAt: now + month })).toBe(now - 60);
  });

  test("an exact duplicate is ignored without a write", () => {
    expect(
      decideUpsert(stored, { updatedAt: now - 60, deletedAt: null }, {
        nowSeconds: now,
        sameContent: true,
        parentDeletedAt: null,
      }),
    ).toEqual({ action: "ignore" });
  });

  test("a deletion is never undone, whatever the timestamps", () => {
    const tombstone = { ...stored, deletedAt: now - 60 };
    for (const updatedAt of [now - 3600, now - 60, now, now + month]) {
      const decision = decideUpsert(tombstone, { updatedAt, deletedAt: null }, {
        nowSeconds: now,
        sameContent: false,
        parentDeletedAt: null,
      });
      expect(decision.action === "ignore" || decision.deletedAt === now - 60).toBe(true);
    }
  });
});
