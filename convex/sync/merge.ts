// The server's conflict rule for every synced record. Pure, so the same rule
// can be tested directly and mirrored by the client test harness.
//
// 1. Deletes win. A tombstone is terminal: no later upload revives it, and
//    deleting a workout or logged exercise deletes everything under it. A
//    tombstone still takes newer field values, so the last edit anyone made
//    stays on the server and a deleted record can be recovered.
// 2. Field values are last-writer-wins. A current build names the version its
//    edit started from (`baseUpdatedAt`): an edit made after seeing the
//    stored version always replaces it, and any other upload must beat the
//    stored ordering time (`syncOrder`), which never moves backward, so a
//    retry can never win twice. Installed builds send no base; their uploads
//    are judged on an effective time that no client clock can push past the
//    moment the write reached the server. An edit cannot happen after it is
//    uploaded, so a later client timestamp is always a fast clock.
// 3. When the server keeps one version over another, the stored `updatedAt`
//    ends up above the discarded one. Installed builds adopt a pulled record
//    only when its `updatedAt` is greater than their own, so they then adopt
//    the server's choice instead of keeping theirs forever.

// Smallest step that keeps a stored version strictly above the one it beat.
export const versionStepSeconds = 0.001;

export type StoredVersion = {
  // Zero marks a placeholder tombstone: the server got the delete before it
  // ever got the record.
  createdAt?: number;
  updatedAt: number;
  deletedAt: number | null;
  // Milliseconds, assigned by the server when the version was written.
  serverUpdatedAt: number;
  // Conflict-ordering time, kept apart from the updatedAt installed builds
  // compare. Absent on rows written before it existed.
  syncOrder?: number;
};

export type IncomingVersion = {
  updatedAt: number;
  deletedAt: number | null;
  // Sent by current builds only: the stored updatedAt of the version this
  // edit started from, or null for a record the device has never synced.
  baseUpdatedAt?: number | null;
};

export type UpsertDecision =
  // Store the upload as a new row, live or already deleted.
  | { action: "insert"; updatedAt: number; deletedAt: number | null; syncOrder: number; accepted: boolean }
  // Update the stored row. `takeIncomingFields` says whose field values win;
  // `deletedAt` is the row's resulting deletion, which never goes back to null.
  | {
      action: "patch";
      takeIncomingFields: boolean;
      updatedAt: number;
      deletedAt: number | null;
      // Set when the upload's fields win.
      syncOrder?: number;
      // The upload took effect as sent: its fields and its deletion state.
      accepted: boolean;
    }
  // Keep the stored row unchanged: a duplicate, or an older upload.
  | { action: "ignore" };

export type TombstoneDecision =
  // No row yet: store a placeholder tombstone so a later upload of the record
  // cannot bring it back.
  | { action: "insertPlaceholder"; updatedAt: number; deletedAt: number }
  | { action: "alreadyDeleted" }
  | { action: "tombstone"; updatedAt: number; deletedAt: number };

// When the stored version reached the server, at the latest. The change
// feed's counter can run a little ahead of wall time during a burst of
// writes, so it is capped at now as well.
export function effectiveStoredTime(stored: StoredVersion, nowSeconds = Infinity): number {
  return Math.min(stored.updatedAt, stored.serverUpdatedAt / 1000, nowSeconds);
}

function isPlaceholder(stored: StoredVersion): boolean {
  return stored.createdAt === 0;
}

// The stored version's conflict-ordering time. Rows written before the
// field existed fall back to their effective time.
export function storedSyncOrder(stored: StoredVersion, nowSeconds: number): number {
  return stored.syncOrder ?? effectiveStoredTime(stored, nowSeconds);
}

// The ordering time an accepted upload gives the row: its own, and never
// below the version it replaced.
export function nextSyncOrder(
  stored: StoredVersion | null,
  incoming: IncomingVersion,
  nowSeconds: number,
): number {
  const own =
    incoming.baseUpdatedAt !== undefined
      ? incoming.updatedAt
      : effectiveIncomingTime(incoming, nowSeconds);
  return stored === null ? own : Math.max(own, storedSyncOrder(stored, nowSeconds) + versionStepSeconds);
}

export function effectiveIncomingTime(incoming: IncomingVersion, nowSeconds: number): number {
  return Math.min(incoming.updatedAt, nowSeconds);
}

export function clampToServerTime(timestamp: number, nowSeconds: number): number {
  return Math.min(timestamp, nowSeconds);
}

// A timestamp survives the app's Date round trip only to about a microsecond.
const sameTimeToleranceSeconds = 1e-6;

function sameTime(lhs: number, rhs: number): boolean {
  return Math.abs(lhs - rhs) <= sameTimeToleranceSeconds;
}

// Whether the upload's field values replace the stored ones.
export function incomingFieldsWin(
  stored: StoredVersion,
  incoming: IncomingVersion,
  nowSeconds: number,
): boolean {
  if (incoming.baseUpdatedAt !== undefined) {
    // A current build. An edit made after seeing the stored version replaces
    // it, whatever the clocks say.
    if (
      incoming.baseUpdatedAt !== null &&
      incoming.baseUpdatedAt >= stored.updatedAt - sameTimeToleranceSeconds
    ) {
      return true;
    }
    // Otherwise it was concurrent, or it is a retry. Every accepted upload
    // left the ordering time at or above its own stamp, so a retry, however
    // late, never wins again.
    return incoming.updatedAt > storedSyncOrder(stored, nowSeconds);
  }
  // An installed build. A timestamp ahead of server time is credited with its arrival only when
  // it is also ahead of the stored version on its own clock. Every upload the
  // server has processed left the stored timestamp at or above its own, so a
  // retry cannot win a second time while its stamp is still ahead.
  if (incoming.updatedAt > nowSeconds && incoming.updatedAt <= stored.updatedAt) {
    return false;
  }
  const incomingTime = effectiveIncomingTime(incoming, nowSeconds);
  const storedTime = effectiveStoredTime(stored, nowSeconds);
  if (incomingTime !== storedTime) {
    return incomingTime > storedTime;
  }
  // Same effective time, as with an edit in the same millisecond as the
  // version it replaced: the raw timestamp decides.
  return incoming.updatedAt > stored.updatedAt;
}

export function decideUpsert(
  stored: StoredVersion | null,
  incoming: IncomingVersion,
  context: {
    nowSeconds: number;
    // True when the upload's synced fields equal the stored ones.
    sameContent: boolean;
    // Set when the record's workout or logged exercise is already deleted.
    parentDeletedAt: number | null;
  },
): UpsertDecision {
  const { nowSeconds, sameContent, parentDeletedAt } = context;
  const uploaderHoldsLive = incoming.deletedAt === null;
  const requestedDeletedAt = incoming.deletedAt ?? parentDeletedAt;
  // A device that still shows the record live must be outranked to adopt the
  // delete; a device that sent the delete already has it.
  const deletionVersion = (base: number) =>
    uploaderHoldsLive ? base + versionStepSeconds : base;

  const syncOrder = nextSyncOrder(stored, incoming, nowSeconds);

  if (stored === null) {
    if (requestedDeletedAt === null) {
      return { action: "insert", updatedAt: incoming.updatedAt, deletedAt: null, syncOrder, accepted: true };
    }
    return {
      action: "insert",
      updatedAt: deletionVersion(incoming.updatedAt),
      deletedAt: clampToServerTime(requestedDeletedAt, nowSeconds),
      syncOrder,
      accepted: !uploaderHoldsLive,
    };
  }

  if (stored.deletedAt === null && requestedDeletedAt === null && sameContent && sameTime(incoming.updatedAt, stored.updatedAt)) {
    // A retry of the stored version.
    return { action: "ignore" };
  }
  const fieldsWin = incomingFieldsWin(stored, incoming, nowSeconds);

  if (stored.deletedAt !== null) {
    if (fieldsWin || isPlaceholder(stored)) {
      return {
        action: "patch",
        takeIncomingFields: true,
        updatedAt: Math.max(deletionVersion(incoming.updatedAt), stored.updatedAt + versionStepSeconds),
        deletedAt: stored.deletedAt,
        syncOrder,
        accepted: !uploaderHoldsLive,
      };
    }
    if (uploaderHoldsLive && incoming.updatedAt >= stored.updatedAt) {
      return {
        action: "patch",
        takeIncomingFields: false,
        updatedAt: incoming.updatedAt + versionStepSeconds,
        deletedAt: stored.deletedAt,
        accepted: false,
      };
    }
    return { action: "ignore" };
  }

  if (requestedDeletedAt !== null) {
    const inherited = uploaderHoldsLive;
    return {
      action: "patch",
      takeIncomingFields: fieldsWin,
      updatedAt: Math.max(stored.updatedAt + versionStepSeconds, deletionVersion(incoming.updatedAt)),
      deletedAt: clampToServerTime(requestedDeletedAt, nowSeconds),
      syncOrder: fieldsWin ? syncOrder : undefined,
      accepted: !inherited && fieldsWin,
    };
  }

  if (fieldsWin) {
    return {
      action: "patch",
      takeIncomingFields: true,
      updatedAt: Math.max(incoming.updatedAt, stored.updatedAt + versionStepSeconds),
      deletedAt: null,
      syncOrder,
      accepted: true,
    };
  }
  if (incoming.updatedAt < stored.updatedAt) {
    return { action: "ignore" };
  }
  return {
    action: "patch",
    takeIncomingFields: false,
    // Same content means the uploader already shows the kept version.
    updatedAt: sameContent ? incoming.updatedAt : incoming.updatedAt + versionStepSeconds,
    deletedAt: null,
    accepted: false,
  };
}

export function decideTombstone(
  stored: StoredVersion | null,
  deletedAt: number,
  nowSeconds: number,
): TombstoneDecision {
  if (stored === null) {
    // Versioned at the delete's own stamp, and at least its arrival, so a
    // device still holding the record adopts the delete. A current build
    // stamps a delete above the version it replaced, even from a fast clock.
    return {
      action: "insertPlaceholder",
      updatedAt: Math.max(deletedAt, nowSeconds),
      deletedAt: clampToServerTime(deletedAt, nowSeconds),
    };
  }
  if (stored.deletedAt !== null) {
    return { action: "alreadyDeleted" };
  }
  const clampedDeletedAt = clampToServerTime(deletedAt, nowSeconds);
  return {
    action: "tombstone",
    deletedAt: clampedDeletedAt,
    updatedAt: Math.max(clampedDeletedAt, stored.updatedAt + versionStepSeconds),
  };
}

// Child rows inherit a parent's deletion with a version above their own.
export function cascadedChildVersion(
  child: { updatedAt: number },
  parent: { updatedAt: number; deletedAt: number },
): { updatedAt: number; deletedAt: number } {
  return {
    deletedAt: parent.deletedAt,
    updatedAt: Math.max(child.updatedAt + versionStepSeconds, parent.updatedAt),
  };
}

export function syncedContentEquals(lhs: unknown, rhs: unknown): boolean {
  if (lhs === rhs) return true;
  if (lhs === null || rhs === null || typeof lhs !== "object" || typeof rhs !== "object") {
    return false;
  }
  if (Array.isArray(lhs) !== Array.isArray(rhs)) return false;
  if (Array.isArray(lhs) && Array.isArray(rhs)) {
    return lhs.length === rhs.length && lhs.every((value, index) => syncedContentEquals(value, rhs[index]));
  }
  const lhsRecord = lhs as Record<string, unknown>;
  const rhsRecord = rhs as Record<string, unknown>;
  const keys = new Set([...Object.keys(lhsRecord), ...Object.keys(rhsRecord)]);
  for (const key of keys) {
    if (!syncedContentEquals(lhsRecord[key] ?? null, rhsRecord[key] ?? null)) return false;
  }
  return true;
}
