# Exercise Taxonomy Design

Issue: [#40 Tighten exercise taxonomy before v1 sync](https://github.com/Tatooles/lifting-log-ios/issues/40)

Date: 2026-06-05

## Decision

Tighten exercise definitions before v1 sync by replacing free-text primary muscle entry with a controlled primary muscle group taxonomy, expanding the existing equipment taxonomy, and making equipment part of exercise identity. Keep the model simple for v1: one exercise record has one name, one equipment value, one primary muscle group, and optional notes.

This work should make exercise creation feel like a first-class library workflow without introducing a full movement-family or variant system yet.

## Goals

- Replace free-text primary muscle entry with a controlled picker.
- Keep one required primary muscle group per exercise.
- Defer secondary muscle groups until muscle-volume analytics or richer filtering needs justify them.
- Expand equipment options where v1 value is obvious and reusable.
- Keep exercise categories unchanged.
- Treat equipment as part of active exercise identity so users can create records such as `Bench Press` with `Barbell`, `Dumbbell`, `Machine`, or `Cable`.
- Show exercise metadata consistently as secondary text where exercise names appear.
- Snapshot exercise metadata into logged exercises so workout history remains readable after library edits.
- Preserve reasonable fallback behavior for old or future unknown taxonomy values.
- Keep Convex sync payloads compatible with local model changes.

## Non-Goals

- No secondary muscle group field in v1.
- No full movement-family, base-movement, or exercise-variant model in this issue.
- No muscle-volume analytics.
- No rest timer, superset, circuit, or workout-grouping changes.
- No user-defined custom metadata field system.
- No attempt to perfectly reconstruct metadata for old logged exercises that predate snapshot fields.

## Primary Muscle Groups

The v1 primary muscle group taxonomy is intentionally broad and training-focused:

- `chest`
- `lats`
- `upperBack`
- `traps`
- `lowerBack`
- `shoulders`
- `biceps`
- `triceps`
- `forearms`
- `quads`
- `hamstrings`
- `glutes`
- `abductors`
- `adductors`
- `calves`
- `core`
- `neck`
- `fullBody`
- `cardio`
- `other`

Display labels should use normal title case, for example `Upper Back`, `Lower Back`, and `Full Body`.

The purpose of this taxonomy is search, filtering, and clear exercise creation, not anatomical precision. Use `Core`, not `Abdominals`, because it covers bracing, anti-rotation, planks, carries, and other non-crunch trunk work. `Lower Back` is still a separate value because back extensions, reverse hypers, and spinal-erector accessories are common enough to avoid overloading `Core`, `Glutes`, or `Hamstrings`. Values such as `Rear Delts` should not become their own v1 taxonomy value; seeded or migrated exercises with that value should map to `shoulders`. Broad filters are acceptable because users should get everything they expect, even if a filter returns a few extra exercises.

## Equipment

Keep the existing equipment taxonomy and add common reusable equipment types:

- `barbell`
- `dumbbell`
- `machine`
- `cable`
- `bodyweight`
- `kettlebell`
- `smithMachine`
- `resistanceBand`
- `medicineBall`
- `other`

More specific implements such as an ab wheel should use `other` for v1 unless real usage shows that they need first-class treatment.

## Categories

Keep the current exercise categories unchanged:

- `strength`
- `cardio`
- `mobility`
- `other`

Most exercises are expected to remain under `strength`. `cardio` and `mobility` leave room for future exercise types without needing additional v1 category work.

## Exercise Identity

For v1, an active exercise duplicate is defined by normalized `name + equipment`, not name alone.

This allows:

- `Bench Press` + `Barbell`
- `Bench Press` + `Dumbbell`
- `Shoulder Press` + `Machine`
- `Shoulder Press` + `Dumbbell`

The app should still reject exact active duplicates with the same normalized name and same equipment. Archived or deleted records should continue to follow the existing archive/delete behavior.

Exercise history lookup should respect the same identity rule. The active workout history button should show history for the specific linked exercise when available. If it must fall back to snapshot matching, it should match at least normalized `exerciseSnapshotName + exerciseSnapshotEquipmentRaw`, not name alone. For example, `Bench Press` + `Dumbbell` history should not include `Bench Press` + `Barbell` entries.

The model should not treat exercise name as a canonical movement identity. The name remains the user-facing display name. Users can create names such as `Close Grip Slingshot Pause Bench Press` today. A future movement-family system can later group that exercise under a base movement such as `Bench Press` without invalidating this design.

## UI Behavior

Exercise creation and editing should use pickers for category, equipment, and primary muscle group. Notes remain free text.

Where exercise names are displayed in exercise-focused views, show metadata as a quiet secondary line:

```text
Bench Press
Barbell • Chest
```

The standardized secondary text is:

```text
Equipment • Primary Muscle Group
```

This should appear in exercise library rows, exercise picker rows, active workout exercise cards, workout history detail, and exercise history detail/session rows where space allows. The exercise name remains the primary scan target. If a narrow row truncates secondary text, that is acceptable.

Top-level workout history rows summarize sessions rather than individual exercises, so they do not need to list exercise metadata.

## Logged Exercise Snapshots

Logged exercises currently snapshot only the exercise name. Add snapshot fields for exercise equipment and primary muscle group so completed workout history remains understandable after the library exercise changes.

Recommended snapshot fields:

- `exerciseSnapshotName`
- `exerciseSnapshotEquipmentRaw`
- `exerciseSnapshotPrimaryMuscleGroupRaw`

When adding an exercise to a workout, copy these values from the selected exercise. History views should prefer snapshot metadata for completed logged exercises. If old logged exercises do not have the new snapshot fields, they may fall back to linked exercise metadata when available. If neither snapshot nor linked metadata is available, show the exercise name without forcing inaccurate metadata.

The goal is readable continuity, not perfect historical reconstruction.

## Local Model Shape

The SwiftData exercise model should continue storing raw taxonomy strings and expose typed enum accessors for known values.

Recommended exercise fields:

- `categoryRaw`
- `equipmentRaw`
- `primaryMuscleGroupRaw`

Recommended enum accessors:

- `category: ExerciseCategory`
- `equipment: ExerciseEquipment`
- `primaryMuscleGroup: ExerciseMuscleGroup`

The old `primaryMuscleRaw` field should be replaced or migrated to `primaryMuscleGroupRaw` as part of the model migration path. The implementation should choose the least disruptive SwiftData migration approach available for the current schema setup.

Use precise naming now so a future field such as `secondaryMuscleGroupRaws` can be added without renaming the primary field.

## Migration And Fallbacks

Known existing free-text primary muscle values should map into the new controlled taxonomy. For current seed data, use these concrete mappings:

- Back Squat: `quads`
- Front Squat: `quads`
- Romanian Deadlift: `hamstrings`
- Conventional Deadlift: `glutes`
- Leg Press: `quads`
- Leg Extension: `quads`
- Leg Curl: `hamstrings`
- Bench Press: `chest`
- Incline Dumbbell Press: `chest`
- Overhead Press: `shoulders`
- Pull-Up: `lats`
- Lat Pulldown: `lats`
- Barbell Row: `upperBack`
- Seated Cable Row: `upperBack`
- Dumbbell Row: `upperBack`
- Face Pull: `shoulders`
- Biceps Curl: `biceps`
- Triceps Pushdown: `triceps`
- Calf Raise: `calves`
- Plank: `core`

For non-seeded existing records, map known legacy strings conservatively:

- `Quads` -> `quads`
- `Hamstrings` -> `hamstrings`
- `Posterior Chain` -> `glutes`
- `Chest` -> `chest`
- `Back` -> `upperBack`
- `Lats` -> `lats`
- `Traps` -> `traps`
- `Lower Back` -> `lowerBack`
- `Rear Delts` -> `shoulders`
- `Biceps` -> `biceps`
- `Triceps` -> `triceps`
- `Forearms` -> `forearms`
- `Abductors` -> `abductors`
- `Adductors` -> `adductors`
- `Calves` -> `calves`
- `Core` -> `core`
- `Abdominals` -> `core`
- `Neck` -> `neck`

Unknown existing values should display as `Other`. Where storage allows preserving an unknown raw value, preserve it rather than overwriting it. This keeps future taxonomy additions from corrupting older data.

Seed data should be updated to use the new controlled values directly.

## Convex Sync

Convex exercise records and sync payload validators should match the local model fields.

For forward compatibility, Convex should store taxonomy raw values as strings instead of strict literal unions for the exercise taxonomy fields. The app UI remains controlled, and tests should enforce that seeded and client-created exercise values use supported taxonomy values.

This avoids making every future taxonomy addition a backend schema rollout. Older clients should be able to preserve unknown raw values and display a fallback such as `Other`.

## Testing

Add or update tests for:

- Model persistence of `primaryMuscleGroupRaw`, expanded equipment values, and fallback accessors.
- Exercise editor picker behavior and duplicate validation using `name + equipment`.
- UI test coverage for creating same-name exercises with different equipment and rejecting same-name, same-equipment duplicates.
- Seed data mappings into the new primary muscle taxonomy.
- Logged exercise snapshot creation for name, equipment, and primary muscle group.
- Active workout history lookup for same-name exercises with different equipment.
- UI test coverage that verifies active-workout history for one same-name equipment variant does not show another same-name equipment variant.
- History display fallback behavior for old logged exercises without snapshot metadata.
- Convex schema and sync payload validator changes.
- Any SwiftData migration or compatibility path used to replace `primaryMuscleRaw`.

## Open Implementation Notes

- The implementation should inspect the current SwiftData schema setup before choosing whether this is a lightweight rename, a schema version migration, or a transitional compatibility field.
- Existing history that predates metadata snapshots may remain less precise. It should still show the logged exercise name.
- A future movement-family feature could add `movementFamilyID`, `baseMovementRaw`, or a related model. This issue should not add that field now.
