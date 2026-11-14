// Audit and repair for sync damage that older servers left in the data (#97,
// #98). Every function here is internal: run them with `npx convex run`, never
// from the app. The repair applies the same rules as sync/merge.ts, so its
// results look exactly like ordinary syncing to every installed build.
//
// Damage kinds:
// - liveChildUnderDeletedParent: a logged exercise or set left live under a
//   deleted workout or logged exercise. Older servers did not cascade deletes.
//   The apps already hide these rows. Repair: delete it, as the cascade would.
// - suspectedResurrection: a live, finished workout whose logged exercises
//   were all deleted after it ended. The app deletes a finished workout's
//   logged exercises only when it deletes the whole workout, so another
//   device's edit probably revived it on an older server. Report only: an
//   automatic delete cannot tell a revived workout from one whose duration
//   was later shortened. A current build that deleted it heals it by itself.
// - liveChildWithMissingParent: a live child whose parent row does not exist.
//   Report only; there is nothing to apply a rule to.
// - futureTimestamp: a row whose client timestamp is later than the moment it
//   reached the server (#98). Report only. The merge rule already judges such
//   rows by when they were written, and lowering the stored value would leave
//   installed builds with fast clocks unable to adopt later changes.
//
// Every row a repair changes keeps all of its fields, and gets a
// syncRepairLog entry. restoreWorkoutAsCopy brings a deleted workout back
// under new ids, which every installed build downloads as a new workout.

import { v } from "convex/values";
import { internal } from "./_generated/api";
import {
  internalAction,
  internalMutation,
  internalQuery,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import { type Doc, type Id } from "./_generated/dataModel";
import {
  cascadeDeletion,
  serverVersionAllocator,
  versionOf,
  type CascadeChange,
  type SyncTableName,
} from "./sync";
import { cascadedChildVersion } from "./sync/merge";

const damageKinds = [
  "liveChildUnderDeletedParent",
  "suspectedResurrection",
  "liveChildWithMissingParent",
  "futureTimestamp",
] as const;
type DamageKind = (typeof damageKinds)[number];

const scanTables = [
  "workoutSessions",
  "loggedExercises",
  "loggedSets",
  "exercises",
  "workoutTemplates",
  "userSettings",
] as const satisfies readonly SyncTableName[];
type ScanTable = (typeof scanTables)[number];
const scanTableValidator = v.union(...scanTables.map((table) => v.literal(table)));

// Client timestamps within this margin of the write time are ordinary jitter.
const futureTimestampToleranceSeconds = 1;
const defaultPageSize = 100;
const maxPageSize = 500;

type ParentVersion = { updatedAt: number; deletedAt: number };

type Finding = {
  kind: DamageKind;
  tableName: ScanTable;
  rowId: string;
  clientId: string;
  ownerTokenIdentifier: string;
  // What the repair changes. Present only for repairable kinds.
  plan:
    | { action: "deleteChild"; parent: ParentVersion }
    | null;
};

type ReadCtx = Pick<QueryCtx | MutationCtx, "db">;

async function findByClientId(
  ctx: ReadCtx,
  table: "workoutSessions" | "loggedExercises",
  ownerTokenIdentifier: string,
  clientId: string,
): Promise<Doc<"workoutSessions"> | Doc<"loggedExercises"> | null> {
  return await ctx.db
    .query(table as "workoutSessions")
    .withIndex("by_ownerTokenIdentifier_and_clientId", (q) =>
      q.eq("ownerTokenIdentifier", ownerTokenIdentifier).eq("clientId", clientId),
    )
    .unique();
}

function deletedVersion(row: { updatedAt: number; deletedAt: number | null }): ParentVersion | null {
  return row.deletedAt === null ? null : { updatedAt: row.updatedAt, deletedAt: row.deletedAt };
}

async function inspectRow(
  ctx: ReadCtx,
  tableName: ScanTable,
  row: Doc<ScanTable>,
): Promise<Finding[]> {
  const findings: Finding[] = [];
  const base = {
    tableName,
    rowId: row._id as string,
    clientId: row.clientId,
    ownerTokenIdentifier: row.ownerTokenIdentifier,
  };
  if (row.updatedAt > row.serverUpdatedAt / 1000 + futureTimestampToleranceSeconds) {
    findings.push({ ...base, kind: "futureTimestamp", plan: null });
  }
  if (row.deletedAt !== null) {
    return findings;
  }

  if (tableName === "workoutSessions") {
    const session = row as Doc<"workoutSessions">;
    // Only a finished workout has a fixed set of logged exercises.
    if (session.statusRaw !== "completed" || session.endedAt === null) {
      return findings;
    }
    const finishedAt = session.endedAt;
    // A deleted workout loses all its logged exercises at once; removing one
    // mid-workout leaves the others live.
    let loggedExerciseCount = 0;
    let allDeletedAfterFinish = true;
    for await (const loggedExercise of ctx.db
      .query("loggedExercises")
      .withIndex("by_ownerTokenIdentifier_and_sessionClientId", (q) =>
        q.eq("ownerTokenIdentifier", session.ownerTokenIdentifier).eq("sessionClientId", session.clientId),
      )) {
      loggedExerciseCount += 1;
      if (loggedExercise.deletedAt === null || loggedExercise.deletedAt <= finishedAt) {
        allDeletedAfterFinish = false;
      }
    }
    if (loggedExerciseCount > 0 && allDeletedAfterFinish) {
      findings.push({ ...base, kind: "suspectedResurrection", plan: null });
    }
  } else if (tableName === "loggedExercises") {
    const loggedExercise = row as Doc<"loggedExercises">;
    const session = await findByClientId(
      ctx,
      "workoutSessions",
      loggedExercise.ownerTokenIdentifier,
      loggedExercise.sessionClientId,
    );
    findings.push(...childFindings(base, session === null ? [] : [session], session === null));
  } else if (tableName === "loggedSets") {
    const set = row as Doc<"loggedSets">;
    const loggedExercise = (await findByClientId(
      ctx,
      "loggedExercises",
      set.ownerTokenIdentifier,
      set.loggedExerciseClientId,
    )) as Doc<"loggedExercises"> | null;
    const session =
      loggedExercise === null
        ? null
        : await findByClientId(ctx, "workoutSessions", set.ownerTokenIdentifier, loggedExercise.sessionClientId);
    const ancestors = [loggedExercise, session].filter((ancestor) => ancestor !== null);
    findings.push(...childFindings(base, ancestors, loggedExercise === null || session === null));
  }
  return findings;
}

function childFindings(
  base: Omit<Finding, "kind" | "plan">,
  ancestors: { updatedAt: number; deletedAt: number | null }[],
  hasMissingAncestor: boolean,
): Finding[] {
  // The nearest deleted ancestor decides the deletion the child inherits.
  const deletedAncestor = ancestors.map(deletedVersion).find((version) => version !== null);
  if (deletedAncestor !== undefined && deletedAncestor !== null) {
    return [{ ...base, kind: "liveChildUnderDeletedParent", plan: { action: "deleteChild", parent: deletedAncestor } }];
  }
  if (hasMissingAncestor) {
    return [{ ...base, kind: "liveChildWithMissingParent", plan: null }];
  }
  return [];
}

function isRepairable(finding: Finding): boolean {
  return finding.plan !== null;
}

function normalizePageSize(pageSize: number | undefined): number {
  return Math.max(1, Math.min(maxPageSize, Math.floor(pageSize ?? defaultPageSize)));
}

const pageArgs = {
  tableName: scanTableValidator,
  cursor: v.union(v.string(), v.null()),
  pageSize: v.optional(v.number()),
};

const findingValidator = v.object({
  kind: v.string(),
  tableName: v.string(),
  rowId: v.string(),
  clientId: v.string(),
  ownerTokenIdentifier: v.string(),
  repairable: v.boolean(),
  repaired: v.boolean(),
  changedRows: v.number(),
});

type PageResult = {
  findings: {
    kind: string;
    tableName: string;
    rowId: string;
    clientId: string;
    ownerTokenIdentifier: string;
    repairable: boolean;
    repaired: boolean;
    changedRows: number;
  }[];
  scanned: number;
  continueCursor: string;
  isDone: boolean;
};

function reportedFinding(
  finding: Finding,
  repairable: boolean,
  changedRows: number,
): PageResult["findings"][number] {
  return {
    kind: finding.kind,
    tableName: finding.tableName,
    rowId: finding.rowId,
    clientId: finding.clientId,
    ownerTokenIdentifier: finding.ownerTokenIdentifier,
    repairable,
    repaired: changedRows > 0,
    changedRows,
  };
}

const pageResultValidator = v.object({
  findings: v.array(findingValidator),
  scanned: v.number(),
  continueCursor: v.string(),
  isDone: v.boolean(),
});

// Read-only: what the repair would find and change on one page of a table.
export const auditSyncDamagePage = internalQuery({
  args: pageArgs,
  returns: pageResultValidator,
  handler: async (ctx, args): Promise<PageResult> => {
    const page = await ctx.db
      .query(args.tableName)
      .paginate({ cursor: args.cursor, numItems: normalizePageSize(args.pageSize) });
    const findings: PageResult["findings"] = [];
    for (const row of page.page) {
      for (const finding of await inspectRow(ctx, args.tableName, row as Doc<ScanTable>)) {
        const repairable = isRepairable(finding);
        findings.push(reportedFinding(finding, repairable, 0));
      }
    }
    return { findings, scanned: page.page.length, continueCursor: page.continueCursor, isDone: page.isDone };
  },
});

// Applies the repair to one page of a table. Safe to rerun: a repaired row
// no longer matches any damage kind.
export const repairSyncDamagePage = internalMutation({
  args: {
    ...pageArgs,
    runId: v.string(),
  },
  returns: pageResultValidator,
  handler: async (ctx, args): Promise<PageResult> => {
    const page = await ctx.db
      .query(args.tableName)
      .paginate({ cursor: args.cursor, numItems: normalizePageSize(args.pageSize) });
    const findings: PageResult["findings"] = [];
    for (const row of page.page) {
      for (const finding of await inspectRow(ctx, args.tableName, row as Doc<ScanTable>)) {
        const repairable = isRepairable(finding);
        const changedRows = repairable ? await applyRepair(ctx, finding, args.runId) : 0;
        findings.push(reportedFinding(finding, repairable, changedRows));
      }
    }
    return { findings, scanned: page.page.length, continueCursor: page.continueCursor, isDone: page.isDone };
  },
});

async function applyRepair(ctx: MutationCtx, finding: Finding, runId: string): Promise<number> {
  const row = await ctx.db.get(finding.rowId as Id<"workoutSessions">);
  // Recheck inside this transaction: a sync write may have fixed it already.
  if (row === null || row.deletedAt !== null || finding.plan === null) {
    return 0;
  }
  const nextVersion = serverVersionAllocator(ctx, finding.ownerTokenIdentifier);
  const repairedAt = Date.now();
  let changedRows = 0;
  const log = async (change: Omit<CascadeChange, "tableName"> & { tableName: string }) => {
    changedRows += 1;
    await ctx.db.insert("syncRepairLog", {
      runId,
      damageKind: finding.kind,
      repairedAt,
      ...change,
    });
  };

  if (finding.plan.action === "deleteChild") {
    const after = {
      ...cascadedChildVersion(row, finding.plan.parent),
      serverUpdatedAt: await nextVersion(),
    };
    await ctx.db.patch(row._id, after);
    await log({ tableName: finding.tableName, rowId: finding.rowId, clientId: row.clientId, before: versionOf(row), after });
    await cascadeDeletion(ctx, finding.ownerTokenIdentifier, finding.tableName, {
      clientId: row.clientId,
      updatedAt: after.updatedAt,
      deletedAt: after.deletedAt,
    }, nextVersion, log);
    return changedRows;
  }
  return 0;
}

type RunSummary = {
  runId: string;
  dryRun: boolean;
  scannedRows: number;
  affectedOwners: number;
  byKind: Record<string, { found: number; repairable: number; repaired: number; changedRows: number }>;
  // A bounded sample to spot-check, without account identifiers.
  sample: { kind: string; tableName: string; rowId: string; clientId: string; repairable: boolean }[];
};

// Scans every synced table. With dryRun (the default) it only reports what a
// repair would change. Pass dryRun: false to apply; the summary's runId keys
// the syncRepairLog entries.
export const runSyncDamageRepair = internalAction({
  args: {
    dryRun: v.optional(v.boolean()),
    pageSize: v.optional(v.number()),
    sampleLimit: v.optional(v.number()),
    runId: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<RunSummary> => {
    const dryRun = args.dryRun !== false;
    const runId = args.runId ?? `sync-repair-${Date.now()}`;
    const sampleLimit = Math.max(0, Math.min(200, args.sampleLimit ?? 25));
    const summary: RunSummary = {
      runId,
      dryRun,
      scannedRows: 0,
      affectedOwners: 0,
      byKind: Object.fromEntries(
        damageKinds.map((kind) => [kind, { found: 0, repairable: 0, repaired: 0, changedRows: 0 }]),
      ),
      sample: [],
    };
    const owners = new Set<string>();

    for (const tableName of scanTables) {
      let cursor: string | null = null;
      for (;;) {
        const page: PageResult = dryRun
          ? await ctx.runQuery(internal.syncRepair.auditSyncDamagePage, {
              tableName,
              cursor,
              pageSize: args.pageSize,
            })
          : await ctx.runMutation(internal.syncRepair.repairSyncDamagePage, {
              tableName,
              cursor,
              pageSize: args.pageSize,
              runId,
            });
        summary.scannedRows += page.scanned;
        for (const finding of page.findings) {
          const counts = summary.byKind[finding.kind];
          counts.found += 1;
          counts.repairable += finding.repairable ? 1 : 0;
          counts.repaired += finding.repaired ? 1 : 0;
          counts.changedRows += finding.changedRows;
          owners.add(finding.ownerTokenIdentifier);
          if (summary.sample.length < sampleLimit) {
            summary.sample.push({
              kind: finding.kind,
              tableName: finding.tableName,
              rowId: finding.rowId,
              clientId: finding.clientId,
              repairable: finding.repairable,
            });
          }
        }
        if (page.isDone) break;
        cursor = page.continueCursor;
      }
    }
    summary.affectedOwners = owners.size;
    return summary;
  },
});

// The rows one repair run changed, for review.
export const syncRepairLogForRun = internalQuery({
  args: { runId: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("syncRepairLog")
      .withIndex("by_runId", (q) => q.eq("runId", args.runId))
      .take(Math.max(1, Math.min(1000, args.limit ?? 200)));
  },
});

// Recovery path for a deleted workout, whether a person, sync or a repair
// deleted it. A tombstone can never come back to life on an installed build,
// so this creates a live copy under new ids, with the logged exercises and
// sets that were deleted together with the workout. Every build downloads it
// as a new workout. Dry run by default.
export const restoreWorkoutAsCopy = internalMutation({
  args: {
    sessionRowId: v.id("workoutSessions"),
    dryRun: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.sessionRowId);
    if (session === null) {
      throw new Error("No workout with that row id.");
    }
    if (session.deletedAt === null) {
      throw new Error("That workout is not deleted.");
    }
    if (session.createdAt === 0) {
      throw new Error("The server never received this workout's content.");
    }
    const deletedWithWorkout = (row: { deletedAt: number | null }) =>
      row.deletedAt === null || row.deletedAt >= session.deletedAt!;
    const owner = session.ownerTokenIdentifier;
    const loggedExercises: Doc<"loggedExercises">[] = [];
    for await (const loggedExercise of ctx.db
      .query("loggedExercises")
      .withIndex("by_ownerTokenIdentifier_and_sessionClientId", (q) =>
        q.eq("ownerTokenIdentifier", owner).eq("sessionClientId", session.clientId),
      )) {
      if (deletedWithWorkout(loggedExercise)) loggedExercises.push(loggedExercise);
    }
    const setsByLoggedExercise = new Map<string, Doc<"loggedSets">[]>();
    for (const loggedExercise of loggedExercises) {
      const sets: Doc<"loggedSets">[] = [];
      for await (const set of ctx.db
        .query("loggedSets")
        .withIndex("by_ownerTokenIdentifier_and_loggedExerciseClientId", (q) =>
          q.eq("ownerTokenIdentifier", owner).eq("loggedExerciseClientId", loggedExercise.clientId),
        )) {
        if (deletedWithWorkout(set)) sets.push(set);
      }
      setsByLoggedExercise.set(loggedExercise.clientId, sets);
    }
    const setCount = [...setsByLoggedExercise.values()].reduce((total, sets) => total + sets.length, 0);
    const newSessionClientId = crypto.randomUUID().toLowerCase();
    if (args.dryRun !== false) {
      return { dryRun: true, newSessionClientId: null, loggedExercises: loggedExercises.length, sets: setCount };
    }

    const nextVersion = serverVersionAllocator(ctx, owner);
    const nowSeconds = Date.now() / 1000;
    const live = { deletedAt: null, updatedAt: nowSeconds };
    const { _id: _sessionId, _creationTime: _sessionCreation, ...sessionFields } = session;
    await ctx.db.insert("workoutSessions", {
      ...sessionFields,
      ...live,
      clientId: newSessionClientId,
      serverUpdatedAt: await nextVersion(),
    });
    for (const loggedExercise of loggedExercises) {
      const newLoggedExerciseClientId = crypto.randomUUID().toLowerCase();
      const { _id, _creationTime, ...fields } = loggedExercise;
      await ctx.db.insert("loggedExercises", {
        ...fields,
        ...live,
        clientId: newLoggedExerciseClientId,
        sessionClientId: newSessionClientId,
        serverUpdatedAt: await nextVersion(),
      });
      for (const set of setsByLoggedExercise.get(loggedExercise.clientId) ?? []) {
        const { _id: _setId, _creationTime: _setCreation, ...setFields } = set;
        await ctx.db.insert("loggedSets", {
          ...setFields,
          ...live,
          clientId: crypto.randomUUID().toLowerCase(),
          loggedExerciseClientId: newLoggedExerciseClientId,
          serverUpdatedAt: await nextVersion(),
        });
      }
    }
    return { dryRun: false, newSessionClientId, loggedExercises: loggedExercises.length, sets: setCount };
  },
});
