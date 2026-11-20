import { v } from "convex/values";

const nullableString = v.union(v.string(), v.null());
const nullableNumber = v.union(v.number(), v.null());

const syncPayloadFields = {
  clientId: v.string(),
  createdAt: v.number(),
  updatedAt: v.number(),
  deletedAt: nullableNumber,
};

export const entityKindValidator = v.union(
  v.literal("userSettings"),
  v.literal("exercises"),
  v.literal("workoutSessions"),
  v.literal("loggedExercises"),
  v.literal("loggedSets"),
  v.literal("workoutTemplates"),
);

export const userSettingsPayloadValidator = v.object({
  ...syncPayloadFields,
  weightUnitRaw: v.union(v.literal("pounds"), v.literal("kilograms")),
  defaultRestTimerSeconds: v.number(),
  hasCompletedOnboarding: v.boolean(),
});

export const exercisePayloadValidator = v.object({
  ...syncPayloadFields,
  seedIdentifier: nullableString,
  name: v.string(),
  categoryRaw: v.string(),
  equipmentRaw: v.string(),
  primaryMuscleRaw: v.string(),
  primaryMuscleGroupRaw: v.optional(v.string()),
  notes: v.string(),
  isArchived: v.boolean(),
  isSeeded: v.boolean(),
  // "reps" or "duration". Builds from before timed exercises omit it, and
  // the upsert's patch keeps the stored value.
  trackingMethodRaw: v.optional(v.string()),
});

export const workoutSessionPayloadValidator = v.object({
  ...syncPayloadFields,
  title: v.string(),
  startedAt: v.number(),
  endedAt: nullableNumber,
  durationSeconds: v.number(),
  notes: v.string(),
  referenceNotes: nullableString,
  statusRaw: v.union(v.literal("completed"), v.literal("discarded")),
  sourceRaw: v.union(
    v.literal("blank"),
    v.literal("pastWorkout"),
    v.literal("template"),
  ),
  sourceSessionID: nullableString,
  healthLinkID: nullableString,
  // The template a workout started from. Builds from before the link omit
  // it, and the upsert's patch keeps the stored value.
  sourceTemplateID: v.optional(nullableString),
});

export const loggedExercisePayloadValidator = v.object({
  ...syncPayloadFields,
  sessionClientId: v.string(),
  exerciseClientId: nullableString,
  orderIndex: v.number(),
  exerciseSnapshotName: v.string(),
  exerciseSnapshotEquipmentRaw: v.optional(v.string()),
  exerciseSnapshotPrimaryMuscleGroupRaw: v.optional(v.string()),
  hasSnapshotMetadata: v.optional(v.boolean()),
  notes: v.string(),
  referenceNotes: nullableString,
  sourceLoggedExerciseID: v.optional(nullableString),
  // Omission is a legacy upload; null explicitly removes grouping.
  supersetGroupID: v.optional(nullableString),
  // Omitted by builds from before timed exercises; the stored value is kept.
  trackingMethodRaw: v.optional(v.string()),
});

export const loggedSetPayloadValidator = v.object({
  ...syncPayloadFields,
  loggedExerciseClientId: v.string(),
  orderIndex: v.number(),
  weight: nullableNumber,
  reps: nullableNumber,
  rpe: nullableNumber,
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
  sourceLoggedSetID: v.optional(nullableString),
  // Omission is a legacy upload and keeps the stored time; null clears it.
  durationSeconds: v.optional(nullableNumber),
});

export const workoutTemplateEntryValidator = v.object({
  id: v.string(),
  exerciseClientId: nullableString,
  exerciseSnapshotName: v.string(),
  exerciseSnapshotEquipmentRaw: v.string(),
  exerciseSnapshotPrimaryMuscleGroupRaw: v.string(),
  supersetGroupID: nullableString,
});

export const workoutTemplatePayloadValidator = v.object({
  ...syncPayloadFields,
  name: v.string(),
  entries: v.array(workoutTemplateEntryValidator),
});
