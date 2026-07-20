import { v } from "convex/values";
import type { Id } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";

const legacyIssuer = "https://clerk.auth.liftinglog.app";
const maximumRowsPerOwnerTable = 1_000;

type OwnerScopedTable =
  | "userSettings"
  | "exercises"
  | "workoutSessions"
  | "loggedExercises"
  | "loggedSets";

const tableValidator = v.union(
  v.literal("userSettings"),
  v.literal("exercises"),
  v.literal("workoutSessions"),
  v.literal("loggedExercises"),
  v.literal("loggedSets"),
);

function validateNewIssuer(newIssuer: string) {
  let url: URL;
  try {
    url = new URL(newIssuer);
  } catch {
    throw new Error("New issuer is malformed");
  }
  if (url.protocol !== "https:" || url.origin !== newIssuer) {
    throw new Error("New issuer must be an HTTPS origin without a path");
  }
  if (newIssuer === legacyIssuer) {
    throw new Error("New issuer must differ from the legacy issuer");
  }
}

function ownerIdentifiers(subject: string, newIssuer: string) {
  if (subject.length === 0 || subject.includes("|")) {
    throw new Error("Clerk subject is malformed");
  }
  validateNewIssuer(newIssuer);
  return {
    oldOwner: `${legacyIssuer}|${subject}`,
    newOwner: `${newIssuer}|${subject}`,
  };
}

/**
 * Temporary beta cutover tool. Production currently has fewer than 500 rows in
 * any owner/table pair, so each table can move atomically in one invocation.
 * Remove this function after the four coordinated beta users are migrated.
 */
export const migrateOwnerTable = internalMutation({
  args: {
    subject: v.string(),
    newIssuer: v.string(),
    table: tableValidator,
    dryRun: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const { oldOwner, newOwner } = ownerIdentifiers(
      args.subject,
      args.newIssuer,
    );
    const dryRun = args.dryRun ?? true;

    const hasDeletionMarker = async (ownerTokenIdentifier: string) => {
      const markers = await ctx.db
        .query("accountDeletionMarkers")
        .withIndex("by_ownerTokenIdentifier", (q) =>
          q.eq("ownerTokenIdentifier", ownerTokenIdentifier),
        )
        .take(1);
      return markers.length > 0;
    };
    const [oldOwnerHasDeletionMarker, newOwnerHasDeletionMarker] =
      await Promise.all([
        hasDeletionMarker(oldOwner),
        hasDeletionMarker(newOwner),
      ]);
    if (oldOwnerHasDeletionMarker) {
      throw new Error(
        "Legacy owner has an account deletion marker; resolve it separately before migration",
      );
    }
    if (newOwnerHasDeletionMarker) {
      throw new Error(
        "Destination owner has an account deletion marker; resolve it separately before migration",
      );
    }

    const migrateRows = async (
      rows: Array<{ _id: Id<OwnerScopedTable> }>,
    ) => {
      if (rows.length === maximumRowsPerOwnerTable) {
        throw new Error(
          `Owner/table reached the ${maximumRowsPerOwnerTable}-row safety limit`,
        );
      }
      if (rows.length === 0 || dryRun) return rows.length;
      for (const row of rows) {
        await ctx.db.patch(row._id, { ownerTokenIdentifier: newOwner });
      }
      return rows.length;
    };

    const assertDestinationIsEmpty = async (hasDestinationRows: boolean) => {
      if (hasDestinationRows) {
        throw new Error(
          `Destination owner already has ${args.table} rows; stop and inspect`,
        );
      }
    };

    const rows = await ctx.db
      .query(args.table)
      .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
        q.eq("ownerTokenIdentifier", oldOwner),
      )
      .take(maximumRowsPerOwnerTable);
    if (rows.length > 0) {
      const destination = await ctx.db
        .query(args.table)
        .withIndex("by_ownerTokenIdentifier_and_serverUpdatedAt", (q) =>
          q.eq("ownerTokenIdentifier", newOwner),
        )
        .take(1);
      await assertDestinationIsEmpty(destination.length > 0);
    }
    const matched = await migrateRows(rows);

    return {
      table: args.table,
      subject: args.subject,
      dryRun,
      matched,
      migrated: dryRun ? 0 : matched,
    };
  },
});
