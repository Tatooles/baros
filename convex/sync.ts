import { v, type Infer } from "convex/values";
import { internal } from "./_generated/api";
import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
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
  workoutTemplatePayloadValidator,
} from "./sync/validators";
import {
  cascadedChildVersion,
  decideTombstone,
  decideUpsert,
  syncedContentEquals,
  type UpsertDecision,
} from "./sync/merge";
import { syncError, type SyncErrorCode } from "./sync/errors";

type UserSettingsPayload = Infer<typeof userSettingsPayloadValidator>;
type ExercisePayload = Infer<typeof exercisePayloadValidator>;
type WorkoutSessionPayload = Infer<typeof workoutSessionPayloadValidator>;
type LoggedExercisePayload = Infer<typeof loggedExercisePayloadValidator>;
type LoggedSetPayload = Infer<typeof loggedSetPayloadValidator>;
type WorkoutTemplatePayload = Infer<typeof workoutTemplatePayloadValidator>;
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

// updatedAt is the stored version after the call. Current builds use it as
// the base of their next edit; installed builds ignore it.
type UpsertResult =
  | { status: "inserted"; serverUpdatedAt: number; updatedAt: number }
  | { status: "updated"; serverUpdatedAt: number; updatedAt: number }
  | { status: "ignored_stale"; serverUpdatedAt: number; updatedAt: number };

// Deletes always win, so a tombstone call always ends deleted. Installed
// builds also accept the "ignored_stale" and "missing" statuses older servers
// returned here.
type TombstoneResult = { status: "tombstoned"; serverUpdatedAt: number };

type AccountDataDeletionResult = {
  status: "deleted";
  deletedCounts: {
    loggedSets: number;
    loggedExercises: number;
    workoutSessions: number;
    exercises: number;
    userSettings: number;
    workoutTemplates: number;
  };
};

type AccountDeletionTable =
  | "loggedSets"
  | "loggedExercises"
  | "workoutSessions"
  | "exercises"
  | "userSettings"
  | "workoutTemplates";

const accountDeletionTableValidator = v.union(
  v.literal("loggedSets"),
  v.literal("loggedExercises"),
  v.literal("workoutSessions"),
  v.literal("exercises"),
  v.literal("userSettings"),
  v.literal("workoutTemplates"),
);

const accountDeletionTableOrder = [
  "loggedSets",
  "loggedExercises",
  "workoutSessions",
  "exercises",
  "userSettings",
  "workoutTemplates",
] as const satisfies readonly AccountDeletionTable[];

type AccountDataDeletionTableBatchResult = {
  tableName: AccountDeletionTable;
  deletedCount: number;
  hasMore: boolean;
};

type AccountDeletionMarkerCleanupResult = {
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
const accountDeletionMarkerExpiryMs = 24 * 60 * 60 * 1000;
const accountDeletionMarkerPurgeMs = 30 * 24 * 60 * 60 * 1000;
const accountDeletionMarkerCleanupBatchSize = 100;
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
  // Builds from before templates leave this out and get no template changes.
  workoutTemplates: v.optional(v.number()),
});

type SyncCursors = Infer<typeof syncCursorValidator>;
type FetchChangesArgs = {
  cursors: SyncCursors;
  limit?: number;
};
type SyncReadCtx = QueryCtx | MutationCtx;

function assertFiniteNumber(value: number, fieldName: string): void {
  if (!Number.isFinite(value)) {
    throw syncError("invalidPayload", `${fieldName} must be a finite number`);
  }
}

function assertFinitePayloadNumbers(record: Record<string, unknown>): void {
  for (const [fieldName, value] of Object.entries(record)) {
    if (typeof value === "number") {
      assertFiniteNumber(value, fieldName);
    }
  }
}

function assertFiniteCursors(cursors: Record<string, number | undefined>): void {
  for (const [tableName, cursor] of Object.entries(cursors)) {
    if (cursor !== undefined) {
      assertFiniteNumber(cursor, `${tableName} cursor`);
    }
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
    workoutTemplates: 0,
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
    supersetGroupID: record.supersetGroupID === undefined
      ? existing.supersetGroupID ?? null
      : record.supersetGroupID,
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

async function latestWorkoutTemplateServerUpdatedAt(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<number> {
  const latest = await ctx.db
    .query("workoutTemplates")
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
    latestWorkoutTemplateServerUpdatedAt(ctx, ownerTokenIdentifier),
  ]);
  const maxExisting = Math.max(0, ...latestValues);

  return Math.max(Date.now(), maxExisting + 1);
}

async function accountDeletionMarkerForOwner(
  ctx: QueryCtx,
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
  if (marker === null) {
    return;
  }

  if (marker.phaseRaw === "started" && accountDeletionMarkerExpired(marker)) {
    await ctx.db.delete(marker._id);
    return;
  }

  throw syncError("accountDeletionInProgress", "Account deletion is in progress");
}

async function markAccountDeletionStarted(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  cancellationToken: string,
): Promise<void> {
  const existing = await accountDeletionMarkerForOwner(ctx, ownerTokenIdentifier);
  if (existing === null) {
    await ctx.db.insert("accountDeletionMarkers", {
      ownerTokenIdentifier,
      cancellationToken,
      createdAt: Date.now(),
      phaseRaw: "started",
    });
    return;
  }

  if (existing.phaseRaw === "cloudDataDeleted") {
    return;
  }

  if (!canTakeOverAccountDeletionMarker(existing, cancellationToken)) {
    throw new Error("Account deletion is already in progress on another client");
  }

  await ctx.db.patch(existing._id, {
    cancellationToken,
    createdAt: Date.now(),
    phaseRaw: existing.phaseRaw === "started" ? "started" : "deleting",
  });
}

function accountDeletionMarkerExpired(
  marker: Pick<Doc<"accountDeletionMarkers">, "createdAt">,
): boolean {
  return marker.createdAt < Date.now() - accountDeletionMarkerExpiryMs;
}

function canTakeOverAccountDeletionMarker(
  marker: Doc<"accountDeletionMarkers">,
  cancellationToken: string,
): boolean {
  return (
    marker.cancellationToken === cancellationToken ||
    accountDeletionMarkerExpired(marker)
  );
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

  const ownerRecoverable =
    existing.phaseRaw === "cloudDataDeleted" ||
    (existing.phaseRaw === "started" && accountDeletionMarkerExpired(existing));

  if (existing.cancellationToken !== cancellationToken && !ownerRecoverable) {
    throw new Error("Account deletion is already in progress on another client");
  }

  await ctx.db.delete(existing._id);
}

async function ownerHasAccountData(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<boolean> {
  const results = await Promise.all(
    accountDeletionTableOrder.map((tableName) =>
      ctx.db
        .query(tableName)
        .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
          q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
        )
        .take(1),
    ),
  );

  return results.some((records) => records.length > 0);
}

async function resolveExpiredAccountDeletionMarker(
  ctx: MutationCtx,
  marker: Doc<"accountDeletionMarkers">,
): Promise<boolean> {
  if (
    marker.phaseRaw === "cloudDataDeleted" ||
    marker.phaseRaw === "deletionIncomplete"
  ) {
    return false;
  }

  if (marker.phaseRaw === "started") {
    await ctx.db.delete(marker._id);
    return true;
  }

  if (await ownerHasAccountData(ctx, marker.ownerTokenIdentifier)) {
    await ctx.db.patch(marker._id, { phaseRaw: "deletionIncomplete" });
    return false;
  }

  const completedAt = Date.now();
  await ctx.db.patch(marker._id, {
    phaseRaw: "cloudDataDeleted",
    createdAt: completedAt,
    cloudDataDeletedAt: completedAt,
  });
  return false;
}

const expirableAccountDeletionPhases = ["started", "deleting", undefined] as const;

// Every synced table shares the sync fields and these two index names, so one
// engine handles them all. See sync/merge.ts for the rule itself.
export type SyncTableName = AccountDeletionTable;
type SyncDoc = Doc<SyncTableName>;
type SyncPayload = {
  clientId: string;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};

type ParentState =
  | { kind: "live" }
  | { kind: "deleted"; deletedAt: number }
  | { kind: "missing"; code: SyncErrorCode; message: string };

type UpsertPlan<TRecord extends SyncPayload> = {
  table: SyncTableName;
  record: TRecord;
  insertFields: (record: TRecord) => Record<string, unknown>;
  updateFields: (record: TRecord, existing: SyncDoc) => Record<string, unknown>;
  // Only asked when the upload would keep the record live.
  parentState?: () => Promise<ParentState>;
};

// Allocates the change-feed versions for one mutation. Each written row gets
// its own value, because the per-table cursors page with a strict
// greater-than and would skip rows that share one.
export function serverVersionAllocator(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): () => Promise<number> {
  let next: number | null = null;
  return async () => {
    next ??= await nextServerUpdatedAt(ctx, ownerTokenIdentifier);
    return next++;
  };
}

export async function findSyncedRecord(
  ctx: MutationCtx,
  table: SyncTableName,
  ownerTokenIdentifier: string,
  clientId: string,
): Promise<SyncDoc | null> {
  // The cast only narrows the table union; every synced table has this index.
  return await ctx.db
    .query(table as "exercises")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();
}

function sameSyncedFields(existing: SyncDoc, fields: Record<string, unknown>): boolean {
  const stored = existing as unknown as Record<string, unknown>;
  return Object.entries(fields).every(
    ([key, value]) => key === "updatedAt" || syncedContentEquals(stored[key] ?? null, value ?? null),
  );
}

function keepsUploadLive(decision: UpsertDecision): boolean {
  return (
    (decision.action === "insert" && decision.deletedAt === null) ||
    (decision.action === "patch" && decision.takeIncomingFields && decision.deletedAt === null)
  );
}

async function upsertSyncedRecord<TRecord extends SyncPayload>(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  plan: UpsertPlan<TRecord>,
): Promise<UpsertResult> {
  const { table } = plan;
  // The base names the version an edit started from; it is not stored.
  const { baseUpdatedAt, ...upload } = plan.record as TRecord & { baseUpdatedAt?: number | null };
  const record = upload as TRecord;
  const existing = await findSyncedRecord(ctx, table, ownerTokenIdentifier, record.clientId);
  const keepsRecordLive =
    record.deletedAt === null && (existing === null || existing.deletedAt === null);
  const parent: ParentState =
    keepsRecordLive && plan.parentState !== undefined
      ? await plan.parentState()
      : { kind: "live" };
  const fields =
    existing === null ? plan.insertFields(record) : plan.updateFields(record, existing);
  const decision = decideUpsert(existing, { ...record, baseUpdatedAt }, {
    nowSeconds: Date.now() / 1000,
    sameContent: existing !== null && sameSyncedFields(existing, fields),
    parentDeletedAt: parent.kind === "deleted" ? parent.deletedAt : null,
  });
  if (parent.kind === "missing" && keepsUploadLive(decision)) {
    throw syncError(parent.code, parent.message);
  }

  const nextVersion = serverVersionAllocator(ctx, ownerTokenIdentifier);
  switch (decision.action) {
    case "ignore":
      if (existing!.deletedAt !== null) {
        // Children an older server left live under this tombstone follow it
        // now, as with a repeated tombstone.
        await cascadeDeletion(ctx, ownerTokenIdentifier, table, {
          clientId: record.clientId,
          updatedAt: existing!.updatedAt,
          deletedAt: existing!.deletedAt,
        }, nextVersion);
      }
      return {
        status: "ignored_stale",
        serverUpdatedAt: existing!.serverUpdatedAt,
        updatedAt: existing!.updatedAt,
      };
    case "insert": {
      const serverUpdatedAt = await nextVersion();
      await ctx.db.insert(table as "exercises", {
        ...fields,
        updatedAt: decision.updatedAt,
        deletedAt: decision.deletedAt,
        ownerTokenIdentifier,
        serverUpdatedAt,
        syncOrder: decision.syncOrder,
      } as Doc<"exercises">);
      if (decision.deletedAt !== null) {
        // Children an older server left without this row follow its deletion.
        await cascadeDeletion(ctx, ownerTokenIdentifier, table, {
          clientId: record.clientId,
          updatedAt: decision.updatedAt,
          deletedAt: decision.deletedAt,
        }, nextVersion);
      }
      return {
        status: decision.accepted ? "inserted" : "ignored_stale",
        serverUpdatedAt,
        updatedAt: decision.updatedAt,
      };
    }
    case "patch": {
      const serverUpdatedAt = await nextVersion();
      await ctx.db.patch(existing!._id, {
        ...(decision.takeIncomingFields ? { ...fields, ownerTokenIdentifier } : {}),
        updatedAt: decision.updatedAt,
        deletedAt: decision.deletedAt,
        serverUpdatedAt,
        ...(decision.syncOrder === undefined ? {} : { syncOrder: decision.syncOrder }),
      });
      if (decision.deletedAt !== null) {
        // Also on a row that was already deleted: children an older server
        // left live under it follow it now, as with a repeated tombstone.
        await cascadeDeletion(ctx, ownerTokenIdentifier, table, {
          clientId: record.clientId,
          updatedAt: decision.updatedAt,
          deletedAt: decision.deletedAt,
        }, nextVersion);
      }
      return {
        status: decision.accepted ? "updated" : "ignored_stale",
        serverUpdatedAt,
        updatedAt: decision.updatedAt,
      };
    }
  }
}

async function tombstoneSyncedRecord(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  table: SyncTableName,
  clientId: string,
  deletedAt: number,
): Promise<TombstoneResult> {
  const existing = await findSyncedRecord(ctx, table, ownerTokenIdentifier, clientId);
  const decision = decideTombstone(existing, deletedAt, Date.now() / 1000);
  const nextVersion = serverVersionAllocator(ctx, ownerTokenIdentifier);
  switch (decision.action) {
    case "insertPlaceholder": {
      const serverUpdatedAt = await nextVersion();
      await ctx.db.insert(table as "exercises", {
        ...placeholderFields(table),
        clientId,
        ownerTokenIdentifier,
        // Zero createdAt marks a placeholder: the record's own upload, if it
        // ever arrives, writes its fields onto the tombstone and stays deleted.
        createdAt: 0,
        updatedAt: decision.updatedAt,
        deletedAt: decision.deletedAt,
        serverUpdatedAt,
      } as Doc<"exercises">);
      // Children an older server left without this parent row follow it too.
      await cascadeDeletion(ctx, ownerTokenIdentifier, table, {
        clientId,
        updatedAt: decision.updatedAt,
        deletedAt: decision.deletedAt,
      }, nextVersion);
      return { status: "tombstoned", serverUpdatedAt };
    }
    case "alreadyDeleted": {
      // Children that an older server left live under this tombstone follow it now.
      await cascadeDeletion(ctx, ownerTokenIdentifier, table, {
        clientId,
        updatedAt: existing!.updatedAt,
        deletedAt: existing!.deletedAt!,
      }, nextVersion);
      return { status: "tombstoned", serverUpdatedAt: existing!.serverUpdatedAt };
    }
    case "tombstone": {
      const serverUpdatedAt = await nextVersion();
      await ctx.db.patch(existing!._id, {
        deletedAt: decision.deletedAt,
        updatedAt: decision.updatedAt,
        serverUpdatedAt,
      });
      await cascadeDeletion(ctx, ownerTokenIdentifier, table, {
        clientId,
        updatedAt: decision.updatedAt,
        deletedAt: decision.deletedAt,
      }, nextVersion);
      return { status: "tombstoned", serverUpdatedAt };
    }
  }
}

// Valid field values for a tombstone of a record the server never received.
// Installed builds skip tombstones for records they do not have.
function placeholderFields(table: SyncTableName): Record<string, unknown> {
  switch (table) {
    case "userSettings":
      return { weightUnitRaw: "pounds", defaultRestTimerSeconds: 0, hasCompletedOnboarding: false };
    case "exercises":
      return {
        seedIdentifier: null,
        name: "",
        categoryRaw: "other",
        equipmentRaw: "other",
        primaryMuscleRaw: "",
        primaryMuscleGroupRaw: defaultPrimaryMuscleGroupRaw,
        notes: "",
        isArchived: false,
        isSeeded: false,
      };
    case "workoutSessions":
      return {
        title: "",
        startedAt: 0,
        endedAt: null,
        durationSeconds: 0,
        notes: "",
        referenceNotes: null,
        statusRaw: "discarded",
        sourceRaw: "blank",
        sourceSessionID: null,
        healthLinkID: null,
      };
    case "loggedExercises":
      return {
        sessionClientId: "",
        exerciseClientId: null,
        orderIndex: 0,
        exerciseSnapshotName: "",
        exerciseSnapshotEquipmentRaw: defaultExerciseSnapshotEquipmentRaw,
        exerciseSnapshotPrimaryMuscleGroupRaw: defaultExerciseSnapshotPrimaryMuscleGroupRaw,
        hasSnapshotMetadata: false,
        notes: "",
        referenceNotes: null,
      };
    case "loggedSets":
      return {
        loggedExerciseClientId: "",
        orderIndex: 0,
        weight: null,
        reps: null,
        rpe: null,
        kindRaw: "working",
        isCompleted: false,
        completedAt: null,
        notes: "",
        healthLinkID: null,
      };
    case "workoutTemplates":
      return { name: "", entries: [] };
  }
}

// Deleting a workout deletes its logged exercises and their sets; deleting a
// logged exercise deletes its sets. Deleting an exercise from the library
// leaves history alone, because history keeps its own snapshot.
export type SyncRowVersion = {
  updatedAt: number;
  deletedAt: number | null;
  serverUpdatedAt: number;
};

// Reports each row a cascade changes, so a repair can log what it did.
export type CascadeChange = {
  tableName: "loggedExercises" | "loggedSets";
  rowId: string;
  clientId: string;
  before: SyncRowVersion;
  after: SyncRowVersion;
};

export async function cascadeDeletion(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  table: SyncTableName,
  parent: { clientId: string; updatedAt: number; deletedAt: number },
  nextVersion: () => Promise<number>,
  onChange?: (change: CascadeChange) => Promise<void>,
): Promise<void> {
  if (table === "workoutSessions") {
    const loggedExercises: Doc<"loggedExercises">[] = [];
    for await (const loggedExercise of ctx.db
      .query("loggedExercises")
      .withIndex("by_ownerTokenIdentifier_and_sessionClientId", (q) =>
        q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("sessionClientId", parent.clientId),
      )) {
      loggedExercises.push(loggedExercise);
    }
    for (const loggedExercise of loggedExercises) {
      let version = { updatedAt: loggedExercise.updatedAt, deletedAt: loggedExercise.deletedAt };
      if (loggedExercise.deletedAt === null) {
        version = cascadedChildVersion(loggedExercise, parent);
        const after = { ...version, serverUpdatedAt: await nextVersion() };
        await ctx.db.patch(loggedExercise._id, after);
        await onChange?.({
          tableName: "loggedExercises",
          rowId: loggedExercise._id,
          clientId: loggedExercise.clientId,
          before: versionOf(loggedExercise),
          after,
        });
      }
      await cascadeDeletion(ctx, ownerTokenIdentifier, "loggedExercises", {
        clientId: loggedExercise.clientId,
        updatedAt: version.updatedAt,
        deletedAt: version.deletedAt ?? parent.deletedAt,
      }, nextVersion, onChange);
    }
    return;
  }

  if (table === "loggedExercises") {
    const sets: Doc<"loggedSets">[] = [];
    for await (const set of ctx.db
      .query("loggedSets")
      .withIndex("by_ownerTokenIdentifier_and_loggedExerciseClientId", (q) =>
        q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("loggedExerciseClientId", parent.clientId),
      )) {
      sets.push(set);
    }
    for (const set of sets) {
      if (set.deletedAt === null) {
        const after = { ...cascadedChildVersion(set, parent), serverUpdatedAt: await nextVersion() };
        await ctx.db.patch(set._id, after);
        await onChange?.({
          tableName: "loggedSets",
          rowId: set._id,
          clientId: set.clientId,
          before: versionOf(set),
          after,
        });
      }
    }
  }
}

export function versionOf(row: SyncRowVersion): SyncRowVersion {
  return { updatedAt: row.updatedAt, deletedAt: row.deletedAt, serverUpdatedAt: row.serverUpdatedAt };
}

function parentStateFromRow(
  row: { deletedAt: number | null } | null,
  missingMessage: string,
): ParentState {
  if (row === null) return { kind: "missing", code: "missingParent", message: missingMessage };
  if (row.deletedAt !== null) return { kind: "deleted", deletedAt: row.deletedAt };
  return { kind: "live" };
}

async function upsertUserSettingsByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: UserSettingsPayload,
): Promise<UpsertResult> {
  return await upsertSyncedRecord(ctx, ownerTokenIdentifier, {
    table: "userSettings",
    record,
    insertFields: (upload) => ({ ...upload }),
    updateFields: (upload) => ({ ...upload }),
  });
}

async function upsertExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: ExercisePayload,
): Promise<UpsertResult> {
  return await upsertSyncedRecord(ctx, ownerTokenIdentifier, {
    table: "exercises",
    record,
    insertFields: normalizeExercisePayload,
    updateFields: (upload, existing) => ({
      ...upload,
      primaryMuscleGroupRaw:
        upload.primaryMuscleGroupRaw ??
        (existing as Doc<"exercises">).primaryMuscleGroupRaw ??
        defaultPrimaryMuscleGroupRaw,
    }),
  });
}

async function upsertWorkoutSessionByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: WorkoutSessionPayload,
): Promise<UpsertResult> {
  return await upsertSyncedRecord(ctx, ownerTokenIdentifier, {
    table: "workoutSessions",
    record,
    insertFields: (upload) => ({ ...upload }),
    // patch keeps sourceTemplateID when an older build leaves it out.
    updateFields: (upload, existing) => ({
      ...upload,
      sourceTemplateID:
        upload.sourceTemplateID === undefined
          ? (existing as Doc<"workoutSessions">).sourceTemplateID
          : upload.sourceTemplateID,
    }),
  });
}

export function mergeWorkoutTemplateEntries(
  existing: Doc<"workoutTemplates">["entries"],
  uploaded: WorkoutTemplatePayload["entries"],
): Doc<"workoutTemplates">["entries"] {
  const existingByID = new Map(existing.map((entry) => [entry.id, entry]));
  return uploaded.map((entry) => ({ ...existingByID.get(entry.id), ...entry }));
}

async function upsertWorkoutTemplateByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: WorkoutTemplatePayload,
): Promise<UpsertResult> {
  return await upsertSyncedRecord(ctx, ownerTokenIdentifier, {
    table: "workoutTemplates",
    record,
    insertFields: (upload) => ({ ...upload }),
    updateFields: (upload, existing) => ({
      ...upload,
      entries: mergeWorkoutTemplateEntries(
        (existing as Doc<"workoutTemplates">).entries,
        upload.entries,
      ),
    }),
  });
}

async function findWorkoutSessionByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
): Promise<Doc<"workoutSessions"> | null> {
  return (await findSyncedRecord(
    ctx,
    "workoutSessions",
    ownerTokenIdentifier,
    clientId,
  )) as Doc<"workoutSessions"> | null;
}

async function findLoggedExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  clientId: string,
): Promise<Doc<"loggedExercises"> | null> {
  return (await findSyncedRecord(
    ctx,
    "loggedExercises",
    ownerTokenIdentifier,
    clientId,
  )) as Doc<"loggedExercises"> | null;
}

async function loggedExerciseParentState(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: LoggedExercisePayload,
): Promise<ParentState> {
  const session = parentStateFromRow(
    await findWorkoutSessionByClientId(ctx, ownerTokenIdentifier, record.sessionClientId),
    "Cannot upsert active logged exercise without its workout session parent.",
  );
  if (session.kind !== "live" || record.exerciseClientId === null) {
    return session;
  }
  // A tombstoned exercise is still a valid reference: history keeps its snapshot.
  const exercise = await findSyncedRecord(
    ctx,
    "exercises",
    ownerTokenIdentifier,
    record.exerciseClientId,
  );
  return exercise === null
    ? {
        kind: "missing",
        code: "missingExerciseReference",
        message: "Cannot upsert active logged exercise with a missing exercise reference.",
      }
    : { kind: "live" };
}

async function loggedSetParentState(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: LoggedSetPayload,
): Promise<ParentState> {
  const missingMessage = "Cannot upsert active logged set without its logged exercise parent.";
  const loggedExercise = await findLoggedExerciseByClientId(
    ctx,
    ownerTokenIdentifier,
    record.loggedExerciseClientId,
  );
  const loggedExerciseState = parentStateFromRow(loggedExercise, missingMessage);
  if (loggedExercise === null || loggedExerciseState.kind !== "live") {
    return loggedExerciseState;
  }
  return parentStateFromRow(
    await findWorkoutSessionByClientId(ctx, ownerTokenIdentifier, loggedExercise.sessionClientId),
    missingMessage,
  );
}

async function upsertLoggedExerciseByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: LoggedExercisePayload,
): Promise<UpsertResult> {
  return await upsertSyncedRecord(ctx, ownerTokenIdentifier, {
    table: "loggedExercises",
    record,
    insertFields: normalizeLoggedExercisePayload,
    updateFields: (upload, existing) =>
      normalizeLoggedExerciseUpdatePayload(upload, existing as Doc<"loggedExercises">),
    parentState: () => loggedExerciseParentState(ctx, ownerTokenIdentifier, record),
  });
}

async function upsertLoggedSetByClientId(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
  record: LoggedSetPayload,
): Promise<UpsertResult> {
  return await upsertSyncedRecord(ctx, ownerTokenIdentifier, {
    table: "loggedSets",
    record,
    insertFields: (upload) => ({ ...upload }),
    updateFields: (upload) => ({ ...upload }),
    parentState: () => loggedSetParentState(ctx, ownerTokenIdentifier, record),
  });
}

async function fetchUserSettingsChanges(
  ctx: SyncReadCtx,
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
  ctx: SyncReadCtx,
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
  ctx: SyncReadCtx,
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
  ctx: SyncReadCtx,
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
  ctx: SyncReadCtx,
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

async function fetchWorkoutTemplateChanges(
  ctx: SyncReadCtx,
  ownerTokenIdentifier: string,
  cursor: number,
  limit: number,
): Promise<ChangePage<Doc<"workoutTemplates">>> {
  const records = await ctx.db
    .query("workoutTemplates")
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

async function deleteWorkoutTemplatesForOwnerBatch(
  ctx: MutationCtx,
  ownerTokenIdentifier: string,
): Promise<{ deletedCount: number; hasMore: boolean }> {
  return await deleteRowsForOwnerBatch(
    () =>
      ctx.db
        .query("workoutTemplates")
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

export const upsertWorkoutTemplate = mutation({
  args: { record: workoutTemplatePayloadValidator },
  handler: async (ctx, args) => {
    assertFinitePayloadNumbers(args.record);
    const ownerTokenIdentifier = await requireOwnerTokenIdentifier(ctx);
    await assertAccountDeletionNotStarted(ctx, ownerTokenIdentifier);
    return await upsertWorkoutTemplateByClientId(ctx, ownerTokenIdentifier, args.record);
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

    return await tombstoneSyncedRecord(
      ctx,
      ownerTokenIdentifier,
      args.entityKind,
      args.clientId,
      args.deletedAt,
    );
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

export const accountDeletionMarkerForOwnerInternal = internalQuery({
  args: {
    ownerTokenIdentifier: v.string(),
  },
  handler: async (ctx, args): Promise<Doc<"accountDeletionMarkers"> | null> => {
    return await accountDeletionMarkerForOwner(ctx, args.ownerTokenIdentifier);
  },
});

export const resumeIncompleteAccountDeletion = internalAction({
  args: {
    ownerTokenIdentifier: v.string(),
  },
  handler: async (ctx, args): Promise<void> => {
    const marker: Doc<"accountDeletionMarkers"> | null = await ctx.runQuery(
      internal.sync.accountDeletionMarkerForOwnerInternal,
      { ownerTokenIdentifier: args.ownerTokenIdentifier },
    );
    if (marker === null || marker.phaseRaw !== "deletionIncomplete") {
      return;
    }

    await deleteAccountDataWithBatches(async (tableName) => {
      return await ctx.runMutation(internal.sync.deleteAccountDataBatch, {
        ownerTokenIdentifier: args.ownerTokenIdentifier,
        tableName,
      });
    });

    await ctx.runMutation(internal.sync.markAccountDeletionDataDeleted, {
      ownerTokenIdentifier: args.ownerTokenIdentifier,
      cancellationToken: marker.cancellationToken,
    });
  },
});

export const clearExpiredAccountDeletionMarkers = internalMutation({
  args: {
    expiresBefore: v.optional(v.number()),
    purgeBefore: v.optional(v.number()),
    parkedCursor: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<AccountDeletionMarkerCleanupResult> => {
    const now = Date.now();
    const expiresBefore = args.expiresBefore ?? now - accountDeletionMarkerExpiryMs;
    const purgeBefore = args.purgeBefore ?? now - accountDeletionMarkerPurgeMs;
    let deletedCount = 0;
    let hasMore = false;

    for (const phaseRaw of expirableAccountDeletionPhases) {
      const candidates = await ctx.db
        .query("accountDeletionMarkers")
        .withIndex("by_phaseRaw_and_createdAt", (q) =>
          q.eq("phaseRaw", phaseRaw).lt("createdAt", expiresBefore),
        )
        .take(accountDeletionMarkerCleanupBatchSize + 1);
      hasMore = hasMore || candidates.length > accountDeletionMarkerCleanupBatchSize;

      for (const marker of candidates.slice(0, accountDeletionMarkerCleanupBatchSize)) {
        if (await resolveExpiredAccountDeletionMarker(ctx, marker)) {
          deletedCount += 1;
        }
      }
    }

    const completedAtPurgeCandidates = await ctx.db
      .query("accountDeletionMarkers")
      .withIndex("by_phaseRaw_and_cloudDataDeletedAt", (q) =>
        q
          .eq("phaseRaw", "cloudDataDeleted")
          .gt("cloudDataDeletedAt", 0)
          .lt("cloudDataDeletedAt", purgeBefore),
      )
      .take(accountDeletionMarkerCleanupBatchSize + 1);
    hasMore =
      hasMore || completedAtPurgeCandidates.length > accountDeletionMarkerCleanupBatchSize;
    for (const marker of completedAtPurgeCandidates.slice(
      0,
      accountDeletionMarkerCleanupBatchSize,
    )) {
      await ctx.db.delete(marker._id);
      deletedCount += 1;
    }

    const createdAtPurgeCandidates = await ctx.db
      .query("accountDeletionMarkers")
      .withIndex("by_phaseRaw_and_createdAt", (q) =>
        q.eq("phaseRaw", "cloudDataDeleted").lt("createdAt", purgeBefore),
      )
      .take(accountDeletionMarkerCleanupBatchSize + 1);
    hasMore =
      hasMore || createdAtPurgeCandidates.length > accountDeletionMarkerCleanupBatchSize;
    for (const marker of createdAtPurgeCandidates.slice(
      0,
      accountDeletionMarkerCleanupBatchSize,
    )) {
      const purgeEligibleAt = marker.cloudDataDeletedAt ?? marker.createdAt;
      if (purgeEligibleAt >= purgeBefore) {
        if (
          marker.cloudDataDeletedAt !== undefined &&
          marker.createdAt !== marker.cloudDataDeletedAt
        ) {
          await ctx.db.patch(marker._id, { createdAt: marker.cloudDataDeletedAt });
        }
        continue;
      }
      await ctx.db.delete(marker._id);
      deletedCount += 1;
    }

    const parkedPage = await ctx.db
      .query("accountDeletionMarkers")
      .withIndex("by_phaseRaw_and_createdAt", (q) =>
        q.eq("phaseRaw", "deletionIncomplete"),
      )
      .paginate({
        numItems: accountDeletionMarkerCleanupBatchSize,
        cursor: args.parkedCursor ?? null,
      });
    hasMore = hasMore || !parkedPage.isDone;
    for (const marker of parkedPage.page) {
      await ctx.scheduler.runAfter(0, internal.sync.resumeIncompleteAccountDeletion, {
        ownerTokenIdentifier: marker.ownerTokenIdentifier,
      });
    }

    if (hasMore) {
      await ctx.scheduler.runAfter(
        0,
        internal.sync.clearExpiredAccountDeletionMarkers,
        {
          ...args,
          parkedCursor: parkedPage.continueCursor,
        },
      );
    }

    return { deletedCount, hasMore };
  },
});

export const markAccountDeletionDataDeleted = internalMutation({
  args: {
    ownerTokenIdentifier: v.string(),
    cancellationToken: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await accountDeletionMarkerForOwner(ctx, args.ownerTokenIdentifier);
    if (
      existing === null ||
      existing.phaseRaw === "cloudDataDeleted" ||
      existing.cancellationToken !== args.cancellationToken
    ) {
      return;
    }

    const completedAt = Date.now();
    await ctx.db.patch(existing._id, {
      phaseRaw: "cloudDataDeleted",
      createdAt: completedAt,
      cloudDataDeletedAt: completedAt,
    });
  },
});

export const deleteAccountDataBatch = internalMutation({
  args: {
    ownerTokenIdentifier: v.string(),
    tableName: accountDeletionTableValidator,
  },
  handler: async (ctx, args): Promise<AccountDataDeletionTableBatchResult> => {
    const marker = await accountDeletionMarkerForOwner(ctx, args.ownerTokenIdentifier);
    if (marker === null) {
      return { tableName: args.tableName, deletedCount: 0, hasMore: false };
    }
    if (marker.phaseRaw !== "deleting" && marker.phaseRaw !== "cloudDataDeleted") {
      await ctx.db.patch(marker._id, { phaseRaw: "deleting" });
    }

    switch (args.tableName) {
      case "workoutTemplates": {
        const result = await deleteWorkoutTemplatesForOwnerBatch(
          ctx,
          args.ownerTokenIdentifier,
        );
        return { tableName: args.tableName, ...result };
      }
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

    const result = await deleteAccountDataForOwner(
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

    await ctx.runMutation(internal.sync.markAccountDeletionDataDeleted, {
      ownerTokenIdentifier,
      cancellationToken: args.cancellationToken,
    });

    return result;
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

async function fetchChangesForOwner(ctx: SyncReadCtx, args: FetchChangesArgs) {
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

  const changes = {
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

  const templateCursor = args.cursors.workoutTemplates;
  if (templateCursor === undefined) {
    return changes;
  }
  const workoutTemplatePage = await fetchWorkoutTemplateChanges(
    ctx,
    ownerTokenIdentifier,
    templateCursor,
    limit,
  );
  const workoutTemplates = workoutTemplatePage.records;
  return {
    ...changes,
    workoutTemplates,
    cursors: {
      ...changes.cursors,
      workoutTemplates: nextCursorFromRecords(workoutTemplates, templateCursor),
    },
    hasMore: { ...changes.hasMore, workoutTemplates: workoutTemplatePage.hasMore },
  };
}

export const fetchChanges = query({
  args: {
    cursors: syncCursorValidator,
    limit: v.optional(v.number()),
  },
  handler: fetchChangesForOwner,
});

export const fetchChangesOnce = mutation({
  args: {
    cursors: syncCursorValidator,
    limit: v.optional(v.number()),
  },
  handler: fetchChangesForOwner,
});
