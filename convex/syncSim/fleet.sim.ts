// Deterministic multi-device sync simulator that drives the real Convex sync
// functions through convex-test. Test-only: the double-dot file name keeps it
// out of the deploy bundle.
//
// Each simulated device models one iPhone: its own local store, outbox and
// pull cursors, and a clock that can run fast, slow or jump. A device runs
// one of two client rules:
//
// - "legacy": a port of the client rule shipped in installed builds today
//   (SyncConflictResolver, SyncCoordinator push and pull loops). The server
//   must keep these devices convergent, because users update late or never.
// - "current": the rule new builds run. The server decides conflicts, and an
//   idle device copies the server's version. Edits stamp hybrid-logical
//   timestamps. A server-rejected entry is retried with backoff and later
//   dead-lettered without blocking the rest of the queue.
//
// A seeded scheduler interleaves devices at every network call. Faults are
// lost requests (never applied), lost responses (applied, but the device sees
// a failure and retries) and delays. One device's requests stay in order,
// because the app awaits each mutation and the Convex transport is ordered.

import { ConvexError } from "convex/values";
import { vi } from "vitest";
import { api } from "../_generated/api";
import { Rng } from "./rng.sim";

export type Kind = "exercises" | "workoutSessions" | "loggedExercises" | "loggedSets";
export const syncedKinds: readonly Kind[] = [
  "exercises",
  "workoutSessions",
  "loggedExercises",
  "loggedSets",
];
export type ClientRule = "legacy" | "current";
type Operation = "create" | "update" | "delete";
type EntryStatus = "pending" | "inFlight" | "failed" | "blocked";

export type LocalRecord = {
  kind: Kind;
  id: string;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
  // The user-editable field: exercise name, workout title, or notes.
  value: string;
  // Names the write that produced this version, so the oracle can tell which
  // write won. Stored in a spare string field of the payload.
  tag: string;
  // Session for a logged exercise, logged exercise for a set.
  parentId: string | null;
  exerciseId: string | null;
  // The server version this local copy descends from; current builds upload
  // it as baseUpdatedAt. Absent for a record never synced.
  syncBase?: number;
};

type OutboxEntry = {
  kind: Kind;
  id: string;
  operation: Operation;
  status: EntryStatus;
  createdAt: number;
  updatedAt: number;
  attemptCount: number;
  rejectionCount: number;
  firstRejectedAt: number | null;
  nextAttemptAt: number | null;
};

type MutationResult = { status: string; serverUpdatedAt?: number; updatedAt?: number };
type Cursors = {
  userSettings: number;
  exercises: number;
  workoutSessions: number;
  loggedExercises: number;
  loggedSets: number;
};
type HasMore = Record<keyof Cursors, boolean>;
type RemoteRecord = Record<string, unknown> & {
  clientId: string;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
  serverUpdatedAt: number;
};
type FetchResponse = {
  exercises: RemoteRecord[];
  workoutSessions: RemoteRecord[];
  loggedExercises: RemoteRecord[];
  loggedSets: RemoteRecord[];
  cursors: Cursors;
  hasMore: HasMore;
};

export type ConvexHarness = {
  withIdentity(identity: Record<string, string>): {
    mutation(fn: unknown, args: unknown): Promise<unknown>;
  };
  action(fn: unknown, args: unknown): Promise<unknown>;
  run<T>(
    fn: (ctx: {
      db: {
        query(table: string): { collect(): Promise<unknown[]> };
        insert(table: string, document: unknown): Promise<unknown>;
      };
    }) => Promise<T>,
  ): Promise<T>;
};

export class TransientNetworkError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TransientNetworkError";
  }
}

const millisecond = 0.001;
const pullPageLimit = 4;
const pushBatchLimit = 8;
// A record is dead-lettered only after this many rejections over at least a day.
const rejectionsBeforeDeadLetter = 8;
const rejectionWindowBeforeDeadLetterSeconds = 24 * 60 * 60;
const maxBackoffSeconds = 6 * 60 * 60;

// How the current build reads a server error (sync/errors.ts).
type RejectionKind = "record" | "accountWide" | "unknown";

function rejectionKind(error: unknown): RejectionKind {
  const code =
    error instanceof ConvexError && typeof error.data === "object" && error.data !== null
      ? (error.data as { code?: unknown }).code
      : undefined;
  switch (code) {
    case "invalidPayload":
    case "missingParent":
    case "missingExerciseReference":
      return "record";
    case "unauthenticated":
    case "accountDeletionInProgress":
      return "accountWide";
    default:
      return "unknown";
  }
}

export const owner = {
  subject: "sim_owner",
  issuer: "https://glad-krill-22.clerk.accounts.dev",
  tokenIdentifier: "https://glad-krill-22.clerk.accounts.dev|sim_owner",
};

function keyOf(kind: Kind, id: string): string {
  return `${kind}:${id}`;
}

function valueField(kind: Kind): string {
  switch (kind) {
    case "exercises":
      return "name";
    case "workoutSessions":
      return "title";
    case "loggedExercises":
    case "loggedSets":
      return "notes";
  }
}

function tagField(kind: Kind): string {
  switch (kind) {
    case "exercises":
    case "workoutSessions":
      return "notes";
    case "loggedExercises":
      return "referenceNotes";
    case "loggedSets":
      return "healthLinkID";
  }
}

export function payloadFor(record: LocalRecord, sendsBase = false): Record<string, unknown> {
  const base = {
    clientId: record.id,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    deletedAt: record.deletedAt,
    ...(sendsBase ? { baseUpdatedAt: record.syncBase ?? null } : {}),
  };
  switch (record.kind) {
    case "exercises":
      return {
        ...base,
        seedIdentifier: null,
        name: record.value,
        categoryRaw: "strength",
        equipmentRaw: "barbell",
        primaryMuscleRaw: "Chest",
        primaryMuscleGroupRaw: "chest",
        notes: record.tag,
        isArchived: false,
        isSeeded: false,
      };
    case "workoutSessions":
      return {
        ...base,
        title: record.value,
        startedAt: record.createdAt,
        endedAt: record.createdAt + 60,
        durationSeconds: 60,
        notes: record.tag,
        referenceNotes: null,
        statusRaw: "completed",
        sourceRaw: "blank",
        sourceSessionID: null,
        healthLinkID: null,
        sourceTemplateID: null,
      };
    case "loggedExercises":
      return {
        ...base,
        sessionClientId: record.parentId,
        exerciseClientId: record.exerciseId,
        orderIndex: 0,
        exerciseSnapshotName: "Bench Press",
        exerciseSnapshotEquipmentRaw: "barbell",
        exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
        hasSnapshotMetadata: true,
        notes: record.value,
        referenceNotes: record.tag,
        sourceLoggedExerciseID: null,
        supersetGroupID: null,
      };
    case "loggedSets":
      return {
        ...base,
        loggedExerciseClientId: record.parentId,
        orderIndex: 0,
        weight: 100,
        reps: 5,
        rpe: null,
        kindRaw: "working",
        isCompleted: true,
        completedAt: record.createdAt,
        notes: record.value,
        healthLinkID: record.tag,
        sourceLoggedSetID: null,
      };
  }
}

function recordFromRemote(kind: Kind, remote: RemoteRecord): LocalRecord {
  return {
    kind,
    id: remote.clientId,
    createdAt: remote.createdAt,
    updatedAt: remote.updatedAt,
    deletedAt: remote.deletedAt,
    value: String(remote[valueField(kind)]),
    tag: String(remote[tagField(kind)] ?? ""),
    syncBase: remote.updatedAt,
    parentId:
      kind === "loggedExercises"
        ? String(remote.sessionClientId)
        : kind === "loggedSets"
          ? String(remote.loggedExerciseClientId)
          : null,
    exerciseId:
      kind === "loggedExercises" ? ((remote.exerciseClientId as string | null) ?? null) : null,
  };
}

function upsertFunction(kind: Kind): unknown {
  switch (kind) {
    case "exercises":
      return api.sync.upsertExercise;
    case "workoutSessions":
      return api.sync.upsertWorkoutSession;
    case "loggedExercises":
      return api.sync.upsertLoggedExercise;
    case "loggedSets":
      return api.sync.upsertLoggedSet;
  }
}

function legacyPushRank(entry: OutboxEntry): number {
  if (entry.operation === "delete") {
    return { exercises: 1, loggedSets: 2, loggedExercises: 3, workoutSessions: 4 }[entry.kind];
  }
  return { exercises: 1, workoutSessions: 2, loggedExercises: 3, loggedSets: 4 }[entry.kind];
}

// A flat view of one replica: visible records only, which is what a person
// sees. A record is visible when it and every ancestor are live.
export type VisibleState = Map<string, string>;

export function visibleState(records: Iterable<LocalRecord>): VisibleState {
  const byKey = new Map<string, LocalRecord>();
  for (const record of records) {
    byKey.set(keyOf(record.kind, record.id), record);
  }
  const isVisible = (record: LocalRecord | undefined): boolean => {
    if (record === undefined || record.deletedAt !== null) {
      return false;
    }
    if (record.kind === "loggedExercises") {
      return isVisible(byKey.get(keyOf("workoutSessions", record.parentId ?? "")));
    }
    if (record.kind === "loggedSets") {
      return isVisible(byKey.get(keyOf("loggedExercises", record.parentId ?? "")));
    }
    return true;
  };
  const visible: VisibleState = new Map();
  for (const [key, record] of byKey) {
    if (isVisible(record)) {
      visible.set(
        key,
        `${record.value}|tag=${record.tag}|parent=${record.parentId}|exercise=${record.exerciseId}`,
      );
    }
  }
  return visible;
}

export type ServerFault = {
  // Records whose upserts the server permanently rejects, to model a poison entry.
  poisonIds: Set<string>;
};

export class SimServer {
  readonly fault: ServerFault = { poisonIds: new Set() };
  readonly acceptedWrites: { kind: Kind; id: string; status: string; at: number; detail?: string }[] = [];

  constructor(
    readonly t: ConvexHarness,
    private readonly clock: () => number,
  ) {}

  // Server-side Date.now() follows simulated time.
  setServerTime(): void {
    vi.setSystemTime(Math.round(this.clock() * 1000));
  }

  async upsert(kind: Kind, payload: Record<string, unknown>): Promise<MutationResult> {
    this.setServerTime();
    if (this.fault.poisonIds.has(String(payload.clientId))) {
      throw new ConvexError({ code: "invalidPayload", message: "Simulated server validation rejection" });
    }
    const result = (await this.t
      .withIdentity(owner)
      .mutation(upsertFunction(kind), { record: payload })) as MutationResult;
    this.acceptedWrites.push({
      kind,
      id: String(payload.clientId),
      status: result.status,
      at: this.clock(),
      detail: `${String(payload[valueField(kind)])} raw=${Number(payload.updatedAt).toFixed(3)}`,
    });
    return result;
  }

  async tombstone(kind: Kind, id: string, deletedAt: number): Promise<MutationResult> {
    this.setServerTime();
    const result = (await this.t
      .withIdentity(owner)
      .mutation(api.sync.tombstone, { entityKind: kind, clientId: id, deletedAt })) as MutationResult;
    this.acceptedWrites.push({ kind, id, status: result.status, at: this.clock() });
    return result;
  }

  async fetch(cursors: Cursors, limit: number): Promise<FetchResponse> {
    this.setServerTime();
    return (await this.t
      .withIdentity(owner)
      .mutation(api.sync.fetchChangesOnce, { cursors, limit })) as FetchResponse;
  }

  // Writes a row directly, as an older server left it.
  async insertRaw(record: LocalRecord, serverUpdatedAt: number): Promise<void> {
    await this.t.run(async (ctx) => {
      await ctx.db.insert(record.kind, {
        ...payloadFor(record),
        ownerTokenIdentifier: owner.tokenIdentifier,
        serverUpdatedAt,
      });
    });
  }

  async records(): Promise<LocalRecord[]> {
    return await this.t.run(async (ctx) => {
      const all: LocalRecord[] = [];
      for (const kind of syncedKinds) {
        const rows = (await ctx.db.query(kind).collect()) as RemoteRecord[];
        all.push(...rows.map((row) => recordFromRemote(kind, row)));
      }
      return all;
    });
  }
}

type Network = {
  online: boolean;
  dropRequestRate: number;
  dropResponseRate: number;
};

// What the harness knows about every operation, for the data-loss oracle.
export class OperationLog {
  readonly created = new Map<string, { kind: Kind; parentKey: string | null }>();
  readonly deleted = new Set<string>();
  readonly writtenValues = new Map<string, Set<string>>();
  // Writes (by tag) that a later write replaced after its device had seen
  // them. A causally superseded write must never be the final state.
  readonly superseded = new Map<string, Set<string>>();
  readonly trace: string[] = [];

  noteCreate(record: LocalRecord): void {
    const key = keyOf(record.kind, record.id);
    const parentKind: Kind | null =
      record.kind === "loggedExercises"
        ? "workoutSessions"
        : record.kind === "loggedSets"
          ? "loggedExercises"
          : null;
    this.created.set(key, {
      kind: record.kind,
      parentKey: parentKind === null ? null : keyOf(parentKind, record.parentId ?? ""),
    });
    this.noteWrite(key, record.value);
  }

  noteWrite(key: string, value: string): void {
    const values = this.writtenValues.get(key) ?? new Set<string>();
    values.add(value);
    this.writtenValues.set(key, values);
  }

  noteSupersede(key: string, previousTag: string, next: string): void {
    const previous = previousTag;
    if (previous === next) {
      return;
    }
    const values = this.superseded.get(key) ?? new Set<string>();
    values.add(previous);
    this.superseded.set(key, values);
  }

  isDeletedByPolicy(key: string): boolean {
    let current: string | null = key;
    while (current !== null) {
      if (this.deleted.has(current)) {
        return true;
      }
      current = this.created.get(current)?.parentKey ?? null;
    }
    return false;
  }
}

type PushOutcome = { completed: boolean; didPush: boolean; hasMore: boolean };

export class SimDevice {
  readonly records = new Map<string, LocalRecord>();
  readonly outbox = new Map<string, OutboxEntry>();
  cursors: Cursors = {
    userSettings: 0,
    exercises: 0,
    workoutSessions: 0,
    loggedExercises: 0,
    loggedSets: 0,
  };
  clockOffset = 0;
  readonly network: Network = { online: true, dropRequestRate: 0, dropResponseRate: 0 };
  activeRun: AsyncGenerator<string, void, void> | null = null;
  private valueCounter = 0;
  private idCounter = 0;

  constructor(
    readonly name: string,
    readonly rule: ClientRule,
    private readonly server: SimServer,
    private readonly rng: Rng,
    private readonly simClock: () => number,
    private readonly log: OperationLog,
    private readonly fleetHasFastClock: () => boolean = () => false,
  ) {}

  now(): number {
    return this.simClock() + this.clockOffset;
  }

  // Legacy builds stamp edits with the device clock. Current builds stamp a
  // hybrid-logical time, so an edit always outranks the version it replaced.
  private editStamp(previous: LocalRecord | undefined): number {
    const now = this.now();
    if (this.rule === "legacy" || previous === undefined) {
      return now;
    }
    return Math.max(now, previous.updatedAt + millisecond);
  }

  get(kind: Kind, id: string | null): LocalRecord | undefined {
    return id === null ? undefined : this.records.get(keyOf(kind, id));
  }

  private put(record: LocalRecord): void {
    this.records.set(keyOf(record.kind, record.id), record);
  }

  children(kind: Kind, parentId: string): LocalRecord[] {
    return [...this.records.values()].filter(
      (record) => record.kind === kind && record.parentId === parentId,
    );
  }

  visible(): VisibleState {
    return visibleState(this.records.values());
  }

  private visibleRecords(kind?: Kind): LocalRecord[] {
    const visible = this.visible();
    return [...this.records.values()].filter(
      (record) =>
        visible.has(keyOf(record.kind, record.id)) && (kind === undefined || record.kind === kind),
    );
  }

  private nextTag(): string {
    this.valueCounter += 1;
    return `${this.name}-w${this.valueCounter}`;
  }

  // Legacy builds with slow clocks lose causally later writes by design; the
  // oracle checks causality only where the client rule can keep it.
  // Whether the oracle may hold this device's edits to causal order. Current
  // builds keep it under any clocks. An installed build with a slow clock
  // loses its causally later edits, and its pull lets any version stamped
  // ahead of its own replace a pending local edit, so its causality holds
  // only while no device in the fleet runs fast.
  private get keepsCausality(): boolean {
    return this.rule === "current" || (this.clockOffset >= 0 && !this.fleetHasFastClock());
  }

  private nextValue(): string {
    this.valueCounter += 1;
    return `${this.name}-v${this.valueCounter}`;
  }

  private nextId(prefix: string): string {
    this.idCounter += 1;
    return `${this.name}-${prefix}${this.idCounter}`;
  }

  // MARK: Outbox recorder (port of SyncOutboxRecorder)

  private recordCreate(kind: Kind, id: string): void {
    const now = this.now();
    const entry = this.outbox.get(keyOf(kind, id));
    if (entry !== undefined) {
      if (entry.operation !== "delete") {
        entry.operation = "create";
      }
      this.refreshPending(entry, now);
      return;
    }
    this.outbox.set(keyOf(kind, id), this.newEntry(kind, id, "create", now));
  }

  private recordUpdate(kind: Kind, id: string): void {
    const now = this.now();
    const entry = this.outbox.get(keyOf(kind, id));
    if (entry !== undefined) {
      if (entry.operation !== "delete") {
        entry.operation = entry.operation === "create" ? "create" : "update";
      }
      this.refreshPending(entry, now);
      return;
    }
    this.outbox.set(keyOf(kind, id), this.newEntry(kind, id, "update", now));
  }

  recordDelete(kind: Kind, id: string): void {
    const now = this.now();
    const entry = this.outbox.get(keyOf(kind, id));
    if (entry !== undefined) {
      if (entry.operation === "create" && entry.attemptCount === 0 && entry.status === "pending") {
        this.outbox.delete(keyOf(kind, id));
        return;
      }
      entry.operation = "delete";
      entry.createdAt = now;
      this.refreshPending(entry, now);
      return;
    }
    this.outbox.set(keyOf(kind, id), this.newEntry(kind, id, "delete", now));
  }

  private newEntry(kind: Kind, id: string, operation: Operation, now: number): OutboxEntry {
    return {
      kind,
      id,
      operation,
      status: "pending",
      createdAt: now,
      updatedAt: now,
      attemptCount: 0,
      rejectionCount: 0,
      firstRejectedAt: null,
      nextAttemptAt: null,
    };
  }

  private refreshPending(entry: OutboxEntry, now: number): void {
    entry.status = "pending";
    entry.updatedAt = now;
    entry.nextAttemptAt = null;
  }

  hasActiveEntry(kind: Kind, id: string): boolean {
    return this.outbox.has(keyOf(kind, id));
  }

  // MARK: Seeding damage that an older server left behind

  seedRecord(record: LocalRecord): void {
    this.put({ ...record, syncBase: record.syncBase ?? record.updatedAt });
  }

  seedEntry(kind: Kind, id: string, operation: Operation, status: "pending" | "failed", attemptCount: number): void {
    const entry = this.newEntry(kind, id, operation, this.now());
    entry.status = status;
    entry.attemptCount = attemptCount;
    this.outbox.set(keyOf(kind, id), entry);
  }

  seedCursors(cursors: Partial<Cursors>): void {
    this.cursors = { ...this.cursors, ...cursors };
  }

  // The one-time step a current build runs after updating: send every local
  // delete again. The server ignores ones it already has, and applies the
  // ones an older server rejected or later undid.
  reassertLocalDeletions(): number {
    let count = 0;
    for (const record of this.records.values()) {
      if (record.deletedAt !== null && !this.hasActiveEntry(record.kind, record.id)) {
        this.outbox.set(keyOf(record.kind, record.id), this.newEntry(record.kind, record.id, "delete", this.now()));
        count += 1;
      }
    }
    this.log.trace.push(`${this.name} re-sends ${count} local deletes after updating`);
    return count;
  }

  // MARK: User operations

  createExercise(): void {
    const now = this.now();
    const record: LocalRecord = {
      kind: "exercises",
      id: this.nextId("ex"),
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      value: this.nextValue(),
      tag: this.nextTag(),
      parentId: null,
      exerciseId: null,
    };
    this.put(record);
    this.recordCreate(record.kind, record.id);
    this.log.noteCreate(record);
    this.log.trace.push(`${this.name} create ${record.kind}:${record.id}`);
  }

  createWorkout(): void {
    const now = this.now();
    const session: LocalRecord = {
      kind: "workoutSessions",
      id: this.nextId("ws"),
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      value: this.nextValue(),
      tag: this.nextTag(),
      parentId: null,
      exerciseId: null,
    };
    const graph: LocalRecord[] = [session];
    // The exercise picker offers live exercises only.
    const exercises = [...this.records.values()].filter(
      (record) => record.kind === "exercises" && record.deletedAt === null,
    );
    const exerciseCount = 1 + this.rng.int(2);
    for (let index = 0; index < exerciseCount; index++) {
      const loggedExercise: LocalRecord = {
        kind: "loggedExercises",
        id: this.nextId("le"),
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        value: this.nextValue(),
        tag: this.nextTag(),
        parentId: session.id,
        // A workout may reference an exercise that another device has deleted (#94).
        exerciseId: exercises.length > 0 && this.rng.chance(0.7) ? this.rng.pick(exercises).id : null,
      };
      graph.push(loggedExercise);
      const setCount = 1 + this.rng.int(2);
      for (let setIndex = 0; setIndex < setCount; setIndex++) {
        graph.push({
          kind: "loggedSets",
          id: this.nextId("set"),
          createdAt: now,
          updatedAt: now,
          deletedAt: null,
          value: this.nextValue(),
          tag: this.nextTag(),
          parentId: loggedExercise.id,
          exerciseId: null,
        });
      }
    }
    for (const record of graph) {
      this.put(record);
      this.recordCreate(record.kind, record.id);
      this.log.noteCreate(record);
    }
    this.log.trace.push(`${this.name} create workout ${session.id} (${graph.length} records)`);
  }

  private sessionOf(record: LocalRecord): LocalRecord | undefined {
    if (record.kind === "workoutSessions") {
      return record;
    }
    if (record.kind === "loggedExercises") {
      return this.get("workoutSessions", record.parentId);
    }
    if (record.kind === "loggedSets") {
      const loggedExercise = this.get("loggedExercises", record.parentId);
      return loggedExercise === undefined ? undefined : this.sessionOf(loggedExercise);
    }
    return undefined;
  }

  // A completed-workout edit stamps the session too, as WorkoutHistoryMutationService does.
  private touchSession(record: LocalRecord): void {
    const session = this.sessionOf(record);
    if (session === undefined || session === record) {
      return;
    }
    const tag = this.nextTag();
    if (this.keepsCausality) {
      this.log.noteSupersede(keyOf(session.kind, session.id), session.tag, tag);
    }
    session.tag = tag;
    session.updatedAt = this.editStamp(session);
    this.recordUpdate(session.kind, session.id);
  }

  editValue(record: LocalRecord, value = this.nextValue()): string {
    const key = keyOf(record.kind, record.id);
    const tag = this.nextTag();
    if (this.keepsCausality) {
      this.log.noteSupersede(key, record.tag, tag);
    }
    record.updatedAt = this.editStamp(record);
    record.value = value;
    record.tag = tag;
    this.recordUpdate(record.kind, record.id);
    this.touchSession(record);
    this.log.noteWrite(key, value);
    this.log.trace.push(`${this.name} edit ${key} -> ${value} @${record.updatedAt.toFixed(3)}`);
    return value;
  }

  addSet(loggedExercise: LocalRecord): void {
    const now = this.now();
    const set: LocalRecord = {
      kind: "loggedSets",
      id: this.nextId("set"),
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      value: this.nextValue(),
      tag: this.nextTag(),
      parentId: loggedExercise.id,
      exerciseId: null,
    };
    this.put(set);
    this.recordCreate(set.kind, set.id);
    this.touchSession(set);
    this.log.noteCreate(set);
    this.log.trace.push(`${this.name} add set ${set.id} to ${loggedExercise.id}`);
  }

  private markDeleted(record: LocalRecord): void {
    const now = this.now();
    record.deletedAt = now;
    record.updatedAt = this.rule === "legacy" ? now : Math.max(now, record.updatedAt + millisecond);
  }

  deleteRecord(record: LocalRecord): void {
    const key = keyOf(record.kind, record.id);
    if (record.kind === "workoutSessions") {
      // markDeletedCascade, then a delete entry for every record in the graph.
      this.markDeleted(record);
      this.recordDelete(record.kind, record.id);
      for (const loggedExercise of this.children("loggedExercises", record.id)) {
        this.markDeleted(loggedExercise);
        this.recordDelete(loggedExercise.kind, loggedExercise.id);
        for (const set of this.children("loggedSets", loggedExercise.id)) {
          this.markDeleted(set);
          this.recordDelete(set.kind, set.id);
        }
      }
    } else {
      this.markDeleted(record);
      this.recordDelete(record.kind, record.id);
      this.touchSession(record);
    }
    this.log.deleted.add(key);
    this.log.trace.push(`${this.name} delete ${key}`);
  }

  randomUserOperation(): void {
    const visible = this.visibleRecords();
    const operation = this.rng.weighted({
      createWorkout: visible.length < 4 ? 4 : 1,
      createExercise: 1,
      edit: visible.length > 0 ? 5 : 0,
      addSet: visible.length > 0 ? 2 : 0,
      deleteSet: visible.length > 0 ? 1 : 0,
      deleteWorkout: visible.length > 0 ? 1.5 : 0,
      deleteExercise: visible.length > 0 ? 0.5 : 0,
    });
    switch (operation) {
      case "createWorkout":
        this.createWorkout();
        return;
      case "createExercise":
        this.createExercise();
        return;
      case "edit":
        this.editValue(this.rng.pick(visible));
        return;
      case "addSet": {
        const loggedExercises = this.visibleRecords("loggedExercises");
        if (loggedExercises.length > 0) this.addSet(this.rng.pick(loggedExercises));
        return;
      }
      case "deleteSet": {
        const sets = this.visibleRecords("loggedSets");
        if (sets.length > 0) this.deleteRecord(this.rng.pick(sets));
        return;
      }
      case "deleteWorkout": {
        const sessions = this.visibleRecords("workoutSessions");
        if (sessions.length > 0) this.deleteRecord(this.rng.pick(sessions));
        return;
      }
      case "deleteExercise": {
        const exercises = this.visibleRecords("exercises");
        if (exercises.length === 0) return;
        const exercise = this.rng.pick(exercises);
        // Exercise.removalOutcome archives, a field edit, when local history uses it.
        const hasLocalHistory = [...this.records.values()].some(
          (record) => record.kind === "loggedExercises" && record.exerciseId === exercise.id,
        );
        if (hasLocalHistory) {
          this.editValue(exercise);
        } else {
          this.deleteRecord(exercise);
        }
        return;
      }
    }
  }

  // MARK: Network

  private async call<T>(request: () => Promise<T>): Promise<T> {
    if (!this.network.online) {
      throw new TransientNetworkError("offline");
    }
    if (this.rng.chance(this.network.dropRequestRate)) {
      throw new TransientNetworkError("request lost");
    }
    const response = await request();
    if (this.rng.chance(this.network.dropResponseRate)) {
      throw new TransientNetworkError("response lost after the server applied the request");
    }
    return response;
  }

  // MARK: Sync run (port of SyncCoordinator.run)

  startRun(): void {
    if (this.activeRun === null) {
      this.activeRun = this.run();
    }
  }

  // The lowest change-feed position this run skipped because local intent
  // was pending. Rewound after the push, so a push that ends without a
  // server verdict cannot leave the server's version unpulled.
  private keptLocalFloor = new Map<Kind, number>();

  private rewindPastKeptLocalRecords(): void {
    for (const [kind, floor] of this.keptLocalFloor) {
      this.cursors[kind] = Math.min(this.cursors[kind], Math.max(0, floor - 1));
    }
    this.keptLocalFloor.clear();
  }

  private async *run(): AsyncGenerator<string, void, void> {
    try {
      this.keptLocalFloor.clear();
      yield* this.pull();
      const push = yield* this.push();
      if (this.rule === "current") this.rewindPastKeptLocalRecords();
      if (!push.completed || push.hasMore) {
        return;
      }
      if (push.didPush) {
        yield* this.pull();
      }
    } catch (error) {
      if (error instanceof TransientNetworkError) {
        return;
      }
      if (error instanceof ConvexError) {
        return;
      }
      throw error;
    }
  }

  private async *pull(): AsyncGenerator<string, void, void> {
    const fetchCursors: Cursors = { ...this.cursors };
    let loggedExercisesBlocked = false;
    let loggedSetsBlocked = false;
    let hasMore = true;
    while (hasMore) {
      yield "fetch";
      const response = await this.call(() => this.server.fetch(fetchCursors, pullPageLimit));
      // The response is in flight: other devices and local edits can run now.
      yield "fetched";
      for (const remote of response.exercises) {
        this.applyTopLevel("exercises", remote);
      }
      const sessionsCursor = this.applySessions(response.workoutSessions);
      const loggedExercises = this.applyChildren("loggedExercises", response.loggedExercises, response.hasMore);
      const sets = this.applyChildren("loggedSets", response.loggedSets, response.hasMore);

      fetchCursors.exercises = Math.max(fetchCursors.exercises, response.cursors.exercises);
      fetchCursors.workoutSessions = Math.max(fetchCursors.workoutSessions, response.cursors.workoutSessions);
      fetchCursors.loggedExercises = nextChildFetchCursor(
        fetchCursors.loggedExercises,
        response.cursors.loggedExercises,
        loggedExercises,
      );
      fetchCursors.loggedSets = nextChildFetchCursor(fetchCursors.loggedSets, response.cursors.loggedSets, sets);
      this.cursors.exercises = Math.max(this.cursors.exercises, response.cursors.exercises);
      if (sessionsCursor !== null) {
        this.cursors.workoutSessions = Math.max(this.cursors.workoutSessions, sessionsCursor);
      }
      if (loggedExercises.appliedCursor !== null && !loggedExercisesBlocked) {
        this.cursors.loggedExercises = Math.max(this.cursors.loggedExercises, loggedExercises.appliedCursor);
      }
      loggedExercisesBlocked ||= loggedExercises.skippedMissingParent;
      if (sets.appliedCursor !== null && !loggedSetsBlocked) {
        this.cursors.loggedSets = Math.max(this.cursors.loggedSets, sets.appliedCursor);
      }
      loggedSetsBlocked ||= sets.skippedMissingParent;
      hasMore = Object.values(response.hasMore).some(Boolean);
    }
  }

  // Returns whether the incoming version replaces the local one.
  private shouldApply(local: LocalRecord, remote: RemoteRecord): boolean {
    if (this.rule === "legacy") {
      // SyncConflictResolver.decision with allowsIncomingRestore: false.
      if (remote.updatedAt <= local.updatedAt) return false;
      if (local.deletedAt !== null && remote.deletedAt === null) return false;
      return true;
    }
    // Current rule: deletes win and the server decides everything else.
    if (remote.deletedAt !== null) return true;
    if (local.deletedAt !== null) {
      if (!this.hasActiveEntry(local.kind, local.id)) {
        // The server holds a live copy of something this device deleted, which
        // only an older server could have produced. Re-assert the delete.
        this.recordDelete(local.kind, local.id);
      }
      return false;
    }
    if (this.hasActiveEntry(local.kind, local.id)) {
      const floor = this.keptLocalFloor.get(local.kind);
      this.keptLocalFloor.set(local.kind, Math.min(floor ?? Infinity, remote.serverUpdatedAt));
      return false;
    }
    return true;
  }

  private applyRemote(kind: Kind, remote: RemoteRecord, local: LocalRecord): void {
    const incoming = recordFromRemote(kind, remote);
    Object.assign(local, incoming);
    if (kind === "workoutSessions" && local.deletedAt !== null) {
      this.cascadeRemoteSessionDeletion(local, local.deletedAt);
    }
  }

  private cascadeRemoteSessionDeletion(session: LocalRecord, deletedAt: number): void {
    for (const loggedExercise of this.children("loggedExercises", session.id)) {
      loggedExercise.deletedAt ??= deletedAt;
      loggedExercise.updatedAt = Math.max(loggedExercise.updatedAt, deletedAt);
      for (const set of this.children("loggedSets", loggedExercise.id)) {
        set.deletedAt ??= deletedAt;
        set.updatedAt = Math.max(set.updatedAt, deletedAt);
      }
    }
  }

  private applyTopLevel(kind: Kind, remote: RemoteRecord): void {
    const local = this.get(kind, remote.clientId);
    if (local === undefined) {
      // Exercises import even as tombstones, as the app does.
      this.put(recordFromRemote(kind, remote));
      return;
    }
    if (this.shouldApply(local, remote)) {
      this.applyRemote(kind, remote, local);
    }
  }

  private applySessions(records: RemoteRecord[]): number | null {
    let applied: number | null = null;
    for (const remote of records) {
      const local = this.get("workoutSessions", remote.clientId);
      if (local !== undefined) {
        if (this.shouldApply(local, remote)) {
          this.applyRemote("workoutSessions", remote, local);
        }
      } else if (remote.deletedAt === null) {
        this.put(recordFromRemote("workoutSessions", remote));
      }
      applied = Math.max(applied ?? 0, remote.serverUpdatedAt);
    }
    return applied;
  }

  private applyChildren(
    kind: "loggedExercises" | "loggedSets",
    records: RemoteRecord[],
    hasMore: HasMore,
  ): ChildApplyResult {
    let appliedCursor: number | null = null;
    let skippedMissingParent = false;
    let canAdvance = true;
    const recordApplied = (serverUpdatedAt: number) => {
      if (canAdvance) appliedCursor = Math.max(appliedCursor ?? 0, serverUpdatedAt);
    };
    const parentStreamHasMore =
      kind === "loggedExercises"
        ? hasMore.workoutSessions
        : hasMore.exercises || hasMore.workoutSessions || hasMore.loggedExercises;

    for (const remote of records) {
      const incoming = recordFromRemote(kind, remote);
      const parent = this.get(kind === "loggedExercises" ? "workoutSessions" : "loggedExercises", incoming.parentId);
      if (parent === undefined) {
        if (remote.deletedAt !== null) {
          // A placeholder tombstone has no parent id; current builds still
          // apply it to a copy they hold.
          const held = this.get(kind, remote.clientId);
          if (this.rule === "current" && held !== undefined && this.shouldApply(held, remote)) {
            this.applyRemote(kind, remote, held);
          }
          recordApplied(remote.serverUpdatedAt);
          continue;
        }
        if (!parentStreamHasMore) {
          canAdvance = false;
          skippedMissingParent = true;
          continue;
        }
        return { appliedCursor, skippedMissingParent: false };
      }
      if (kind === "loggedExercises" && incoming.exerciseId !== null && this.get("exercises", incoming.exerciseId) === undefined) {
        if (remote.deletedAt !== null) {
          recordApplied(remote.serverUpdatedAt);
          continue;
        }
        if (!hasMore.exercises) {
          canAdvance = false;
          skippedMissingParent = true;
          continue;
        }
        return { appliedCursor, skippedMissingParent: false };
      }
      const local = this.get(kind, remote.clientId);
      if (local !== undefined) {
        if (this.shouldApply(local, remote)) {
          this.applyRemote(kind, remote, local);
        }
      } else if (remote.deletedAt === null) {
        this.put(incoming);
      }
      recordApplied(remote.serverUpdatedAt);
    }
    return { appliedCursor, skippedMissingParent };
  }

  private async *push(): AsyncGenerator<string, PushOutcome, void> {
    const now = this.now();
    const eligible = [...this.outbox.values()].filter((entry) => {
      if (entry.status === "blocked" || entry.status === "inFlight") return false;
      if (this.rule === "legacy") return true;
      // A clock that jumped backwards must not strand an entry past its longest backoff.
      return (
        entry.nextAttemptAt === null ||
        entry.nextAttemptAt <= now ||
        entry.nextAttemptAt - now > maxBackoffSeconds
      );
    });
    const entries = eligible
      .sort((lhs, rhs) => {
        const rank = legacyPushRank(lhs) - legacyPushRank(rhs);
        if (rank !== 0) return rank;
        if ((lhs.status === "failed") !== (rhs.status === "failed")) {
          return lhs.status === "failed" ? 1 : -1;
        }
        if (lhs.updatedAt !== rhs.updatedAt) return lhs.updatedAt - rhs.updatedAt;
        return lhs.createdAt - rhs.createdAt;
      })
      .slice(0, pushBatchLimit);
    const hasMore = eligible.length > pushBatchLimit;
    const rejectedThisRun = new Set<string>();

    for (const entry of entries) {
      if (this.rule === "current" && this.dependsOnRejected(entry, rejectedThisRun)) {
        continue;
      }
      const record = this.get(entry.kind, entry.id);
      if (record === undefined) {
        this.outbox.delete(keyOf(entry.kind, entry.id));
        continue;
      }
      const wasFailed = entry.status === "failed";
      entry.status = "inFlight";
      entry.attemptCount += 1;
      yield "push";
      let result: MutationResult;
      try {
        result = await this.call(() =>
          entry.operation === "delete"
            ? this.server.tombstone(entry.kind, entry.id, record.deletedAt ?? entry.createdAt)
            : this.server.upsert(entry.kind, payloadFor(record, this.rule === "current")),
        );
      } catch (error) {
        if (error instanceof TransientNetworkError) {
          if (entry.status === "inFlight") entry.status = wasFailed ? "failed" : "pending";
          return { completed: false, didPush: true, hasMore };
        }
        if (this.rule === "legacy") {
          if (entry.status === "inFlight") entry.status = "failed";
          return { completed: false, didPush: true, hasMore };
        }
        const kind = rejectionKind(error);
        if (kind === "accountWide") {
          // Nothing will succeed for this account right now; this record is fine.
          if (entry.status === "inFlight") entry.status = wasFailed ? "failed" : "pending";
          return { completed: false, didPush: true, hasMore };
        }
        rejectedThisRun.add(keyOf(entry.kind, entry.id));
        if (entry.status === "inFlight") {
          const now = this.now();
          if (kind === "record") {
            entry.rejectionCount += 1;
            entry.firstRejectedAt ??= now;
            this.requeueMissingParent(record);
          }
          const isDeadLetter =
            entry.rejectionCount >= rejectionsBeforeDeadLetter &&
            now - (entry.firstRejectedAt ?? now) >= rejectionWindowBeforeDeadLetterSeconds;
          entry.status = isDeadLetter ? "blocked" : "failed";
          entry.nextAttemptAt = now + Math.min(maxBackoffSeconds, 30 * 2 ** Math.max(0, entry.attemptCount - 1));
        }
        continue;
      }
      yield "pushed";
      if ((result.status === "inserted" || result.status === "updated") && result.updatedAt !== undefined) {
        // The local copy, edited since or not, now descends from what the server stored.
        record.syncBase = result.updatedAt;
      }
      if (result.status === "ignored_stale" && result.serverUpdatedAt !== undefined) {
        this.cursors[entry.kind] = Math.min(this.cursors[entry.kind], Math.max(0, result.serverUpdatedAt - 1));
      }
      // A local edit while the request was in flight re-pends the entry.
      if (entry.status === "inFlight") {
        this.outbox.delete(keyOf(entry.kind, entry.id));
      }
    }
    return { completed: true, didPush: entries.length > 0, hasMore };
  }

  // A parent the server never received holds this record back. Upload it
  // again if this device still has it and nothing is queued for it.
  private requeueMissingParent(record: LocalRecord): void {
    const parentKind: Kind | null =
      record.kind === "loggedExercises" ? "workoutSessions" : record.kind === "loggedSets" ? "loggedExercises" : null;
    const parent = parentKind === null ? undefined : this.get(parentKind, record.parentId);
    if (parent !== undefined && !this.hasActiveEntry(parent.kind, parent.id)) {
      this.recordUpdate(parent.kind, parent.id);
    }
  }

  private dependsOnRejected(entry: OutboxEntry, rejected: Set<string>): boolean {
    const record = this.get(entry.kind, entry.id);
    if (record === undefined || entry.operation === "delete") return false;
    let parentKind: Kind | null =
      record.kind === "loggedExercises" ? "workoutSessions" : record.kind === "loggedSets" ? "loggedExercises" : null;
    let parentId = record.parentId;
    while (parentKind !== null && parentId !== null) {
      const parentKey = keyOf(parentKind, parentId);
      const parentEntry = this.outbox.get(parentKey);
      if (rejected.has(parentKey) || (parentEntry !== undefined && parentEntry.status !== "pending" && parentEntry.status !== "inFlight")) {
        return true;
      }
      const parent = this.get(parentKind, parentId);
      parentKind = parentKind === "loggedExercises" ? "workoutSessions" : null;
      parentId = parent?.parentId ?? null;
    }
    return false;
  }

  async finishRun(maxSteps = 10_000): Promise<void> {
    let steps = 0;
    while (this.activeRun !== null) {
      const step = await this.activeRun.next();
      if (step.done) this.activeRun = null;
      if (++steps > maxSteps) throw new Error(`${this.name}: sync run did not finish`);
    }
  }

  outboxSummary(): string[] {
    return [...this.outbox.values()].map(
      (entry) => `${entry.kind}:${entry.id} ${entry.operation} ${entry.status} attempts=${entry.attemptCount}`,
    );
  }
}

type ChildApplyResult = { appliedCursor: number | null; skippedMissingParent: boolean };

function nextChildFetchCursor(current: number, responseCursor: number, result: ChildApplyResult): number {
  if (result.skippedMissingParent) return Math.max(current, responseCursor);
  if (result.appliedCursor !== null) return Math.max(current, result.appliedCursor);
  return current;
}

// MARK: Scenario runner

export type ClockProfile = "honest" | "jitter" | "fast" | "farFuture" | "slow" | "deadClock" | "jumpy";

export type FleetHooks = {
  // Seeds the fleet before any traffic, for example with older-server damage.
  prepare?: (fleet: Fleet) => Promise<void>;
  // Runs a server-side operation, such as a data repair, at this chaos step
  // (0 means before any traffic, at or past the last step means after it).
  repairAtStep?: number;
  repair?: (fleet: Fleet) => Promise<void>;
  // Current builds run their one-time update step at the start.
  currentBuildsReassertDeletes?: boolean;
};

export type FleetConfig = {
  seed: number;
  devices: { rule: ClientRule; clock: ClockProfile }[];
  steps: number;
  dropRequestRate: number;
  dropResponseRate: number;
  offlineRate: number;
  poison?: boolean;
};

const simulationEpoch = Date.UTC(2026, 0, 1) / 1000;
// More than ordinary clock jitter.
const fastClockThresholdSeconds = 2;

function initialOffset(profile: ClockProfile, rng: Rng): number {
  switch (profile) {
    case "honest":
      return 0;
    case "jitter":
      return rng.real(-2, 2);
    case "fast":
      return rng.real(60, 3600);
    case "farFuture":
      return 30 * 24 * 3600;
    case "slow":
      return -rng.real(60, 24 * 3600);
    case "deadClock":
      // A dead RTC restarts the clock at the reference date.
      return Date.UTC(2001, 0, 1) / 1000 - simulationEpoch;
    case "jumpy":
      return 0;
  }
}

export type FleetReport = {
  seed: number;
  failures: string[];
  trace: string[];
  stats: { steps: number; serverWrites: number; records: number };
};

export class Fleet {
  readonly rng: Rng;
  time = simulationEpoch;
  readonly server: SimServer;
  readonly log = new OperationLog();
  readonly devices: SimDevice[];

  constructor(
    t: ConvexHarness,
    readonly config: FleetConfig,
  ) {
    this.rng = new Rng(config.seed);
    this.server = new SimServer(t, () => this.time);
    this.devices = config.devices.map((device, index) => {
      const simDevice = new SimDevice(
        `d${index}${device.rule === "legacy" ? "L" : "C"}`,
        device.rule,
        this.server,
        new Rng(config.seed * 31 + index + 1),
        () => this.time,
        this.log,
        () => this.devices.some((other) => other.clockOffset > fastClockThresholdSeconds),
      );
      simDevice.clockOffset = initialOffset(device.clock, this.rng);
      simDevice.network.dropRequestRate = config.dropRequestRate;
      simDevice.network.dropResponseRate = config.dropResponseRate;
      return simDevice;
    });
  }

  private advanceTime(): void {
    this.time += this.rng.chance(0.03) ? this.rng.real(600, 8 * 3600) : this.rng.real(0.002, 20);
  }

  private async runRepairHook(hooks: FleetHooks, step: number): Promise<void> {
    if (hooks.repair !== undefined && (hooks.repairAtStep ?? 0) === step) {
      this.server.setServerTime();
      await hooks.repair(this);
      this.log.trace.push(`server repair at step ${step}`);
    }
  }

  async chaos(hooks: FleetHooks = {}): Promise<void> {
    for (let step = 0; step < this.config.steps; step++) {
      await this.runRepairHook(hooks, step);
      this.advanceTime();
      const device = this.rng.pick(this.devices);
      const profile = this.config.devices[this.devices.indexOf(device)].clock;
      if (device.activeRun !== null && this.rng.chance(0.65)) {
        const next = await device.activeRun.next();
        if (next.done) device.activeRun = null;
        continue;
      }
      const action = this.rng.weighted({
        userOperation: 6,
        sync: 3,
        toggleOnline: this.config.offlineRate,
        clockJump: profile === "jumpy" ? 1 : 0,
        poison: this.config.poison === true && this.server.fault.poisonIds.size === 0 ? 0.3 : 0,
      });
      switch (action) {
        case "userOperation":
          device.randomUserOperation();
          break;
        case "sync":
          device.startRun();
          break;
        case "toggleOnline":
          device.network.online = !device.network.online;
          this.log.trace.push(`${device.name} ${device.network.online ? "online" : "offline"}`);
          break;
        case "clockJump":
          // Someone sets the date by hand, forwards or backwards.
          device.clockOffset = this.rng.pick([-90 * 86400, -3600, 0, 3600, 45 * 86400]);
          this.log.trace.push(`${device.name} clock offset ${device.clockOffset}`);
          break;
        case "poison": {
          const candidates = [...device.records.values()].filter(
            (record) => record.kind === "loggedSets" && device.hasActiveEntry(record.kind, record.id),
          );
          if (candidates.length > 0) {
            const poisoned = this.rng.pick(candidates);
            this.server.fault.poisonIds.add(poisoned.id);
            this.log.trace.push(`server poisons ${poisoned.kind}:${poisoned.id}`);
          }
          break;
        }
      }
    }
  }

  // Faults off, everyone online, clocks left as they are. Sync until stable.
  async quiesce(maxRounds = 14): Promise<boolean> {
    for (const device of this.devices) {
      device.network.online = true;
      device.network.dropRequestRate = 0;
      device.network.dropResponseRate = 0;
      await device.finishRun();
    }
    let previous = "";
    for (let round = 0; round < maxRounds; round++) {
      // Long enough for every backoff to expire.
      this.time += 7 * 3600;
      for (const device of this.devices) {
        device.startRun();
        await device.finishRun();
      }
      const fingerprint = JSON.stringify(
        this.devices.map((device) => [[...device.visible()].sort(), device.outboxSummary().sort()]),
      );
      if (fingerprint === previous) {
        return true;
      }
      previous = fingerprint;
    }
    return false;
  }

  async check(): Promise<string[]> {
    const failures: string[] = [];
    const serverRecords = await this.server.records();
    const serverVisible = visibleState(serverRecords);
    const poisoned = this.server.fault.poisonIds;
    const isPoisonRelated = (key: string): boolean => {
      let current: string | null = key;
      while (current !== null) {
        const id = current.slice(current.indexOf(":") + 1);
        if (poisoned.has(id)) return true;
        current = this.log.created.get(current)?.parentKey ?? null;
      }
      return false;
    };

    // I1: every device sees exactly what the server holds.
    for (const device of this.devices) {
      const diff = diffVisible(device.visible(), serverVisible, isPoisonRelated);
      if (diff.length > 0) {
        failures.push(`I1 ${device.name} diverges from the server: ${diff.slice(0, 6).join("; ")}`);
      }
    }

    // I2: nothing stays in an outbox, apart from an injected poison entry.
    for (const device of this.devices) {
      const stuck = [...device.outbox.values()].filter((entry) => !poisoned.has(entry.id));
      if (stuck.length > 0) {
        failures.push(`I2 ${device.name} outbox not drained: ${device.outboxSummary().slice(0, 6).join("; ")}`);
      }
      for (const entry of device.outbox.values()) {
        if (poisoned.has(entry.id) && device.rule === "current" && entry.status !== "blocked" && entry.status !== "failed") {
          failures.push(`I5 ${device.name} poison entry ${entry.id} is ${entry.status}, expected failed or blocked`);
        }
      }
    }

    // Server-side structure: a tombstoned parent never has a live child.
    const serverByKey = new Map(serverRecords.map((record) => [keyOf(record.kind, record.id), record]));
    for (const record of serverRecords) {
      if (record.deletedAt !== null || record.parentId === null) continue;
      const parentKind: Kind = record.kind === "loggedExercises" ? "workoutSessions" : "loggedExercises";
      const parent = serverByKey.get(keyOf(parentKind, record.parentId));
      if (parent !== undefined && parent.deletedAt !== null) {
        failures.push(`S live ${record.kind}:${record.id} under tombstoned ${parentKind}:${parent.id}`);
      }
    }

    // I4: no silent data loss.
    for (const [key] of this.log.created) {
      if (isPoisonRelated(key)) continue;
      const deleted = this.log.isDeletedByPolicy(key);
      const visible = serverVisible.has(key);
      if (deleted && visible) {
        failures.push(`I4 resurrected: ${key} was deleted but is visible`);
      }
      if (!deleted && !visible) {
        failures.push(`I4 lost: ${key} was created, never deleted, and is not visible`);
      }
    }
    for (const [key, snapshot] of serverVisible) {
      if (isPoisonRelated(key)) continue;
      const value = snapshot.slice(0, snapshot.indexOf("|"));
      const tag = /\|tag=([^|]*)\|/.exec(snapshot)?.[1] ?? "";
      if (!(this.log.writtenValues.get(key)?.has(value) ?? false)) {
        failures.push(`I4 invented value ${value} for ${key}`);
      }
      if (this.log.superseded.get(key)?.has(tag) ?? false) {
        failures.push(`I4 causally superseded write ${tag} (${value}) survived for ${key}`);
      }
    }
    return failures;
  }

  // I3: every live record is editable, then deletable, from every device
  // whose client rule can promise that.
  async checkEditability(): Promise<string[]> {
    const failures: string[] = [];
    // Current builds can edit anything. An installed build cannot when its
    // clock is slow; a fast one cannot replace a version stamped ahead of its
    // own clock (sync/merge.ts, incomingFieldsWin).
    const editors = this.devices.filter((device) => device.rule === "current" || device.clockOffset >= 0);
    const canEdit = (device: SimDevice, record: LocalRecord | undefined): boolean =>
      record !== undefined &&
      (device.rule === "current" ||
        device.clockOffset <= fastClockThresholdSeconds ||
        record.updatedAt < device.now());
    const poisoned = this.server.fault.poisonIds;
    for (const editor of editors) {
      const visibleKeys = [...editor.visible().keys()].filter((key) => {
        const id = key.slice(key.indexOf(":") + 1);
        return !poisoned.has(id) && canEdit(editor, editor.get(key.slice(0, key.indexOf(":")) as Kind, id));
      });
      if (visibleKeys.length === 0) continue;
      const key = visibleKeys[this.rng.int(visibleKeys.length)];
      const [kind, id] = [key.slice(0, key.indexOf(":")) as Kind, key.slice(key.indexOf(":") + 1)];
      const record = editor.get(kind, id);
      if (record === undefined) continue;
      this.time += 1;
      const value = editor.editValue(record);
      await this.quiesce();
      for (const device of this.devices) {
        const seen = device.visible().get(key);
        if (seen === undefined || !seen.startsWith(`${value}|`)) {
          failures.push(`I3 edit of ${key} by ${editor.name} not visible on ${device.name} (sees ${seen})`);
        }
      }
    }
    for (const deleter of editors) {
      const sessions = [...deleter.visible().keys()].filter(
        (key) => key.startsWith("workoutSessions:") && !poisoned.has(key.slice(key.indexOf(":") + 1)),
      );
      if (sessions.length === 0) continue;
      const key = sessions[this.rng.int(sessions.length)];
      const session = deleter.get("workoutSessions", key.slice(key.indexOf(":") + 1));
      if (session === undefined) continue;
      this.time += 1;
      deleter.deleteRecord(session);
      await this.quiesce();
      for (const device of this.devices) {
        if (device.visible().has(key)) {
          failures.push(`I3 delete of ${key} by ${deleter.name} did not reach ${device.name}`);
        }
      }
    }
    return failures;
  }
}

function diffVisible(
  actual: VisibleState,
  expected: VisibleState,
  ignore: (key: string) => boolean,
): string[] {
  const diff: string[] = [];
  for (const [key, value] of expected) {
    if (ignore(key)) continue;
    const seen = actual.get(key);
    if (seen !== value) diff.push(`${key}: device=${seen ?? "absent"} server=${value}`);
  }
  for (const [key, value] of actual) {
    if (ignore(key)) continue;
    if (!expected.has(key)) diff.push(`${key}: device=${value} server=absent`);
  }
  return diff;
}

export async function runFleet(
  t: ConvexHarness,
  config: FleetConfig,
  options: { editability?: boolean; hooks?: FleetHooks; onFinish?: (fleet: Fleet) => void } = {},
): Promise<FleetReport> {
  vi.useFakeTimers({ toFake: ["Date"] });
  try {
    const fleet = new Fleet(t, config);
    const hooks = options.hooks ?? {};
    await hooks.prepare?.(fleet);
    if (hooks.currentBuildsReassertDeletes === true) {
      for (const device of fleet.devices) {
        if (device.rule === "current") device.reassertLocalDeletions();
      }
    }
    await fleet.chaos(hooks);
    if (hooks.repair !== undefined && (hooks.repairAtStep ?? 0) >= config.steps) {
      fleet.server.setServerTime();
      await hooks.repair(fleet);
    }
    const settled = await fleet.quiesce();
    const failures = settled ? [] : ["Q devices did not reach a stable state within the round limit"];
    failures.push(...(await fleet.check()));
    if (failures.length === 0 && options.editability !== false) {
      failures.push(...(await fleet.checkEditability()));
      failures.push(...(await fleet.check()));
    }
    options.onFinish?.(fleet);
    return {
      seed: config.seed,
      failures,
      trace: fleet.log.trace,
      stats: {
        steps: config.steps,
        serverWrites: fleet.server.acceptedWrites.length,
        records: fleet.log.created.size,
      },
    };
  } finally {
    vi.useRealTimers();
  }
}
