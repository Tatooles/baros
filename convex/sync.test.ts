import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

declare global {
  interface ImportMeta {
    glob(pattern: string): Record<string, () => Promise<any>>;
  }
}

const modules = import.meta.glob("./**/*.{ts,js}");

const zeroCursors: SyncCursors = {
  userSettings: 0,
  exercises: 0,
  workoutSessions: 0,
  loggedExercises: 0,
  loggedSets: 0,
};

function testDb() {
  return convexTest(schema, modules);
}

const userA = {
  subject: "user_a",
  issuer: "https://glad-krill-22.clerk.accounts.dev",
  tokenIdentifier: "https://glad-krill-22.clerk.accounts.dev|user_a",
  email: "a@example.com",
};

const userB = {
  subject: "user_b",
  issuer: "https://glad-krill-22.clerk.accounts.dev",
  tokenIdentifier: "https://glad-krill-22.clerk.accounts.dev|user_b",
  email: "b@example.com",
};

function exerciseRecord(overrides: Partial<ExerciseRecord> = {}): ExerciseRecord {
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
    createdAt: 1,
    updatedAt: 2,
    deletedAt: null,
    ...overrides,
  };
}

function userSettingsRecord(
  overrides: Partial<UserSettingsRecord> = {},
): UserSettingsRecord {
  return {
    clientId: "settings-1",
    weightUnitRaw: "pounds",
    defaultRestTimerSeconds: 120,
    hasCompletedOnboarding: true,
    createdAt: 1,
    updatedAt: 2,
    deletedAt: null,
    ...overrides,
  };
}

function loggedExerciseRecord(
  overrides: Partial<LoggedExerciseRecord> = {},
): LoggedExerciseRecord {
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
    createdAt: 1,
    updatedAt: 2,
    deletedAt: null,
    ...overrides,
  };
}

type ExerciseRecord = {
  clientId: string;
  seedIdentifier: string | null;
  name: string;
  categoryRaw: string;
  equipmentRaw: string;
  primaryMuscleRaw: string;
  primaryMuscleGroupRaw?: string;
  notes: string;
  isArchived: boolean;
  isSeeded: boolean;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};

type UserSettingsRecord = {
  clientId: string;
  weightUnitRaw: "pounds" | "kilograms";
  defaultRestTimerSeconds: number;
  hasCompletedOnboarding: boolean;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};

type LoggedExerciseRecord = {
  clientId: string;
  sessionClientId: string;
  exerciseClientId: string | null;
  orderIndex: number;
  exerciseSnapshotName: string;
  exerciseSnapshotEquipmentRaw: string;
  exerciseSnapshotPrimaryMuscleGroupRaw: string;
  hasSnapshotMetadata: boolean;
  notes: string;
  referenceNotes: string | null;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};

type SyncCursors = {
  userSettings: number;
  exercises: number;
  workoutSessions: number;
  loggedExercises: number;
  loggedSets: number;
};

describe("auth smoke", () => {
  test("me rejects unauthenticated callers", async () => {
    const t = testDb();

    await expect(t.query(api.authSmoke.me, {})).rejects.toThrow(
      "Not authenticated",
    );
  });

  test("me returns authenticated identity", async () => {
    const t = testDb().withIdentity(userA);

    await expect(t.query(api.authSmoke.me, {})).resolves.toMatchObject({
      tokenIdentifier: userA.tokenIdentifier,
      subject: userA.subject,
      issuer: userA.issuer,
      email: userA.email,
    });
  });
});

describe("sync access control", () => {
  test("upsert rejects unauthenticated callers", async () => {
    const t = testDb();

    await expect(
      t.mutation(api.sync.upsertExercise, { record: exerciseRecord() }),
    ).rejects.toThrow("Not authenticated");
  });

  test("users only fetch their own records", async () => {
    const t = testDb();

    await t
      .withIdentity(userA)
      .mutation(api.sync.upsertExercise, { record: exerciseRecord() });

    await t.withIdentity(userB).mutation(api.sync.upsertExercise, {
      record: exerciseRecord({
        clientId: "exercise-2",
        name: "Squat",
      }),
    });

    const userAChanges = await t
      .withIdentity(userA)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    const userBChanges = await t
      .withIdentity(userB)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(userAChanges.exercises.map((record) => record.clientId)).toEqual([
      "exercise-1",
    ]);
    expect(userBChanges.exercises.map((record) => record.clientId)).toEqual([
      "exercise-2",
    ]);
  });
});

describe("sync conflict behavior", () => {
  test("legacy stored exercise docs without muscle group are normalized in changes", async () => {
    const t = testDb();

    await t.run(async (ctx) => {
      await ctx.db.insert("exercises", {
        ownerTokenIdentifier: userA.tokenIdentifier,
        clientId: "legacy-exercise",
        seedIdentifier: null,
        name: "Legacy Bench Press",
        categoryRaw: "strength",
        equipmentRaw: "barbell",
        primaryMuscleRaw: "Chest",
        notes: "",
        isArchived: false,
        isSeeded: false,
        createdAt: 1,
        updatedAt: 2,
        deletedAt: null,
        serverUpdatedAt: 3,
      });
    });

    const changes = await t
      .withIdentity(userA)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(changes.exercises).toHaveLength(1);
    expect(changes.exercises[0]).toMatchObject({
      clientId: "legacy-exercise",
      primaryMuscleRaw: "Chest",
      primaryMuscleGroupRaw: "other",
    });
  });

  test("legacy exercise payloads without muscle group are accepted and normalized", async () => {
    const t = testDb().withIdentity(userA);
    const { primaryMuscleGroupRaw: _primaryMuscleGroupRaw, ...legacyRecord } =
      exerciseRecord({
        primaryMuscleRaw: "Legacy Free Text",
      });

    await t.mutation(api.sync.upsertExercise, { record: legacyRecord });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.exercises).toHaveLength(1);
    expect(changes.exercises[0]).toMatchObject({
      primaryMuscleRaw: "Legacy Free Text",
      primaryMuscleGroupRaw: "other",
    });
  });

  test("legacy exercise update payloads preserve existing muscle group", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({
        primaryMuscleRaw: "Glutes",
        primaryMuscleGroupRaw: "glutes",
      }),
    });

    const { primaryMuscleGroupRaw: _primaryMuscleGroupRaw, ...legacyUpdate } =
      exerciseRecord({
        name: "Updated Bench Press",
        primaryMuscleRaw: "Legacy Free Text",
        updatedAt: 3,
      });

    await t.mutation(api.sync.upsertExercise, { record: legacyUpdate });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.exercises).toHaveLength(1);
    expect(changes.exercises[0]).toMatchObject({
      name: "Updated Bench Press",
      primaryMuscleRaw: "Legacy Free Text",
      primaryMuscleGroupRaw: "glutes",
    });
  });

  test("future exercise taxonomy strings round-trip through sync", async () => {
    const t = testDb().withIdentity(userA);
    const record = exerciseRecord({
      categoryRaw: "plyometrics",
      equipmentRaw: "gravity-boots",
      primaryMuscleRaw: "Future Chest",
      primaryMuscleGroupRaw: "future-upper-body",
    });

    await t.mutation(api.sync.upsertExercise, { record });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.exercises).toHaveLength(1);
    expect(changes.exercises[0]).toMatchObject({
      categoryRaw: "plyometrics",
      equipmentRaw: "gravity-boots",
      primaryMuscleRaw: "Future Chest",
      primaryMuscleGroupRaw: "future-upper-body",
    });
  });

  test("logged exercise snapshot metadata round-trips through sync", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord({
        exerciseSnapshotEquipmentRaw: "smithMachine",
        exerciseSnapshotPrimaryMuscleGroupRaw: "glutes",
        hasSnapshotMetadata: true,
      }),
    });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.loggedExercises).toHaveLength(1);
    expect(changes.loggedExercises[0]).toMatchObject({
      clientId: "logged-exercise-1",
      exerciseSnapshotName: "Bench Press",
      exerciseSnapshotEquipmentRaw: "smithMachine",
      exerciseSnapshotPrimaryMuscleGroupRaw: "glutes",
      hasSnapshotMetadata: true,
    });
  });

  test("legacy logged exercise payloads without snapshot metadata are accepted and normalized", async () => {
    const t = testDb().withIdentity(userA);
    const {
      exerciseSnapshotEquipmentRaw: _exerciseSnapshotEquipmentRaw,
      exerciseSnapshotPrimaryMuscleGroupRaw:
        _exerciseSnapshotPrimaryMuscleGroupRaw,
      hasSnapshotMetadata: _hasSnapshotMetadata,
      ...legacyRecord
    } = loggedExerciseRecord();

    await t.mutation(api.sync.upsertLoggedExercise, { record: legacyRecord });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.loggedExercises).toHaveLength(1);
    expect(changes.loggedExercises[0]).toMatchObject({
      clientId: "logged-exercise-1",
      exerciseSnapshotEquipmentRaw: "other",
      exerciseSnapshotPrimaryMuscleGroupRaw: "other",
      hasSnapshotMetadata: false,
    });
  });

  test("legacy stored logged exercise docs without snapshot metadata are normalized in changes", async () => {
    const t = testDb();

    await t.run(async (ctx) => {
      await ctx.db.insert("loggedExercises", {
        ownerTokenIdentifier: userA.tokenIdentifier,
        clientId: "legacy-logged-exercise",
        sessionClientId: "session-1",
        exerciseClientId: "exercise-1",
        orderIndex: 0,
        exerciseSnapshotName: "Bench Press",
        notes: "",
        referenceNotes: null,
        createdAt: 1,
        updatedAt: 2,
        deletedAt: null,
        serverUpdatedAt: 3,
      });
    });

    const changes = await t
      .withIdentity(userA)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(changes.loggedExercises).toHaveLength(1);
    expect(changes.loggedExercises[0]).toMatchObject({
      clientId: "legacy-logged-exercise",
      exerciseSnapshotName: "Bench Press",
      exerciseSnapshotEquipmentRaw: "other",
      exerciseSnapshotPrimaryMuscleGroupRaw: "other",
      hasSnapshotMetadata: false,
    });
  });

  test("legacy logged exercise update payloads preserve existing snapshot metadata", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord({
        exerciseSnapshotEquipmentRaw: "smithMachine",
        exerciseSnapshotPrimaryMuscleGroupRaw: "glutes",
        hasSnapshotMetadata: true,
      }),
    });

    const {
      exerciseSnapshotEquipmentRaw: _exerciseSnapshotEquipmentRaw,
      exerciseSnapshotPrimaryMuscleGroupRaw:
        _exerciseSnapshotPrimaryMuscleGroupRaw,
      hasSnapshotMetadata: _hasSnapshotMetadata,
      ...legacyUpdate
    } = loggedExerciseRecord({
      notes: "Updated from old client",
      updatedAt: 3,
    });

    await t.mutation(api.sync.upsertLoggedExercise, { record: legacyUpdate });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.loggedExercises).toHaveLength(1);
    expect(changes.loggedExercises[0]).toMatchObject({
      notes: "Updated from old client",
      exerciseSnapshotEquipmentRaw: "smithMachine",
      exerciseSnapshotPrimaryMuscleGroupRaw: "glutes",
      hasSnapshotMetadata: true,
    });
  });

  test("non-finite numbers are rejected before records are written", async () => {
    const t = testDb().withIdentity(userA);

    await expect(
      t.mutation(api.sync.upsertExercise, {
        record: exerciseRecord({ updatedAt: Number.NaN }),
      }),
    ).rejects.toThrow("updatedAt must be a finite number");
    await expect(
      t.mutation(api.sync.tombstone, {
        entityKind: "exercises",
        clientId: "exercise-1",
        deletedAt: Number.POSITIVE_INFINITY,
      }),
    ).rejects.toThrow("deletedAt must be a finite number");
    await expect(
      t.query(api.sync.fetchChanges, {
        cursors: { ...zeroCursors, exercises: Number.NEGATIVE_INFINITY },
      }),
    ).rejects.toThrow("exercises cursor must be a finite number");

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.exercises).toHaveLength(0);
  });

  test("tombstone preserves deleted records in change feed", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertExercise, { record: exerciseRecord() });
    await t.mutation(api.sync.tombstone, {
      entityKind: "exercises",
      clientId: "exercise-1",
      deletedAt: 3,
    });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.exercises).toHaveLength(1);
    expect(changes.exercises[0].deletedAt).toBe(3);
    expect(changes.exercises[0].updatedAt).toBe(3);
  });

  test("stale and equal-timestamp upserts are ignored idempotently", async () => {
    const t = testDb().withIdentity(userA);

    const inserted = await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ updatedAt: 4, name: "Bench Press" }),
    });
    const equalTimestamp = await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ updatedAt: 4, name: "Incline Press" }),
    });
    const stale = await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ updatedAt: 3, name: "Decline Press" }),
    });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(inserted.status).toBe("inserted");
    expect(equalTimestamp).toEqual({
      status: "ignored_stale",
      serverUpdatedAt: inserted.serverUpdatedAt,
    });
    expect(stale).toEqual({
      status: "ignored_stale",
      serverUpdatedAt: inserted.serverUpdatedAt,
    });
    expect(changes.exercises).toHaveLength(1);
    expect(changes.exercises[0].name).toBe("Bench Press");
    expect(changes.exercises[0].serverUpdatedAt).toBe(inserted.serverUpdatedAt);
  });

  test("stale and equal-timestamp tombstones are ignored", async () => {
    const t = testDb().withIdentity(userA);

    const inserted = await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ updatedAt: 4 }),
    });
    const equalTimestamp = await t.mutation(api.sync.tombstone, {
      entityKind: "exercises",
      clientId: "exercise-1",
      deletedAt: 4,
    });
    const stale = await t.mutation(api.sync.tombstone, {
      entityKind: "exercises",
      clientId: "exercise-1",
      deletedAt: 3,
    });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(equalTimestamp).toEqual({
      status: "ignored_stale",
      serverUpdatedAt: inserted.serverUpdatedAt,
    });
    expect(stale).toEqual({
      status: "ignored_stale",
      serverUpdatedAt: inserted.serverUpdatedAt,
    });
    expect(changes.exercises).toHaveLength(1);
    expect(changes.exercises[0].deletedAt).toBeNull();
    expect(changes.exercises[0].updatedAt).toBe(4);
  });
});

describe("sync change cursors", () => {
  test("settings exercise changes do not return workout history pages", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertUserSettings, {
      record: userSettingsRecord({ updatedAt: 2 }),
    });
    await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ updatedAt: 3 }),
    });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: {
        clientId: "session-1",
        title: "Push Day",
        startedAt: 1,
        endedAt: 2,
        durationSeconds: 60,
        notes: "",
        referenceNotes: null,
        statusRaw: "completed",
        sourceRaw: "blank",
        sourceSessionID: null,
        healthLinkID: null,
        createdAt: 1,
        updatedAt: 4,
        deletedAt: null,
      },
    });
    await t.mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord({ updatedAt: 5 }),
    });

    const changes = await t.query(api.sync.fetchSettingsExerciseChanges, {
      cursors: zeroCursors,
    });

    expect(changes.userSettings).toHaveLength(1);
    expect(changes.exercises).toHaveLength(1);
    expect(changes.workoutSessions).toHaveLength(0);
    expect(changes.loggedExercises).toHaveLength(0);
    expect(changes.loggedSets).toHaveLength(0);
    expect(changes.cursors.userSettings).toBeGreaterThan(0);
    expect(changes.cursors.exercises).toBeGreaterThan(0);
    expect(changes.cursors.workoutSessions).toBe(0);
    expect(changes.cursors.loggedExercises).toBe(0);
    expect(changes.cursors.loggedSets).toBe(0);
    expect(changes.hasMore.workoutSessions).toBe(false);
    expect(changes.hasMore.loggedExercises).toBe(false);
    expect(changes.hasMore.loggedSets).toBe(false);
  });

  test("per-table cursors do not skip remaining rows when another table has a higher cursor", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ clientId: "exercise-1", updatedAt: 2 }),
    });
    await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ clientId: "exercise-2", updatedAt: 3 }),
    });
    await t.mutation(api.sync.upsertUserSettings, {
      record: userSettingsRecord({ updatedAt: 4 }),
    });

    const firstPage = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
      limit: 1,
    });
    const secondPage = await t.query(api.sync.fetchChanges, {
      cursors: firstPage.cursors,
      limit: 1,
    });

    expect(firstPage.exercises.map((record) => record.clientId)).toEqual([
      "exercise-1",
    ]);
    expect(firstPage.userSettings.map((record) => record.clientId)).toEqual([
      "settings-1",
    ]);
    expect(firstPage.hasMore.exercises).toBe(true);
    expect(firstPage.hasMore.userSettings).toBe(false);
    expect(firstPage.cursors.userSettings).toBeGreaterThan(
      firstPage.cursors.exercises,
    );
    expect(secondPage.exercises.map((record) => record.clientId)).toEqual([
      "exercise-2",
    ]);
    expect(secondPage.userSettings).toHaveLength(0);
  });
});
