# Baros Authentication Domain Migration Runbook

Status: Small beta migration prepared locally. Nothing in this runbook has been deployed or run against production.

This is a coordinated hard cutover for the handful of beta users whose Convex ownership keys still contain the Lifting Log Clerk issuer.

## Scope And Decision

Production inspection on July 17, 2026 found:

- Four owners with visible completed workouts: 23, 14, 5, and 5 workouts.
- One additional owner with only a tombstoned workout.
- One separate account-deletion marker that must be inspected before deciding whether it still needs migration.
- Every current owner uses `https://clerk.auth.liftinglog.app`.
- The largest owner/table pair contains 483 rows, safely below the migration mutation's 1,000-row limit.

For this beta-sized migration:

- Do not ship a permanent compatibility layer or client-side owner migration.
- Coordinate directly with the four testers so all wanted data reaches Convex before the cutoff.
- Rewrite Convex ownership one user and one table at a time with the temporary internal mutation.
- Have existing testers clear the old local database by deleting and reinstalling the new TestFlight build after the server migration.
- Remove the temporary mutation before the App Store 1.0 build.

Deleting and reinstalling is intentional here. The current client refuses to merge a remote record into a matching local record owned by a different issuer. A clean install pulls the migrated cloud copy without shipping one-time migration machinery in 1.0.

## Temporary Migration Tool

`convex/ownerIssuerMigration.ts:migrateOwnerTable` moves one Clerk subject's rows in one table. It:

- Hard-codes the exact legacy issuer.
- Requires the exact new HTTPS issuer obtained from a post-flip Clerk token.
- Defaults to dry-run mode.
- Refuses to migrate retained data while either the old or destination owner has an account-deletion marker.
- Refuses to mix old-issuer rows into a table where that subject already has new-issuer rows.
- Refuses owner/table pairs at or above 1,000 rows.
- Updates the selected table atomically in one Convex mutation.

The five retained-data table names are:

```text
userSettings
exercises
workoutSessions
loggedExercises
loggedSets
```

Account-deletion markers are not migration targets. Inspect both owner identifiers and resolve markers separately before migrating any retained data for the same subject. A completed marker for an owner with no retained data can remain under the old issuer for its normal cleanup path.

Dry-run command template:

```sh
pnpm exec convex run ownerIssuerMigration:migrateOwnerTable \
  '{"subject":"user_...","newIssuer":"https://NEW_ISSUER","table":"exercises"}' \
  --prod
```

Write command template; `dryRun: false` must be explicit:

```sh
pnpm exec convex run ownerIssuerMigration:migrateOwnerTable \
  '{"subject":"user_...","newIssuer":"https://NEW_ISSUER","table":"exercises","dryRun":false}' \
  --prod
```

Run both commands for every subject whose data is being retained and every table. Save the command output with the release notes. Stop immediately if a destination-owner or row-limit error appears.

## Cutover Checklist

### 1. Coordinate The Testers

- [ ] Identify the four users with visible completed workouts in Clerk.
- [ ] Identify the owner with only a tombstoned workout. Record its Clerk subject and either include it in the migration or explicitly approve discarding that tombstone before removing the tool.
- [ ] Ask each tester to open the current build online and wait for Sync Status to show Up to date.
- [ ] Ask them not to record new workouts after their sync is confirmed until they install the migration build.
- [ ] Tell them in advance that the new build requires deleting and reinstalling the app; they must not delete it before sync is confirmed.
- [ ] Record each tester's Clerk subject and expected visible completed-workout count.

### 2. Capture The Baseline

- [ ] Create a restorable production Convex backup.
- [ ] Record per-owner counts for all five retained-data tables.
- [ ] Inspect every account-deletion marker. Resolve any active or incomplete deletion flow before migrating retained data for that subject. Do not rewrite marker ownership; a completed marker for an owner with no retained data can remain under the old issuer for normal cleanup.
- [ ] Confirm there are no rows under the proposed new issuer.
- [ ] Confirm no tester has pending local-only work.

Stop if any tester cannot reach Up to date or the backup is unavailable.

### 3. Change Clerk And Auth Configuration

- [ ] Change the production Clerk primary domain to the Baros domain.
- [ ] Confirm Clerk's DNS and certificate status.
- [ ] Mint a fresh token and record its exact `iss` value.
- [ ] Confirm existing users retain the same Clerk `sub` values.
- [ ] Update the Release Clerk publishable key and associated domain in `project.yml`.
- [ ] Run `xcodegen generate`, verify the regenerated `Baros.xcodeproj` contains the new Release Clerk values, and include the project file in the configuration PR.
- [ ] Change production Convex `CLERK_JWT_ISSUER_DOMAIN` to the exact new issuer and deploy the updated auth configuration plus the temporary migration function.
- [ ] Confirm new-issuer authentication works and old-issuer authentication is rejected.
- [ ] On a physical iPhone, confirm native Sign in with Apple completes with the new Clerk publishable key. The bundle ID is unchanged; only alter Apple Services ID return URLs if the Clerk production instance is actually configured to use the web-based Apple flow.

### 4. Rewrite The Small Production Dataset

- [ ] Dry-run all five retained-data tables for the four active subjects and every tombstone subject selected for retention. Do not include deletion-marker-only subjects.
- [ ] Compare every `matched` result with the recorded baseline.
- [ ] Run the real mutation for all five retained-data tables for the same subjects.
- [ ] Verify no rows remain under the old issuer for those subjects.
- [ ] Verify new-issuer per-owner/table counts equal the baseline.

Do not release the new TestFlight build until these counts match.

### 5. Move The Four Testers

- [ ] Upload the new Baros TestFlight build.
- [ ] For each tester: delete the old app, install the new build from TestFlight, and sign in again.
- [ ] Confirm their expected completed workouts return from Convex.
- [ ] Confirm the exercise library does not contain duplicate seeded exercises.
- [ ] Complete and sync one new workout.
- [ ] Confirm Sync Status reaches Up to date after a cold launch.

Stop if a tester's expected workout count does not return. Do not create replacement workouts or delete cloud rows while investigating.

### 6. Remove The Temporary Tool Before 1.0

- [ ] Confirm all four testers have completed the reinstall and validation.
- [ ] Delete `convex/ownerIssuerMigration.ts` and its focused tests.
- [ ] Deploy that removal.
- [ ] Build the final App Store candidate without migration code.
- [ ] Record the final Clerk issuer, Convex deployment, TestFlight build, and verified counts.

## Rollback

- Before the Convex rewrite: restore the old Clerk/Convex auth configuration.
- After the rewrite but before testers reinstall: either reverse the owner prefix with a separately reviewed one-off mutation or fix forward. Do not alternate issuers repeatedly.
- After testers reinstall: pause rollout and fix forward from the production backup and recorded counts.

Never delete beta workout data as part of rollback without an explicit decision from Kevin.
