// Shared vectors for the server's conflict rule. The Swift client's simulator
// carries a port of `sync/merge.ts` (BarosCore/Tests/BarosCoreTests/SyncSim),
// and checks it against the same file, so the two cannot drift apart.
//
// Regenerate after changing the rule:
//   SYNC_VECTORS_WRITE=1 pnpm vitest run convex/syncMergeVectors.test.ts
//
// File format, one vector per line:
//   storedCases: name -> StoredVersion, or null for no stored row.
//   upsert: [storedCase, incomingUpdatedAt, incomingDeletedAt, base, sameContent,
//            parentDeletedAt, expected], where base is "absent", null or a number,
//            and expected is [action, updatedAt, deletedAt, syncOrder, accepted,
//            takeIncomingFields], with null for a field the decision leaves out.
//   tombstone: [storedCase, deletedAt, expected], expected [action, updatedAt, deletedAt].
//   cascade: [childUpdatedAt, parentUpdatedAt, parentDeletedAt, updatedAt, deletedAt].
//   nowSeconds is the same for every vector.

import { describe, expect, test } from "vitest";
import {
  cascadedChildVersion,
  decideTombstone,
  decideUpsert,
  type IncomingVersion,
  type StoredVersion,
  type TombstoneDecision,
  type UpsertDecision,
} from "./sync/merge";

const vectorsPath = new URL("./syncSim/merge-vectors.json", import.meta.url);
// Node's fs, loaded untyped: the Convex tsconfig has no Node types.
type FileSystem = {
  readFileSync(path: URL, encoding: "utf8"): string;
  writeFileSync(path: URL, data: string): void;
};
const nodeFileSystem = "node:fs";
const environment = process.env as Record<string, string | undefined>;

const nowSeconds = 1050;
const storedCases: Record<string, StoredVersion | null> = {
  none: null,
  live: { createdAt: 900, updatedAt: 1000, deletedAt: null, serverUpdatedAt: 1_000_000 },
  liveWithSyncOrder: { createdAt: 900, updatedAt: 1000, deletedAt: null, serverUpdatedAt: 1_000_000, syncOrder: 1005 },
  liveFromFastClock: { createdAt: 900, updatedAt: 1100, deletedAt: null, serverUpdatedAt: 1_000_000 },
  deleted: { createdAt: 900, updatedAt: 1000, deletedAt: 990, serverUpdatedAt: 1_000_000 },
  placeholder: { createdAt: 0, updatedAt: 1000, deletedAt: 1000, serverUpdatedAt: 1_000_000 },
};
const incomingStamps = [990, 1000, 1000.0000005, 1010, 2000];
const bases: (number | null | "absent")[] = ["absent", null, 990, 1000, 1010];

function upsertTuple(decision: UpsertDecision): unknown[] {
  switch (decision.action) {
    case "ignore":
      return ["ignore", null, null, null, null, null];
    case "insert":
      return ["insert", decision.updatedAt, decision.deletedAt, decision.syncOrder, decision.accepted, null];
    case "patch":
      return [
        "patch",
        decision.updatedAt,
        decision.deletedAt,
        decision.syncOrder ?? null,
        decision.accepted,
        decision.takeIncomingFields,
      ];
  }
}

function tombstoneTuple(decision: TombstoneDecision): unknown[] {
  return decision.action === "alreadyDeleted"
    ? ["alreadyDeleted", null, null]
    : [decision.action, decision.updatedAt, decision.deletedAt];
}

function buildVectors() {
  const upsert: unknown[][] = [];
  for (const [name, stored] of Object.entries(storedCases)) {
    for (const updatedAt of incomingStamps) {
      for (const deleted of [false, true]) {
        for (const base of bases) {
          for (const sameContent of [false, true]) {
            for (const parentDeletedAt of [null, 995]) {
              const incoming: IncomingVersion = { updatedAt, deletedAt: deleted ? updatedAt : null };
              if (base !== "absent") incoming.baseUpdatedAt = base;
              const decision = decideUpsert(stored, incoming, { nowSeconds, sameContent, parentDeletedAt });
              upsert.push([name, updatedAt, incoming.deletedAt, base, sameContent, parentDeletedAt, upsertTuple(decision)]);
            }
          }
        }
      }
    }
  }
  const tombstone: unknown[][] = [];
  for (const [name, stored] of Object.entries(storedCases)) {
    for (const deletedAt of [990, 1000, 2000]) {
      tombstone.push([name, deletedAt, tombstoneTuple(decideTombstone(stored, deletedAt, nowSeconds))]);
    }
  }
  const cascade: unknown[][] = [];
  for (const childUpdatedAt of [900, 1000, 1100]) {
    for (const parent of [
      { updatedAt: 1000, deletedAt: 1000 },
      { updatedAt: 1000.001, deletedAt: 990 },
    ]) {
      const result = cascadedChildVersion({ updatedAt: childUpdatedAt }, parent);
      cascade.push([childUpdatedAt, parent.updatedAt, parent.deletedAt, result.updatedAt, result.deletedAt]);
    }
  }
  return { nowSeconds, storedCases, upsert, tombstone, cascade };
}

function serialize(vectors: ReturnType<typeof buildVectors>): string {
  // One vector per line keeps the file small and its diffs readable.
  const rows = (items: unknown[]) => `[\n${items.map((item) => JSON.stringify(item)).join(",\n")}\n]`;
  return [
    `{"nowSeconds": ${vectors.nowSeconds},`,
    `"storedCases": ${JSON.stringify(vectors.storedCases)},`,
    `"upsert": ${rows(vectors.upsert)},`,
    `"tombstone": ${rows(vectors.tombstone)},`,
    `"cascade": ${rows(vectors.cascade)}}`,
    "",
  ].join("\n");
}

describe("shared merge vectors", () => {
  test("the checked-in vectors match sync/merge.ts", async () => {
    const { readFileSync, writeFileSync } = (await import(/* @vite-ignore */ nodeFileSystem)) as FileSystem;
    const vectors = buildVectors();
    const json = serialize(vectors);
    if (environment.SYNC_VECTORS_WRITE === "1") {
      writeFileSync(vectorsPath, json);
    }
    expect(
      JSON.parse(readFileSync(vectorsPath, "utf8")),
      "Regenerate with SYNC_VECTORS_WRITE=1 after changing sync/merge.ts",
    ).toEqual(JSON.parse(json));
    expect(vectors.upsert.length).toBeGreaterThan(1000);
  });
});
