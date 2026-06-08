import { v, type Infer } from "convex/values";
import { mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import { type Doc } from "./_generated/dataModel";
import { requireOwnerTokenIdentifier } from "./lib/auth";
import {
  entityKindValidator,
  exercisePayloadValidator,
  loggedExercisePayloadValidator,
  loggedSetPayloadValidator,
  userSettingsPayloadValidator,
  workoutSessionPayloadValidator,
} from "./sync/validators";

type UserSettingsPayload = Infer<typeof userSettingsPayloadValidator>;
type ExercisePayload = Infer<typeof exercisePayloadValidator>;
type WorkoutSessionPayload = Infer<typeof workoutSessionPayloadValidator>;
type LoggedExercisePayload = Infer<typeof loggedExercisePayloadValidator>;
type LoggedSetPayload = Infer<typeof loggedSetPayloadValidator>;
type NormalizedExercisePayload = ExercisePayload & {
  primaryMuscleGroupRaw: string;
};
type NormalizedExerciseRecord = Doc<"exercises"> & {
  primaryMuscleGroupRaw: string;
};
type NormalizedLoggedExerciseRecord = Doc<"loggedExercises"> & {
  exerciseSnapshotEquipmentRaw: string;
  exerciseSnapshotPrimaryMuscleGroupRaw: string;
  hasSnapshotMetadata: boolean;
};
type NormalizedLoggedExercisePayload = LoggedExercisePayload & {
  exerciseSnapshotEquipmentRaw: string;
  exerciseSnapshotPrimaryMuscleGroupRaw: string;
  hasSnapshotMetadata: boolean;
};

type UpsertResult =
  | { status: "inserted"; serverUpdatedAt: number }
  | { status: "updated"; serverUpdatedAt: number }
  | { status: "ignored_stale"; serverUpdatedAt: number };

type TombstoneResult =
  | { status: "tombstoned"; serverUpdatedAt: number }
  | { status: "ignored_stale"; serverUpdatedAt: number }
  | { status: "missing" };

type ChangePage<TRecord extends { serverUpdatedAt: number }> = {
  records: TRecord[];
  hasMore: boolean;
};

const defaultFetchLimit = 100;
const maxFetchLimit = 500;
const defaultPrimaryMuscleGroupRaw = "other";
const defaultExerciseSnapshotEquipmentRaw = "other";
const defaultExerciseSnapshotPrimaryMuscleGroupRaw = "other";
const defaultHasSnapshotMetadata = false;
const syncCursorValidator = v.object({
  userSettings: v.number(),
  exercises: v.number(),
  workoutSessions: v.number(),
  loggedExercises: v.number(),
  loggedSets: v.number(),
});

function assertFiniteNumber(value: number, fieldName: string): void {
  if (!Number.isFinite(value)) {
    throw new Error(`${fieldName} must be a finite number`);
  }
}

function assertFinitePayloadNumbers(record: Record<string, unknown>): void {
  for (const [fieldName, value] of Object.entries(record)) {
    if (typeof value === "number") {
      assertFiniteNumber(value, fieldName);
    }
  }
}

function assertFiniteCursors(cursors: Record<string, number>): void {
  for (const [tableName, cursor] of Object.entries(cursors)) {
    assertFiniteNumber(cursor, `${tableName} cursor`);
  }
}

function normalizeFetchLimit(limit: number | undefined): number {
  if (limit === undefined) {
    return defaultFetchLimit;
  }

  assertFiniteNumber(limit, "limit");
  return Math.max(1, Math.min(maxFetchLimit, Math.floor(limit)));
}

function nextCursorFromRecords<TRecord extends { serverUpdatedAt: number }>(
  records: TRecord[],
  currentCursor: number,
): number {
  return records.reduce(
    (cursor, record) => Math.max(cursor, record.serverUpdatedAt),
    currentCursor,
  );
}

function pageFromOverfetch<TRecord extends { serverUpdatedAt: number }>(
  records: TRecord[],
  limit: number,
): ChangePage<TRecord> {
  return {
    records: records.slice(0, limit),
    hasMore: records.length > limit,
  };
}

function isStale(
  existing: { updatedAt: number },
  payload: { updatedAt: number },
): boolean {
  return existing.updatedAt >= payload.updatedAt;
}

function withServerFields<TRecord extends { clientId: string }>(
  record: TRecord,
  ownerTokenIdentifier: string,
  serverUpdatedAt: number,
): TRecord & { ownerTokenIdentifier: string; serverUpdatedAt: number } {
  return {
    ...record,
    ownerTokenIdentifier,
    serverUpdatedAt,
  };
}

function normalizeExercisePayload(record: ExercisePayload): NormalizedExercisePayload {
  return {
    ...record,
    primaryMuscleGroupRaw:
      record.primaryMuscleGroupRaw ?? defaultPrimaryMuscleGroupRaw,
  };
}

function normalizeExerciseRecord(record: Doc<"exercises">): NormalizedExerciseRecord {
  return {
    ...record,
    primaryMuscleGroupRaw:
      record.primaryMuscleGroupRaw ?? defaultPrimaryMuscleGroupRaw,
  };
}

function normalizeLoggedExercisePayload(
  record: LoggedExercisePayload,
): NormalizedLoggedExercisePayload {
  return {
    ...record,
    exerciseSnapshotEquipmentRaw:
      record.exerciseSnapshotEquipmentRaw ?? defaultExerciseSnapshotEquipmentRaw,
    exerciseSnapshotPrimaryMuscleGroupRaw:
      record.exerciseSnapshotPrimaryMuscleGroupRaw ??
      defaultExerciseSnapshotPrimaryMuscleGroupRaw,
    hasSnapshotMetadata:
      record.hasSnapshotMetadata ?? defaultHasSnapshotMetadata,
  };
}

function normalizeLoggedExerciseRecord(
  record: Doc<"loggedExercises">,
): NormalizedLoggedExerciseRecord {
  return {
    ...record,
    exerciseSnapshotEquipmentRaw:
      record.exerciseSnapshotEquipmentRaw ?? defaultExerciseSnapshotEquipmentRaw,
    exerciseSnapshotPrimaryMuscleGroupRaw:
      record.exerciseSnapshotPrimaryMuscleGroupRaw ??
      defaultExerciseSnapshotPrimaryMuscleGroupRaw,
    hasSnapshotMetadata:
      record.hasSnapshotMetadata ?? defaultHasSnapshotMetadata,
  };
}

function normalizeLoggedExerciseUpdatePayload(
  record: LoggedExercisePayload,
  existing: Doc<"loggedExercises">,
): NormalizedLoggedExercisePayload {
  return {
    ...record,
    exerciseSnapshotEquipmentRaw:
      record.exerciseSnapshotEquipmentRaw ??
      existing.exerciseSnapshotEquipmentRaw ??
      defaultExerciseSnapshotEquipmentRaw,
    exerciseSnapshotPrimaryMuscleGroupRaw:
      record.exerciseSnapshotPrimaryMuscleGroupRaw ??
      existing.exerciseSnapshotPrimaryMuscleGroupRaw ??
      defaultExerciseSnapshotPrimaryMuscleGroupRaw,
    hasSnapshotMetadata:
      record.hasSnapshotMetadata ??
      existing.hasSnapshotMetadata ??
      defaultHasSnapshotMetadata,
  };
}

async function latestUserSettingsServerUpdatedAt(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<number> {
  const latest = await ctx.db
    .query("userSettings")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
    )
    .order("desc")
    .take(1);

  return latest[0]?.serverUpdatedAt ?? 0;
}

async function latestExerciseServerUpdatedAt(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<number> {
  const latest = await ctx.db
    .query("exercises")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
    )
    .order("desc")
    .take(1);

  return latest[0]?.serverUpdatedAt ?? 0;
}

async function latestWorkoutSessionServerUpdatedAt(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<number> {
  const latest = await ctx.db
    .query("workoutSessions")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
    )
    .order("desc")
    .take(1);

  return latest[0]?.serverUpdatedAt ?? 0;
}

async function latestLoggedExerciseServerUpdatedAt(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<number> {
  const latest = await ctx.db
    .query("loggedExercises")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
    )
    .order("desc")
    .take(1);

  return latest[0]?.serverUpdatedAt ?? 0;
}

async function latestLoggedSetServerUpdatedAt(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<number> {
  const latest = await ctx.db
    .query("loggedSets")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
    )
    .order("desc")
    .take(1);

  return latest[0]?.serverUpdatedAt ?? 0;
}

async function nextServerUpdatedAt(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<number> {
  const latestValues = await Promise.all([
    latestUserSettingsServerUpdatedAt(ctx, ownerTokenIdentifier),
    latestExerciseServerUpdatedAt(ctx, ownerTokenIdentifier),
    latestWorkoutSessionServerUpdatedAt(ctx, ownerTokenIdentifier),
    latestLoggedExerciseServerUpdatedAt(ctx, ownerTokenIdentifier),
    latestLoggedSetServerUpdatedAt(ctx, ownerTokenIdentifier),
  ]);
  const maxExisting = Math.max(0, ...latestValues);

  return Math.max(Date.now(), maxExisting + 1);
}

async function upsertUserSettingsByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: UserSettingsPayload,
): Promise<UpsertResult> {
  const existing = await ctx.db
    .query("userSettings")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", record.clientId),
    )
    .unique();

  if (existing !== null && isStale(existing, record)) {
    return {
      status: "ignored_stale",
      serverUpdatedAt: existing.serverUpdatedAt,
    };
  }

  const serverUpdatedAt = await nextServerUpdatedAt(ctx, ownerTokenIdentifier);
  const nextRecord = withServerFields(record, ownerTokenIdentifier, serverUpdatedAt);

  if (existing === null) {
    await ctx.db.insert("userSettings", nextRecord);
    return { status: "inserted", serverUpdatedAt };
  }

  await ctx.db.patch(existing._id, nextRecord);
  return { status: "updated", serverUpdatedAt };
}

async function upsertExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: ExercisePayload,
): Promise<UpsertResult> {
  const existing = await ctx.db
    .query("exercises")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", record.clientId),
    )
    .unique();

  if (existing !== null && isStale(existing, record)) {
    return {
      status: "ignored_stale",
      serverUpdatedAt: existing.serverUpdatedAt,
    };
  }

  const serverUpdatedAt = await nextServerUpdatedAt(ctx, ownerTokenIdentifier);
  const normalizedRecord =
    existing === null
      ? normalizeExercisePayload(record)
      : {
          ...record,
          primaryMuscleGroupRaw:
            record.primaryMuscleGroupRaw ??
            existing.primaryMuscleGroupRaw ??
            defaultPrimaryMuscleGroupRaw,
        };
  const nextRecord = withServerFields(
    normalizedRecord,
    ownerTokenIdentifier,
    serverUpdatedAt,
  );

  if (existing === null) {
    await ctx.db.insert("exercises", nextRecord);
    return { status: "inserted", serverUpdatedAt };
  }

  await ctx.db.patch(existing._id, nextRecord);
  return { status: "updated", serverUpdatedAt };
}

async function upsertWorkoutSessionByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: WorkoutSessionPayload,
): Promise<UpsertResult> {
  const existing = await ctx.db
    .query("workoutSessions")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", record.clientId),
    )
    .unique();

  if (existing !== null && isStale(existing, record)) {
    return {
      status: "ignored_stale",
      serverUpdatedAt: existing.serverUpdatedAt,
    };
  }

  const serverUpdatedAt = await nextServerUpdatedAt(ctx, ownerTokenIdentifier);
  const nextRecord = withServerFields(record, ownerTokenIdentifier, serverUpdatedAt);

  if (existing === null) {
    await ctx.db.insert("workoutSessions", nextRecord);
    return { status: "inserted", serverUpdatedAt };
  }

  await ctx.db.patch(existing._id, nextRecord);
  return { status: "updated", serverUpdatedAt };
}

async function upsertLoggedExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: LoggedExercisePayload,
): Promise<UpsertResult> {
  const existing = await ctx.db
    .query("loggedExercises")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", record.clientId),
    )
    .unique();

  if (existing !== null && isStale(existing, record)) {
    return {
      status: "ignored_stale",
      serverUpdatedAt: existing.serverUpdatedAt,
    };
  }

  const serverUpdatedAt = await nextServerUpdatedAt(ctx, ownerTokenIdentifier);
  const normalizedRecord =
    existing === null
      ? normalizeLoggedExercisePayload(record)
      : normalizeLoggedExerciseUpdatePayload(record, existing);
  const nextRecord = withServerFields(
    normalizedRecord,
    ownerTokenIdentifier,
    serverUpdatedAt,
  );

  if (existing === null) {
    await ctx.db.insert("loggedExercises", nextRecord);
    return { status: "inserted", serverUpdatedAt };
  }

  await ctx.db.patch(existing._id, nextRecord);
  return { status: "updated", serverUpdatedAt };
}

async function upsertLoggedSetByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: LoggedSetPayload,
): Promise<UpsertResult> {
  const existing = await ctx.db
    .query("loggedSets")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", record.clientId),
    )
    .unique();

  if (existing !== null && isStale(existing, record)) {
    return {
      status: "ignored_stale",
      serverUpdatedAt: existing.serverUpdatedAt,
    };
  }

  const serverUpdatedAt = await nextServerUpdatedAt(ctx, ownerTokenIdentifier);
  const nextRecord = withServerFields(record, ownerTokenIdentifier, serverUpdatedAt);

  if (existing === null) {
    await ctx.db.insert("loggedSets", nextRecord);
    return { status: "inserted", serverUpdatedAt };
  }

  await ctx.db.patch(existing._id, nextRecord);
  return { status: "updated", serverUpdatedAt };
}

async function tombstoneExisting(
  ctx: MutationCtx,
  existing: Doc<"userSettings">,
  ownerTokenIdentifier: string,
  deletedAt: number,
): Promise<TombstoneResult>;
async function tombstoneExisting(
  ctx: MutationCtx,
  existing: Doc<"exercises">,
  ownerTokenIdentifier: string,
  deletedAt: number,
): Promise<TombstoneResult>;
async function tombstoneExisting(
  ctx: MutationCtx,
  existing: Doc<"workoutSessions">,
  ownerTokenIdentifier: string,
  deletedAt: number,
): Promise<TombstoneResult>;
async function tombstoneExisting(
  ctx: MutationCtx,
  existing: Doc<"loggedExercises">,
  ownerTokenIdentifier: string,
  deletedAt: number,
): Promise<TombstoneResult>;
async function tombstoneExisting(
  ctx: MutationCtx,
  existing: Doc<"loggedSets">,
  ownerTokenIdentifier: string,
  deletedAt: number,
): Promise<TombstoneResult>;
async function tombstoneExisting(
  ctx: MutationCtx,
  existing:
    | Doc<"userSettings">
    | Doc<"exercises">
    | Doc<"workoutSessions">
    | Doc<"loggedExercises">
    | Doc<"loggedSets">,
  ownerTokenIdentifier: string,
  deletedAt: number,
): Promise<TombstoneResult> {
  if (existing.updatedAt >= deletedAt) {
    return {
      status: "ignored_stale",
      serverUpdatedAt: existing.serverUpdatedAt,
    };
  }

  const serverUpdatedAt = await nextServerUpdatedAt(ctx, ownerTokenIdentifier);
  await ctx.db.patch(existing._id, {
    deletedAt,
    updatedAt: deletedAt,
    serverUpdatedAt,
  });

  return { status: "tombstoned", serverUpdatedAt };
}

async function tombstoneUserSettingsByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
  deletedAt: number,
): Promise<TombstoneResult> {
  const existing = await ctx.db
    .query("userSettings")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();

  if (existing === null) {
    return { status: "missing" };
  }

  return await tombstoneExisting(ctx, existing, ownerTokenIdentifier, deletedAt);
}

async function tombstoneExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
  deletedAt: number,
): Promise<TombstoneResult> {
  const existing = await ctx.db
    .query("exercises")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();

  if (existing === null) {
    return { status: "missing" };
  }

  return await tombstoneExisting(ctx, existing, ownerTokenIdentifier, deletedAt);
}

async function tombstoneWorkoutSessionByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
  deletedAt: number,
): Promise<TombstoneResult> {
  const existing = await ctx.db
    .query("workoutSessions")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();

  if (existing === null) {
    return { status: "missing" };
  }

  return await tombstoneExisting(ctx, existing, ownerTokenIdentifier, deletedAt);
}

async function tombstoneLoggedExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
  deletedAt: number,
): Promise<TombstoneResult> {
  const existing = await ctx.db
    .query("loggedExercises")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();

  if (existing === null) {
    return { status: "missing" };
  }

  return await tombstoneExisting(ctx, existing, ownerTokenIdentifier, deletedAt);
}

async function tombstoneLoggedSetByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
  deletedAt: number,
): Promise<TombstoneResult> {
  const existing = await ctx.db
    .query("loggedSets")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();

  if (existing === null) {
    return { status: "missing" };
  }

  return await tombstoneExisting(ctx, existing, ownerTokenIdentifier, deletedAt);
}

async function fetchUserSettingsChanges(
  ctx: QueryCtx,
  ownerTokenIdentifier: string,
  cursor: number,
  limit: number,
): Promise<ChangePage<Doc<"userSettings">>> {
  const records = await ctx.db
    .query("userSettings")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q
        .eq("ownerTokenIdentifier", ownerTokenIdentifier)
        .gt("serverUpdatedAt", cursor),
    )
    .take(limit + 1);

  return pageFromOverfetch(records, limit);
}

async function fetchExerciseChanges(
  ctx: QueryCtx,
  ownerTokenIdentifier: string,
  cursor: number,
  limit: number,
): Promise<ChangePage<Doc<"exercises">>> {
  const records = await ctx.db
    .query("exercises")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q
        .eq("ownerTokenIdentifier", ownerTokenIdentifier)
        .gt("serverUpdatedAt", cursor),
    )
    .take(limit + 1);

  return pageFromOverfetch(records, limit);
}

async function fetchWorkoutSessionChanges(
  ctx: QueryCtx,
  ownerTokenIdentifier: string,
  cursor: number,
  limit: number,
): Promise<ChangePage<Doc<"workoutSessions">>> {
  const records = await ctx.db
    .query("workoutSessions")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q
        .eq("ownerTokenIdentifier", ownerTokenIdentifier)
        .gt("serverUpdatedAt", cursor),
    )
    .take(limit + 1);

  return pageFromOverfetch(records, limit);
}

async function fetchLoggedExerciseChanges(
  ctx: QueryCtx,
  ownerTokenIdentifier: string,
  cursor: number,
  limit: number,
): Promise<ChangePage<Doc<"loggedExercises">>> {
  const records = await ctx.db
    .query("loggedExercises")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q
        .eq("ownerTokenIdentifier", ownerTokenIdentifier)
        .gt("serverUpdatedAt", cursor),
    )
    .take(limit + 1);

  return pageFromOverfetch(records, limit);
}

async function fetchLoggedSetChanges(
  ctx: QueryCtx,
  ownerTokenIdentifier: string,
  cursor: number,
  limit: number,
): Promise<ChangePage<Doc<"loggedSets">>> {
  const records = await ctx.db
    .query("loggedSets")
    .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
      q
        .eq("ownerTokenIdentifier", ownerTokenIdentifier)
        .gt("serverUpdatedAt", cursor),
    )
    .take(limit + 1);

  return pageFromOverfetch(records, limit);
}

export const upsertUserSettings = mutation({
  args: { record: userSettingsPayloadValidator },
  handler: async (ctx, args) => {
    assertFinitePayloadNumbers(args.record);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    return await upsertUserSettingsByClientId(
      ctx,
      ownerTokenIdentifier,
      args.record,
    );
  },
});

export const upsertExercise = mutation({
  args: { record: exercisePayloadValidator },
  handler: async (ctx, args) => {
    assertFinitePayloadNumbers(args.record);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    return await upsertExerciseByClientId(ctx, ownerTokenIdentifier, args.record);
  },
});

export const upsertWorkoutSession = mutation({
  args: { record: workoutSessionPayloadValidator },
  handler: async (ctx, args) => {
    assertFinitePayloadNumbers(args.record);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    return await upsertWorkoutSessionByClientId(
      ctx,
      ownerTokenIdentifier,
      args.record,
    );
  },
});

export const upsertLoggedExercise = mutation({
  args: { record: loggedExercisePayloadValidator },
  handler: async (ctx, args) => {
    assertFinitePayloadNumbers(args.record);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    return await upsertLoggedExerciseByClientId(
      ctx,
      ownerTokenIdentifier,
      args.record,
    );
  },
});

export const upsertLoggedSet = mutation({
  args: { record: loggedSetPayloadValidator },
  handler: async (ctx, args) => {
    assertFinitePayloadNumbers(args.record);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    return await upsertLoggedSetByClientId(ctx, ownerTokenIdentifier, args.record);
  },
});

export const tombstone = mutation({
  args: {
    entityKind: entityKindValidator,
    clientId: v.string(),
    deletedAt: v.number(),
  },
  handler: async (ctx, args) => {
    assertFiniteNumber(args.deletedAt, "deletedAt");
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);

    switch (args.entityKind) {
      case "userSettings":
        return await tombstoneUserSettingsByClientId(
          ctx,
          ownerTokenIdentifier,
          args.clientId,
          args.deletedAt,
        );
      case "exercises":
        return await tombstoneExerciseByClientId(
          ctx,
          ownerTokenIdentifier,
          args.clientId,
          args.deletedAt,
        );
      case "workoutSessions":
        return await tombstoneWorkoutSessionByClientId(
          ctx,
          ownerTokenIdentifier,
          args.clientId,
          args.deletedAt,
        );
      case "loggedExercises":
        return await tombstoneLoggedExerciseByClientId(
          ctx,
          ownerTokenIdentifier,
          args.clientId,
          args.deletedAt,
        );
      case "loggedSets":
        return await tombstoneLoggedSetByClientId(
          ctx,
          ownerTokenIdentifier,
          args.clientId,
          args.deletedAt,
        );
    }
  },
});

export const fetchChanges = query({
  args: {
    cursors: syncCursorValidator,
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    assertFiniteCursors(args.cursors);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    const limit = normalizeFetchLimit(args.limit);

    const userSettingsPage = await fetchUserSettingsChanges(
      ctx,
      ownerTokenIdentifier,
      args.cursors.userSettings,
      limit,
    );
    const exercisePage = await fetchExerciseChanges(
      ctx,
      ownerTokenIdentifier,
      args.cursors.exercises,
      limit,
    );
    const workoutSessionPage = await fetchWorkoutSessionChanges(
      ctx,
      ownerTokenIdentifier,
      args.cursors.workoutSessions,
      limit,
    );
    const loggedExercisePage = await fetchLoggedExerciseChanges(
      ctx,
      ownerTokenIdentifier,
      args.cursors.loggedExercises,
      limit,
    );
    const loggedSetPage = await fetchLoggedSetChanges(
      ctx,
      ownerTokenIdentifier,
      args.cursors.loggedSets,
      limit,
    );
    const userSettings = userSettingsPage.records;
    const exercises = exercisePage.records.map(normalizeExerciseRecord);
    const workoutSessions = workoutSessionPage.records;
    const loggedExercises = loggedExercisePage.records.map(
      normalizeLoggedExerciseRecord,
    );
    const loggedSets = loggedSetPage.records;

    return {
      userSettings,
      exercises,
      workoutSessions,
      loggedExercises,
      loggedSets,
      cursors: {
        userSettings: nextCursorFromRecords(
          userSettings,
          args.cursors.userSettings,
        ),
        exercises: nextCursorFromRecords(exercises, args.cursors.exercises),
        workoutSessions: nextCursorFromRecords(
          workoutSessions,
          args.cursors.workoutSessions,
        ),
        loggedExercises: nextCursorFromRecords(
          loggedExercises,
          args.cursors.loggedExercises,
        ),
        loggedSets: nextCursorFromRecords(loggedSets, args.cursors.loggedSets),
      },
      hasMore: {
        userSettings: userSettingsPage.hasMore,
        exercises: exercisePage.hasMore,
        workoutSessions: workoutSessionPage.hasMore,
        loggedExercises: loggedExercisePage.hasMore,
        loggedSets: loggedSetPage.hasMore,
      },
    };
  },
});

export const fetchSettingsExerciseChanges = query({
  args: {
    cursors: syncCursorValidator,
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    assertFiniteCursors(args.cursors);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    const limit = normalizeFetchLimit(args.limit);

    const userSettingsPage = await fetchUserSettingsChanges(
      ctx,
      ownerTokenIdentifier,
      args.cursors.userSettings,
      limit,
    );
    const exercisePage = await fetchExerciseChanges(
      ctx,
      ownerTokenIdentifier,
      args.cursors.exercises,
      limit,
    );
    const userSettings = userSettingsPage.records;
    const exercises = exercisePage.records.map(normalizeExerciseRecord);

    // This endpoint intentionally narrows the Phase 5 settings/exercises sync.
    // Full workout sync can move the iOS client back to fetchChanges when those
    // tables have a local coordinator that consumes and persists their cursors.
    return {
      userSettings,
      exercises,
      workoutSessions: [],
      loggedExercises: [],
      loggedSets: [],
      cursors: {
        userSettings: nextCursorFromRecords(
          userSettings,
          args.cursors.userSettings,
        ),
        exercises: nextCursorFromRecords(exercises, args.cursors.exercises),
        workoutSessions: args.cursors.workoutSessions,
        loggedExercises: args.cursors.loggedExercises,
        loggedSets: args.cursors.loggedSets,
      },
      hasMore: {
        userSettings: userSettingsPage.hasMore,
        exercises: exercisePage.hasMore,
        workoutSessions: false,
        loggedExercises: false,
        loggedSets: false,
      },
    };
  },
});
