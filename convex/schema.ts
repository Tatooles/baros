import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const nullableString = v.union(v.string(), v.null());
const nullableNumber = v.union(v.number(), v.null());

const syncFields = {
  ownerTokenIdentifier: v.string(),
  clientId: v.string(),
  createdAt: v.number(),
  updatedAt: v.number(),
  deletedAt: nullableNumber,
  serverUpdatedAt: v.number(),
};

export default defineSchema({
  userSettings: defineTable({
    ...syncFields,
    weightUnitRaw: v.union(v.literal("pounds"), v.literal("kilograms")),
    defaultRestTimerSeconds: v.number(),
    hasCompletedOnboarding: v.boolean(),
  })
    .index("by_ownerTokenIdentifier_and_clientId", [
      "ownerTokenIdentifier",
      "clientId",
    ])
    .index("by_ownerTokenIdentifier_and_serverUpdatedAt", [
      "ownerTokenIdentifier",
      "serverUpdatedAt",
    ]),

  exercises: defineTable({
    ...syncFields,
    seedIdentifier: nullableString,
    name: v.string(),
    categoryRaw: v.string(),
    equipmentRaw: v.string(),
    primaryMuscleRaw: v.string(),
    primaryMuscleGroupRaw: v.optional(v.string()),
    notes: v.string(),
    isArchived: v.boolean(),
    isSeeded: v.boolean(),
  })
    .index("by_ownerTokenIdentifier_and_clientId", [
      "ownerTokenIdentifier",
      "clientId",
    ])
    .index("by_ownerTokenIdentifier_and_serverUpdatedAt", [
      "ownerTokenIdentifier",
      "serverUpdatedAt",
    ]),

  workoutSessions: defineTable({
    ...syncFields,
    title: v.string(),
    startedAt: v.number(),
    endedAt: nullableNumber,
    durationSeconds: v.number(),
    notes: v.string(),
    referenceNotes: nullableString,
    // Active sessions stay local-only for v1 and are intentionally excluded from Convex sync.
    statusRaw: v.union(v.literal("completed"), v.literal("discarded")),
    sourceRaw: v.union(
      v.literal("blank"),
      v.literal("pastWorkout"),
      v.literal("template"),
    ),
    sourceSessionID: nullableString,
    healthLinkID: nullableString,
  })
    .index("by_ownerTokenIdentifier_and_clientId", [
      "ownerTokenIdentifier",
      "clientId",
    ])
    .index("by_ownerTokenIdentifier_and_serverUpdatedAt", [
      "ownerTokenIdentifier",
      "serverUpdatedAt",
    ]),

  loggedExercises: defineTable({
    ...syncFields,
    sessionClientId: v.string(),
    exerciseClientId: nullableString,
    orderIndex: v.number(),
    exerciseSnapshotName: v.string(),
    exerciseSnapshotEquipmentRaw: v.optional(v.string()),
    exerciseSnapshotPrimaryMuscleGroupRaw: v.optional(v.string()),
    hasSnapshotMetadata: v.optional(v.boolean()),
    notes: v.string(),
    referenceNotes: nullableString,
  })
    .index("by_ownerTokenIdentifier_and_clientId", [
      "ownerTokenIdentifier",
      "clientId",
    ])
    .index("by_ownerTokenIdentifier_and_sessionClientId", [
      "ownerTokenIdentifier",
      "sessionClientId",
    ])
    .index("by_ownerTokenIdentifier_and_serverUpdatedAt", [
      "ownerTokenIdentifier",
      "serverUpdatedAt",
    ]),

  loggedSets: defineTable({
    ...syncFields,
    loggedExerciseClientId: v.string(),
    orderIndex: v.number(),
    weight: nullableNumber,
    reps: nullableNumber,
    rpe: nullableNumber,
    placeholderWeight: nullableNumber,
    placeholderReps: nullableNumber,
    placeholderRPE: nullableNumber,
    kindRaw: v.union(
      v.literal("working"),
      v.literal("warmup"),
      v.literal("drop"),
      v.literal("failure"),
    ),
    isCompleted: v.boolean(),
    completedAt: nullableNumber,
    notes: v.string(),
    healthLinkID: nullableString,
  })
    .index("by_ownerTokenIdentifier_and_clientId", [
      "ownerTokenIdentifier",
      "clientId",
    ])
    .index("by_ownerTokenIdentifier_and_loggedExerciseClientId", [
      "ownerTokenIdentifier",
      "loggedExerciseClientId",
    ])
    .index("by_ownerTokenIdentifier_and_serverUpdatedAt", [
      "ownerTokenIdentifier",
      "serverUpdatedAt",
    ]),
});
