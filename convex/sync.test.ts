import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import {
  accountDeletionPassLimitReached,
  deleteAccountDataForOwner,
  deleteAccountDataWithBatches,
} from "./sync";
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
    sourceLoggedExerciseID: null,
    createdAt: 1,
    updatedAt: 2,
    deletedAt: null,
    ...overrides,
  };
}

function workoutSessionRecord(
  overrides: Partial<WorkoutSessionRecord> = {},
): WorkoutSessionRecord {
  return {
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
    updatedAt: 2,
    deletedAt: null,
    ...overrides,
  };
}

function loggedSetRecord(overrides: Partial<LoggedSetRecord> = {}): LoggedSetRecord {
  return {
    clientId: "logged-set-1",
    loggedExerciseClientId: "logged-exercise-1",
    orderIndex: 0,
    weight: 135,
    reps: 10,
    rpe: 8,
    kindRaw: "working",
    isCompleted: true,
    completedAt: 2,
    notes: "",
    healthLinkID: null,
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

type WorkoutSessionRecord = {
  clientId: string;
  title: string;
  startedAt: number;
  endedAt: number | null;
  durationSeconds: number;
  notes: string;
  referenceNotes: string | null;
  statusRaw: "completed" | "discarded";
  sourceRaw: "blank" | "pastWorkout" | "template";
  sourceSessionID: string | null;
  healthLinkID: string | null;
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
  sourceLoggedExerciseID: string | null;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};

type LoggedSetRecord = {
  clientId: string;
  loggedExerciseClientId: string;
  orderIndex: number;
  weight: number | null;
  reps: number | null;
  rpe: number | null;
  kindRaw: "working" | "warmup" | "drop" | "failure";
  isCompleted: boolean;
  completedAt: number | null;
  notes: string;
  healthLinkID: string | null;
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

  test("one-shot fetch changes mutation returns owner-scoped records", async () => {
    const t = testDb();

    await t
      .withIdentity(userA)
      .mutation(api.sync.upsertExercise, { record: exerciseRecord() });

    const changes = await t
      .withIdentity(userA)
      .mutation(api.sync.fetchChangesOnce, { cursors: zeroCursors });

    expect(changes.exercises.map((record) => record.clientId)).toEqual([
      "exercise-1",
    ]);
  });
});

describe("account data deletion", () => {
  async function seedFullSyncGraphForOwner(
    t: ReturnType<typeof testDb>,
    identity: typeof userA,
    suffix: string,
  ) {
    const clientSuffix = suffix.toLowerCase();
    await t.withIdentity(identity).mutation(api.sync.upsertUserSettings, {
      record: userSettingsRecord({ clientId: `settings-${clientSuffix}` }),
    });
    await t.withIdentity(identity).mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ clientId: `exercise-${clientSuffix}` }),
    });
    await t.withIdentity(identity).mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord({ clientId: `session-${clientSuffix}` }),
    });
    await t.withIdentity(identity).mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord({
        clientId: `logged-exercise-${clientSuffix}`,
        sessionClientId: `session-${clientSuffix}`,
        exerciseClientId: `exercise-${clientSuffix}`,
      }),
    });
    await t.withIdentity(identity).mutation(api.sync.upsertLoggedSet, {
      record: loggedSetRecord({
        clientId: `logged-set-${clientSuffix}`,
        loggedExerciseClientId: `logged-exercise-${clientSuffix}`,
      }),
    });
  }

  async function seedLoggedSetsDirectlyForOwner(
    t: ReturnType<typeof testDb>,
    identity: typeof userA,
    count: number,
  ) {
    await t.run(async (ctx) => {
      for (let i = 0; i < count; i++) {
        await ctx.db.insert("loggedSets", {
          ownerTokenIdentifier: identity.tokenIdentifier,
          clientId: `bulk-logged-set-${i}`,
          loggedExerciseClientId: "bulk-logged-exercise",
          orderIndex: i,
          weight: 135,
          reps: 10,
          rpe: 8,
          kindRaw: "working",
          isCompleted: true,
          completedAt: 2,
          notes: "",
          healthLinkID: null,
          createdAt: i + 1,
          updatedAt: i + 1,
          deletedAt: null,
          serverUpdatedAt: i + 1,
        });
      }
    });
  }

  async function seedMixedDeletionGraphForOwner(
    t: ReturnType<typeof testDb>,
    identity: typeof userA,
  ) {
    await t.run(async (ctx) => {
      await ctx.db.insert("exercises", {
        ownerTokenIdentifier: identity.tokenIdentifier,
        clientId: "mixed-exercise-1",
        seedIdentifier: null,
        name: "Mixed Bench Press",
        categoryRaw: "strength",
        equipmentRaw: "barbell",
        primaryMuscleRaw: "Chest",
        primaryMuscleGroupRaw: "chest",
        notes: "",
        isArchived: false,
        isSeeded: false,
        createdAt: 1,
        updatedAt: 1,
        deletedAt: null,
        serverUpdatedAt: 1,
      });
      await ctx.db.insert("exercises", {
        ownerTokenIdentifier: identity.tokenIdentifier,
        clientId: "mixed-exercise-2",
        seedIdentifier: null,
        name: "Mixed Squat",
        categoryRaw: "strength",
        equipmentRaw: "barbell",
        primaryMuscleRaw: "Legs",
        primaryMuscleGroupRaw: "legs",
        notes: "",
        isArchived: false,
        isSeeded: false,
        createdAt: 2,
        updatedAt: 2,
        deletedAt: null,
        serverUpdatedAt: 2,
      });

      for (let i = 0; i < 1001; i++) {
        await ctx.db.insert("loggedSets", {
          ownerTokenIdentifier: identity.tokenIdentifier,
          clientId: `mixed-logged-set-${i}`,
          loggedExerciseClientId: "mixed-logged-exercise",
          orderIndex: i,
          weight: 135,
          reps: 10,
          rpe: 8,
          kindRaw: "working",
          isCompleted: true,
          completedAt: 2,
          notes: "",
          healthLinkID: null,
          createdAt: i + 1,
          updatedAt: i + 1,
          deletedAt: null,
          serverUpdatedAt: i + 3,
        });
      }
    });
  }

  test("deleteAccountData rejects unauthenticated callers", async () => {
    const t = testDb();

    await expect(
      t.action(api.sync.deleteAccountData, {
        cancellationToken: "device-a",
      }),
    ).rejects.toThrow("Not authenticated");
  });

  test("deleteAccountData deletes only the authenticated owner rows", async () => {
    const t = testDb();
    await seedFullSyncGraphForOwner(t, userA, "A");
    await seedFullSyncGraphForOwner(t, userB, "B");

    await expect(
      t.withIdentity(userA).action(api.sync.deleteAccountData, {
        cancellationToken: "device-a",
      }),
    ).resolves.toEqual({
      status: "deleted",
      deletedCounts: {
        loggedSets: 1,
        loggedExercises: 1,
        workoutSessions: 1,
        exercises: 1,
        userSettings: 1,
      },
    });

    const userAChanges = await t
      .withIdentity(userA)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });
    const userBChanges = await t
      .withIdentity(userB)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(userAChanges.userSettings).toEqual([]);
    expect(userAChanges.exercises).toEqual([]);
    expect(userAChanges.workoutSessions).toEqual([]);
    expect(userAChanges.loggedExercises).toEqual([]);
    expect(userAChanges.loggedSets).toEqual([]);
    expect(userBChanges.userSettings.map((record) => record.clientId)).toEqual([
      "settings-b",
    ]);
    expect(userBChanges.exercises.map((record) => record.clientId)).toEqual([
      "exercise-b",
    ]);
    expect(userBChanges.workoutSessions.map((record) => record.clientId)).toEqual([
      "session-b",
    ]);
    expect(userBChanges.loggedExercises.map((record) => record.clientId)).toEqual([
      "logged-exercise-b",
    ]);
    expect(userBChanges.loggedSets.map((record) => record.clientId)).toEqual([
      "logged-set-b",
    ]);
  });

  test("deleteAccountData is idempotent", async () => {
    const t = testDb();
    await seedFullSyncGraphForOwner(t, userA, "A");

    await t.withIdentity(userA).action(api.sync.deleteAccountData, {
      cancellationToken: "device-a",
    });

    await expect(
      t.withIdentity(userA).action(api.sync.deleteAccountData, {
        cancellationToken: "device-a",
      }),
    ).resolves.toEqual({
      status: "deleted",
      deletedCounts: {
        loggedSets: 0,
        loggedExercises: 0,
        workoutSessions: 0,
        exercises: 0,
        userSettings: 0,
      },
    });
  });

  test("account deletion marker blocks new writes for the deleted owner", async () => {
    const t = testDb();

    await t.withIdentity(userA).action(api.sync.deleteAccountData, {
      cancellationToken: "device-a",
    });

    await expect(
      t.withIdentity(userA).mutation(api.sync.upsertExercise, {
        record: exerciseRecord({ clientId: "late-exercise" }),
      }),
    ).rejects.toThrow("Account deletion is in progress");
    await expect(
      t.withIdentity(userA).mutation(api.sync.tombstone, {
        entityKind: "exercises",
        clientId: "late-exercise",
        deletedAt: 3,
      }),
    ).rejects.toThrow("Account deletion is in progress");

    const changes = await t
      .withIdentity(userA)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(changes.exercises).toEqual([]);
  });

  test("account deletion marker does not block other owners", async () => {
    const t = testDb();

    await t.withIdentity(userA).action(api.sync.deleteAccountData, {
      cancellationToken: "device-a",
    });

    await expect(
      t.withIdentity(userB).mutation(api.sync.upsertExercise, {
        record: exerciseRecord({ clientId: "other-owner-exercise" }),
      }),
    ).resolves.toMatchObject({ status: "inserted" });

    const userBChanges = await t
      .withIdentity(userB)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(userBChanges.exercises.map((record) => record.clientId)).toEqual([
      "other-owner-exercise",
    ]);
  });

  test("cancelAccountDeletion clears the marker for the initiating client token", async () => {
    const t = testDb();

    await t.withIdentity(userA).action(api.sync.deleteAccountData, {
      cancellationToken: "device-a",
    });

    await expect(
      t.withIdentity(userA).action(api.sync.cancelAccountDeletion, {
        cancellationToken: "device-a",
      }),
    ).resolves.toEqual({ status: "cancelled" });

    await expect(
      t.withIdentity(userA).mutation(api.sync.upsertExercise, {
        record: exerciseRecord({ clientId: "post-cancel-exercise" }),
      }),
    ).resolves.toMatchObject({ status: "inserted" });
  });

  test("cancelAccountDeletion rejects a different client token for the same owner", async () => {
    const t = testDb();

    await t.withIdentity(userA).action(api.sync.deleteAccountData, {
      cancellationToken: "device-a",
    });

    await expect(
      t.withIdentity(userA).action(api.sync.cancelAccountDeletion, {
        cancellationToken: "different-client-token",
      }),
    ).rejects.toThrow("Account deletion is already in progress on another client");

    await expect(
      t.withIdentity(userA).mutation(api.sync.upsertExercise, {
        record: exerciseRecord({ clientId: "still-blocked-exercise" }),
      }),
    ).rejects.toThrow("Account deletion is in progress");
  });

  test("deleteAccountDataForOwner keeps the marker when deletion fails", async () => {
    let started = false;
    const seenTables: string[] = [];

    await expect(
      deleteAccountDataForOwner(
        async () => {
          started = true;
        },
        async (tableName) => {
          seenTables.push(tableName);
          throw new Error(`failed ${tableName}`);
        },
      ),
    ).rejects.toThrow("failed loggedSets");

    expect(started).toBe(true);
    expect(seenTables).toEqual(["loggedSets"]);
  });

  test("account deletion pass limit helper respects the configured cap", async () => {
    expect(accountDeletionPassLimitReached(99)).toBe(false);
    expect(accountDeletionPassLimitReached(100)).toBe(true);
  });

  test("deleteAccountDataWithBatches throws after the pass cap", async () => {
    const seenTables: string[] = [];

    await expect(
      deleteAccountDataWithBatches(async (tableName) => {
        seenTables.push(tableName);
        return {
          tableName,
          deletedCount: 0,
          hasMore: true,
        };
      }, 2),
    ).rejects.toThrow("Account data deletion did not finish. Retry account deletion.");

    expect(seenTables).toEqual([
      "loggedSets",
      "loggedExercises",
      "workoutSessions",
      "exercises",
      "userSettings",
      "loggedSets",
      "loggedExercises",
      "workoutSessions",
      "exercises",
      "userSettings",
    ]);
  });

  test("deleteAccountDataBatch only deletes the requested table", async () => {
    const t = testDb();
    await t.run(async (ctx) => {
      await ctx.db.insert("exercises", {
        ownerTokenIdentifier: userA.tokenIdentifier,
        clientId: "isolation-exercise",
        seedIdentifier: null,
        name: "Isolation Bench Press",
        categoryRaw: "strength",
        equipmentRaw: "barbell",
        primaryMuscleRaw: "Chest",
        primaryMuscleGroupRaw: "chest",
        notes: "",
        isArchived: false,
        isSeeded: false,
        createdAt: 1,
        updatedAt: 1,
        deletedAt: null,
        serverUpdatedAt: 1,
      });
    });
    await seedLoggedSetsDirectlyForOwner(t, userA, 1001);

    await expect(
      t.mutation(internal.sync.deleteAccountDataBatch, {
        ownerTokenIdentifier: userA.tokenIdentifier,
        tableName: "loggedSets",
      }),
    ).resolves.toEqual({
      tableName: "loggedSets",
      deletedCount: 1000,
      hasMore: true,
    });

    const changes = await t
      .withIdentity(userA)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(changes.exercises.map((record) => record.clientId)).toEqual([
      "isolation-exercise",
    ]);
    expect(changes.loggedSets).toHaveLength(1);
  });

  test("deleteAccountData handles mixed tables in separate batches", async () => {
    const t = testDb();
    await seedMixedDeletionGraphForOwner(t, userA);

    await expect(
      t.withIdentity(userA).action(api.sync.deleteAccountData, {
        cancellationToken: "device-a",
      }),
    ).resolves.toEqual({
      status: "deleted",
      deletedCounts: {
        loggedSets: 1001,
        loggedExercises: 0,
        workoutSessions: 0,
        exercises: 2,
        userSettings: 0,
      },
    });

    const changes = await t
      .withIdentity(userA)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(changes.loggedSets).toEqual([]);
    expect(changes.exercises).toEqual([]);
  });

  test("deleteAccountData deletes more than one batch of logged sets", async () => {
    const t = testDb();
    await seedLoggedSetsDirectlyForOwner(t, userA, 1001);

    await expect(
      t.withIdentity(userA).action(api.sync.deleteAccountData, {
        cancellationToken: "device-a",
      }),
    ).resolves.toEqual({
      status: "deleted",
      deletedCounts: {
        loggedSets: 1001,
        loggedExercises: 0,
        workoutSessions: 0,
        exercises: 0,
        userSettings: 0,
      },
    });

    const changes = await t
      .withIdentity(userA)
      .query(api.sync.fetchChanges, { cursors: zeroCursors });

    expect(changes.loggedSets).toEqual([]);
  });
});

describe("sync conflict behavior", () => {
  test("active logged exercise upsert rejects a missing workout session parent", async () => {
    const t = testDb().withIdentity(userA);

    await expect(
      t.mutation(api.sync.upsertLoggedExercise, {
        record: loggedExerciseRecord({ sessionClientId: "missing-session" }),
      }),
    ).rejects.toThrow(
      "Cannot upsert active logged exercise without its workout session parent.",
    );
  });

  test("active logged exercise upsert rejects a missing exercise reference", async () => {
    const t = testDb().withIdentity(userA);
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord(),
    });

    await expect(
      t.mutation(api.sync.upsertLoggedExercise, {
        record: loggedExerciseRecord({ exerciseClientId: "missing-exercise" }),
      }),
    ).rejects.toThrow(
      "Cannot upsert active logged exercise with a missing exercise reference.",
    );
  });

  test("active logged exercise upsert accepts a tombstoned exercise reference", async () => {
    const t = testDb().withIdentity(userA);
    await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord(),
    });
    await t.mutation(api.sync.tombstone, {
      entityKind: "exercises",
      clientId: "exercise-1",
      deletedAt: 3,
    });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord(),
    });

    await expect(
      t.mutation(api.sync.upsertLoggedExercise, {
        record: loggedExerciseRecord({ updatedAt: 4 }),
      }),
    ).resolves.toMatchObject({ status: "inserted" });
  });

  test("active logged set upsert rejects a missing logged exercise parent", async () => {
    const t = testDb().withIdentity(userA);

    await expect(
      t.mutation(api.sync.upsertLoggedSet, {
        record: loggedSetRecord({ loggedExerciseClientId: "missing-logged-exercise" }),
      }),
    ).rejects.toThrow(
      "Cannot upsert active logged set without its logged exercise parent.",
    );
  });

  test("deleted workout children can upsert without parent rows", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord({
        sessionClientId: "missing-session",
        updatedAt: 4,
        deletedAt: 4,
      }),
    });
    await t.mutation(api.sync.upsertLoggedSet, {
      record: loggedSetRecord({
        loggedExerciseClientId: "missing-logged-exercise",
        updatedAt: 5,
        deletedAt: 5,
      }),
    });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.loggedExercises).toHaveLength(1);
    expect(changes.loggedSets).toHaveLength(1);
    expect(changes.loggedExercises[0]).toMatchObject({
      clientId: "logged-exercise-1",
      deletedAt: 4,
    });
    expect(changes.loggedSets[0]).toMatchObject({
      clientId: "logged-set-1",
      deletedAt: 5,
    });
  });

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

    await t.mutation(api.sync.upsertExercise, { record: exerciseRecord() });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord(),
    });

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

    await t.mutation(api.sync.upsertExercise, { record: exerciseRecord() });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord(),
    });

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

    await t.mutation(api.sync.upsertExercise, { record: exerciseRecord() });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord(),
    });

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

  test("workout graph tombstones stay in fetchChanges", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertExercise, { record: exerciseRecord() });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord(),
    });
    await t.mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord(),
    });
    await t.mutation(api.sync.upsertLoggedSet, {
      record: loggedSetRecord(),
    });

    await t.mutation(api.sync.tombstone, {
      entityKind: "workoutSessions",
      clientId: "session-1",
      deletedAt: 3,
    });
    await t.mutation(api.sync.tombstone, {
      entityKind: "loggedExercises",
      clientId: "logged-exercise-1",
      deletedAt: 4,
    });
    await t.mutation(api.sync.tombstone, {
      entityKind: "loggedSets",
      clientId: "logged-set-1",
      deletedAt: 5,
    });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.workoutSessions).toHaveLength(1);
    expect(changes.loggedExercises).toHaveLength(1);
    expect(changes.loggedSets).toHaveLength(1);
    expect(changes.workoutSessions[0]).toMatchObject({
      clientId: "session-1",
      deletedAt: 3,
      updatedAt: 3,
    });
    expect(changes.loggedExercises[0]).toMatchObject({
      clientId: "logged-exercise-1",
      deletedAt: 4,
      updatedAt: 4,
    });
    expect(changes.loggedSets[0]).toMatchObject({
      clientId: "logged-set-1",
      deletedAt: 5,
      updatedAt: 5,
    });
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
  test("full workout graph round-trips through fetchChanges", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord(),
    });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord({
        title: "Upper Strength",
        notes: "Felt strong",
        referenceNotes: "Repeat next week",
        updatedAt: 3,
      }),
    });
    await t.mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord({
        notes: "Smooth",
        referenceNotes: "Add five pounds",
        sourceLoggedExerciseID: "source-logged-exercise-1",
        updatedAt: 4,
      }),
    });
    await t.mutation(api.sync.upsertLoggedSet, {
      record: loggedSetRecord({
        weight: 185,
        reps: 5,
        rpe: 8.5,
        completedAt: 2,
        notes: "Clean reps",
        updatedAt: 5,
      }),
    });

    const changes = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
    });

    expect(changes.exercises).toHaveLength(1);
    expect(changes.workoutSessions).toHaveLength(1);
    expect(changes.loggedExercises).toHaveLength(1);
    expect(changes.loggedSets).toHaveLength(1);
    expect(changes.exercises[0]).toMatchObject(exerciseRecord());
    expect(changes.workoutSessions[0]).toMatchObject({
      clientId: "session-1",
      title: "Upper Strength",
      statusRaw: "completed",
      sourceRaw: "blank",
      notes: "Felt strong",
      referenceNotes: "Repeat next week",
    });
    expect(changes.loggedExercises[0]).toMatchObject({
      clientId: "logged-exercise-1",
      sessionClientId: "session-1",
      exerciseClientId: "exercise-1",
      orderIndex: 0,
      exerciseSnapshotName: "Bench Press",
      exerciseSnapshotEquipmentRaw: "barbell",
      exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
      hasSnapshotMetadata: true,
      notes: "Smooth",
      referenceNotes: "Add five pounds",
      sourceLoggedExerciseID: "source-logged-exercise-1",
    });
    expect(changes.loggedSets[0]).toMatchObject({
      clientId: "logged-set-1",
      loggedExerciseClientId: "logged-exercise-1",
      orderIndex: 0,
      weight: 185,
      reps: 5,
      rpe: 8.5,
      kindRaw: "working",
      isCompleted: true,
      completedAt: 2,
      notes: "Clean reps",
    });
  });

  test("settings exercise changes do not return workout history pages", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertUserSettings, {
      record: userSettingsRecord({ updatedAt: 2 }),
    });
    await t.mutation(api.sync.upsertExercise, {
      record: exerciseRecord({ updatedAt: 3 }),
    });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord({ updatedAt: 4 }),
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

  test("workout graph cursors page independently", async () => {
    const t = testDb().withIdentity(userA);

    await t.mutation(api.sync.upsertExercise, { record: exerciseRecord() });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord({ clientId: "session-1", updatedAt: 2 }),
    });
    await t.mutation(api.sync.upsertWorkoutSession, {
      record: workoutSessionRecord({ clientId: "session-2", updatedAt: 3 }),
    });
    await t.mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord({
        clientId: "logged-exercise-1",
        sessionClientId: "session-1",
        updatedAt: 4,
      }),
    });
    await t.mutation(api.sync.upsertLoggedExercise, {
      record: loggedExerciseRecord({
        clientId: "logged-exercise-2",
        sessionClientId: "session-2",
        updatedAt: 5,
      }),
    });
    await t.mutation(api.sync.upsertLoggedSet, {
      record: loggedSetRecord({
        clientId: "logged-set-1",
        loggedExerciseClientId: "logged-exercise-1",
        updatedAt: 6,
      }),
    });
    await t.mutation(api.sync.upsertLoggedSet, {
      record: loggedSetRecord({
        clientId: "logged-set-2",
        loggedExerciseClientId: "logged-exercise-2",
        updatedAt: 7,
      }),
    });

    const firstPage = await t.query(api.sync.fetchChanges, {
      cursors: zeroCursors,
      limit: 1,
    });
    const secondPage = await t.query(api.sync.fetchChanges, {
      cursors: firstPage.cursors,
      limit: 1,
    });

    expect(firstPage.workoutSessions.map((record) => record.clientId)).toEqual([
      "session-1",
    ]);
    expect(firstPage.loggedExercises.map((record) => record.clientId)).toEqual([
      "logged-exercise-1",
    ]);
    expect(firstPage.loggedSets.map((record) => record.clientId)).toEqual([
      "logged-set-1",
    ]);
    expect(firstPage.hasMore.workoutSessions).toBe(true);
    expect(firstPage.hasMore.loggedExercises).toBe(true);
    expect(firstPage.hasMore.loggedSets).toBe(true);

    expect(secondPage.workoutSessions.map((record) => record.clientId)).toEqual([
      "session-2",
    ]);
    expect(secondPage.loggedExercises.map((record) => record.clientId)).toEqual([
      "logged-exercise-2",
    ]);
    expect(secondPage.loggedSets.map((record) => record.clientId)).toEqual([
      "logged-set-2",
    ]);
    expect(secondPage.hasMore.workoutSessions).toBe(false);
    expect(secondPage.hasMore.loggedExercises).toBe(false);
    expect(secondPage.hasMore.loggedSets).toBe(false);
  });
});
