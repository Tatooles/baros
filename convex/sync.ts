import { v, type Infer } from "convex/values";
import { internal } from "./_generated/api";
import {
  action,
  internalMutation,
  mutation,
  query,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
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

type AccountDataDeletionResult = {
  status: "deleted";
  deletedCounts: {
    loggedSets: number;
    loggedExercises: number;
    workoutSessions: number;
    exercises: number;
    userSettings: number;
  };
};

type AccountDeletionTable =
  | "loggedSets"
  | "loggedExercises"
  | "workoutSessions"
  | "exercises"
  | "userSettings";

const accountDeletionTableValidator = v.union(
  v.literal("loggedSets"),
  v.literal("loggedExercises"),
  v.literal("workoutSessions"),
  v.literal("exercises"),
  v.literal("userSettings"),
);

const accountDeletionTableOrder: AccountDeletionTable[] = [
  "loggedSets",
  "loggedExercises",
  "workoutSessions",
  "exercises",
  "userSettings",
];

type AccountDataDeletionTableBatchResult = {
  tableName: AccountDeletionTable;
  deletedCount: number;
  hasMore: boolean;
};

type ChangePage<TRecord extends { serverUpdatedAt: number }> = {
  records: TRecord[];
  hasMore: boolean;
};

const defaultFetchLimit = 100;
const maxFetchLimit = 500;
const accountDeletionBatchSize = 1000;
const maxAccountDeletionPassesPerAction = 100;
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

export function accountDeletionPassLimitReached(
  passIndex: number,
): boolean {
  return passIndex >= maxAccountDeletionPassesPerAction;
}

export async function deleteAccountDataWithBatches(
  runBatch: (
    tableName: AccountDeletionTable,
  ) => Promise<AccountDataDeletionTableBatchResult>,
  maxPasses = maxAccountDeletionPassesPerAction,
): Promise<AccountDataDeletionResult> {
  const deletedCounts: AccountDataDeletionResult["deletedCounts"] = {
    loggedSets: 0,
    loggedExercises: 0,
    workoutSessions: 0,
    exercises: 0,
    userSettings: 0,
  };

  for (let passIndex = 0; passIndex < maxPasses; passIndex++) {
    let verifiedEmpty = true;

    for (const tableName of accountDeletionTableOrder) {
      const result = await runBatch(tableName);
      deletedCounts[result.tableName] += result.deletedCount;

      if (result.deletedCount > 0 || result.hasMore) {
        verifiedEmpty = false;
      }
    }

    if (verifiedEmpty) {
      return {
        status: "deleted",
        deletedCounts,
      };
    }
  }

  throw new Error("Account data deletion did not finish. Retry account deletion.");
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
    sourceLoggedExerciseID: record.sourceLoggedExerciseID ?? null,
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
    sourceLoggedExerciseID: record.sourceLoggedExerciseID ?? null,
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
    sourceLoggedExerciseID:
      record.sourceLoggedExerciseID ?? existing.sourceLoggedExerciseID ?? null,
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

async function accountDeletionMarkerForOwner(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<Doc<"accountDeletionMarkers"> | null> {
  const markers = await ctx.db
    .query("accountDeletionMarkers")
    .withIndex("by_ownerTokenIdentifier", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
    )
    .take(1);

  return markers[0] ?? null;
}

async function assertAccountDeletionNotStarted(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<void> {
  const marker = await accountDeletionMarkerForOwner(ctx, ownerTokenIdentifier);
  if (marker !== null) {
    throw new Error("Account deletion is in progress");
  }
}

async function markAccountDeletionStarted(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  cancellationToken: string,
): Promise<void> {
  const existing = await accountDeletionMarkerForOwner(ctx, ownerTokenIdentifier);
  if (existing !== null) {
    if (existing.cancellationToken !== cancellationToken) {
      throw new Error("Account deletion is already in progress on another client");
    }
    return;
  }

  await ctx.db.insert("accountDeletionMarkers", {
    ownerTokenIdentifier,
    cancellationToken,
    createdAt: Date.now(),
  });
}

async function clearAccountDeletionMarker(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  cancellationToken: string,
): Promise<void> {
  const existing = await accountDeletionMarkerForOwner(ctx, ownerTokenIdentifier);
  if (existing === null) {
    return;
  }

  if (existing.cancellationToken !== cancellationToken) {
    throw new Error("Account deletion is already in progress on another client");
  }

  await ctx.db.delete(existing._id);
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

async function findWorkoutSessionByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
): Promise<Doc<"workoutSessions"> | null> {
  return await ctx.db
    .query("workoutSessions")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();
}

async function findExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
): Promise<Doc<"exercises"> | null> {
  return await ctx.db
    .query("exercises")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();
}

async function findLoggedExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
): Promise<Doc<"loggedExercises"> | null> {
  return await ctx.db
    .query("loggedExercises")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();
}

async function assertLoggedExerciseParentExists(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: LoggedExercisePayload,
): Promise<void> {
  if (record.deletedAt !== null) {
    return;
  }

  const session = await findWorkoutSessionByClientId(
    ctx,
    ownerTokenIdentifier,
    record.sessionClientId,
  );
  if (session === null || session.deletedAt !== null) {
    throw new Error(
      "Cannot upsert active logged exercise without its workout session parent.",
    );
  }

  if (record.exerciseClientId !== null) {
    const exercise = await findExerciseByClientId(
      ctx,
      ownerTokenIdentifier,
      record.exerciseClientId,
    );
    if (exercise === null || exercise.deletedAt !== null) {
      throw new Error(
        "Cannot upsert active logged exercise with a missing exercise reference.",
      );
    }
  }
}

async function assertLoggedSetParentExists(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: LoggedSetPayload,
): Promise<void> {
  if (record.deletedAt !== null) {
    return;
  }

  const loggedExercise = await findLoggedExerciseByClientId(
    ctx,
    ownerTokenIdentifier,
    record.loggedExerciseClientId,
  );
  if (loggedExercise === null || loggedExercise.deletedAt !== null) {
    throw new Error(
      "Cannot upsert active logged set without its logged exercise parent.",
    );
  }

  const session = await findWorkoutSessionByClientId(
    ctx,
    ownerTokenIdentifier,
    loggedExercise.sessionClientId,
  );
  if (session === null || session.deletedAt !== null) {
    throw new Error(
      "Cannot upsert active logged set without its logged exercise parent.",
    );
  }
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

  await assertLoggedExerciseParentExists(ctx, ownerTokenIdentifier, record);

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

  await assertLoggedSetParentExists(ctx, ownerTokenIdentifier, record);

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

async function deleteRowsForOwnerBatch<TRecord extends { _id: string }>(
  fetchBatch: () => Promise<TRecord[]>,
  deleteRow: (row: TRecord) => Promise<void>,
): Promise<{ deletedCount: number; hasMore: boolean }> {
  const rows = await fetchBatch();
  const rowsToDelete = rows.slice(0, accountDeletionBatchSize);

  for (const row of rowsToDelete) {
    await deleteRow(row);
  }

  return {
    deletedCount: rowsToDelete.length,
    hasMore: rows.length > accountDeletionBatchSize,
  };
}

async function deleteUserSettingsForOwnerBatch(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<{ deletedCount: number; hasMore: boolean }> {
  return await deleteRowsForOwnerBatch(
    () =>
      ctx.db
        .query("userSettings")
        .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
          q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
        )
        .take(accountDeletionBatchSize + 1),
    (row) => ctx.db.delete(row._id),
  );
}

async function deleteExercisesForOwnerBatch(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<{ deletedCount: number; hasMore: boolean }> {
  return await deleteRowsForOwnerBatch(
    () =>
      ctx.db
        .query("exercises")
        .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
          q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
        )
        .take(accountDeletionBatchSize + 1),
    (row) => ctx.db.delete(row._id),
  );
}

async function deleteWorkoutSessionsForOwnerBatch(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<{ deletedCount: number; hasMore: boolean }> {
  return await deleteRowsForOwnerBatch(
    () =>
      ctx.db
        .query("workoutSessions")
        .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
          q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
        )
        .take(accountDeletionBatchSize + 1),
    (row) => ctx.db.delete(row._id),
  );
}

async function deleteLoggedExercisesForOwnerBatch(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<{ deletedCount: number; hasMore: boolean }> {
  return await deleteRowsForOwnerBatch(
    () =>
      ctx.db
        .query("loggedExercises")
        .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
          q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
        )
        .take(accountDeletionBatchSize + 1),
    (row) => ctx.db.delete(row._id),
  );
}

async function deleteLoggedSetsForOwnerBatch(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<{ deletedCount: number; hasMore: boolean }> {
  return await deleteRowsForOwnerBatch(
    () =>
      ctx.db
        .query("loggedSets")
        .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
          q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
        )
        .take(accountDeletionBatchSize + 1),
    (row) => ctx.db.delete(row._id),
  );
}

export const upsertUserSettings = mutation({
  args: { record: userSettingsPayloadValidator },
  handler: async (ctx, args) => {
    assertFinitePayloadNumbers(args.record);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    await assertAccountDeletionNotStarted(ctx, ownerTokenIdentifier);
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
    await assertAccountDeletionNotStarted(ctx, ownerTokenIdentifier);
    return await upsertExerciseByClientId(ctx, ownerTokenIdentifier, args.record);
  },
});

export const upsertWorkoutSession = mutation({
  args: { record: workoutSessionPayloadValidator },
  handler: async (ctx, args) => {
    assertFinitePayloadNumbers(args.record);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    await assertAccountDeletionNotStarted(ctx, ownerTokenIdentifier);
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
    await assertAccountDeletionNotStarted(ctx, ownerTokenIdentifier);
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
    await assertAccountDeletionNotStarted(ctx, ownerTokenIdentifier);
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
    await assertAccountDeletionNotStarted(ctx, ownerTokenIdentifier);

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

export const startAccountDeletion = internalMutation({
  args: {
    ownerTokenIdentifier: v.string(),
    cancellationToken: v.string(),
  },
  handler: async (ctx, args) => {
    await markAccountDeletionStarted(
      ctx,
      args.ownerTokenIdentifier,
      args.cancellationToken,
    );
  },
});

export const clearAccountDeletion = internalMutation({
  args: {
    ownerTokenIdentifier: v.string(),
    cancellationToken: v.string(),
  },
  handler: async (ctx, args) => {
    await clearAccountDeletionMarker(
      ctx,
      args.ownerTokenIdentifier,
      args.cancellationToken,
    );
  },
});

export const deleteAccountDataBatch = internalMutation({
  args: {
    ownerTokenIdentifier: v.string(),
    tableName: accountDeletionTableValidator,
  },
  handler: async (ctx, args): Promise<AccountDataDeletionTableBatchResult> => {
    switch (args.tableName) {
      case "loggedSets": {
        const result = await deleteLoggedSetsForOwnerBatch(
          ctx,
          args.ownerTokenIdentifier,
        );
        return { tableName: args.tableName, ...result };
      }
      case "loggedExercises": {
        const result = await deleteLoggedExercisesForOwnerBatch(
          ctx,
          args.ownerTokenIdentifier,
        );
        return { tableName: args.tableName, ...result };
      }
      case "workoutSessions": {
        const result = await deleteWorkoutSessionsForOwnerBatch(
          ctx,
          args.ownerTokenIdentifier,
        );
        return { tableName: args.tableName, ...result };
      }
      case "exercises": {
        const result = await deleteExercisesForOwnerBatch(
          ctx,
          args.ownerTokenIdentifier,
        );
        return { tableName: args.tableName, ...result };
      }
      case "userSettings": {
        const result = await deleteUserSettingsForOwnerBatch(
          ctx,
          args.ownerTokenIdentifier,
        );
        return { tableName: args.tableName, ...result };
      }
    }
  },
});

export const deleteAccountData = action({
  args: {
    cancellationToken: v.string(),
  },
  handler: async (ctx, args): Promise<AccountDataDeletionResult> => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) {
      throw new Error("Not authenticated");
    }

    const ownerTokenIdentifier = identity.tokenIdentifier;

    return await deleteAccountDataForOwner(
      async () => {
        await ctx.runMutation(internal.sync.startAccountDeletion, {
          ownerTokenIdentifier,
          cancellationToken: args.cancellationToken,
        });
      },
      async (tableName) => {
        return await ctx.runMutation(internal.sync.deleteAccountDataBatch, {
          ownerTokenIdentifier,
          tableName,
        });
      },
    );
  },
});

export const cancelAccountDeletion = action({
  args: {
    cancellationToken: v.string(),
  },
  handler: async (ctx, args): Promise<{ status: "cancelled" }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) {
      throw new Error("Not authenticated");
    }

    await ctx.runMutation(internal.sync.clearAccountDeletion, {
      ownerTokenIdentifier: identity.tokenIdentifier,
      cancellationToken: args.cancellationToken,
    });

    return { status: "cancelled" };
  },
});

export async function deleteAccountDataForOwner(
  startDeletion: () => Promise<void>,
  runBatch: (
    tableName: AccountDeletionTable,
  ) => Promise<AccountDataDeletionTableBatchResult>,
): Promise<AccountDataDeletionResult> {
  await startDeletion();

  return await deleteAccountDataWithBatches(runBatch);
}

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
