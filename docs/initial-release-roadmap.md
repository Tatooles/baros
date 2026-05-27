# Initial Release Roadmap

This roadmap defines the baseline needed to ship LiftingLog as a trustworthy v1 product. The goal is not to maximize feature count before release; the goal is to make the existing workout logging experience stable, recoverable, syncable, and ready for App Store review.

## Release Goal

Ship a clean native iPhone workout logger with:

- Reliable offline workout logging
- Exercise and history management
- Data export
- Clerk-based authentication
- Convex-backed cloud sync
- Account deletion and privacy controls
- App Store submission readiness

Advanced product features such as charts, programs, HealthKit, subscriptions, widgets, AI, and social sharing are intentionally deferred until after the initial release unless they become necessary for review or data safety.

## Guiding Principles

- Keep the app offline-first. Users should be able to log a workout even when the network is unavailable.
- Protect user data before expanding product scope.
- Treat sync as infrastructure, not as a visible feature bundle.
- Keep v1 conflict handling simple and predictable.
- Build export before cloud sync so users always have a recovery path.
- Keep App Store compliance work visible instead of leaving it until the end.

## Phase 0: Release Baseline Audit

Stabilize the current local app before introducing cloud complexity.

Target outcomes:

- Current workout logging flow is stable.
- Create, edit, delete, finish workout, and history flows are reviewed.
- Existing tests are checked for release-critical coverage.
- Local persistence behavior is understood before sync metadata is added.
- Decide whether v1 supports signed-out offline use, signed-in sync use, or both.

Suggested issue:

- Audit and stabilize local release baseline

## Phase 1: Sync-Ready Data Model

Prepare local SwiftData models for safe syncing with Convex.

Target outcomes:

- Synced models have stable client-generated identifiers.
- Synced models include timestamps such as `createdAt` and `updatedAt`.
- Delete behavior is defined, likely with tombstones or a `deletedAt` value.
- Synced entity scope is explicit: settings, exercises, workouts, logged exercises, logged sets, and any templates included in v1.
- Conflict behavior is defined. For v1, default to latest update wins, while preserving deletes unless a record is intentionally recreated.
- Migrations and persistence tests cover the model changes.

Suggested issue:

- Make SwiftData models sync-ready

## Phase 2: Data Export

Add a user-facing export path before adding cloud sync.

Target outcomes:

- Export workout history to CSV.
- Consider JSON export as a more complete backup format.
- Use the native iOS share sheet.
- Include enough fields to reconstruct workout history: workout date, exercise, set order, weight, reps, unit, notes, and set kind.
- Add tests for export formatting and data coverage.

Suggested issue:

- Add workout data export

## Phase 3: Clerk Authentication

Add account identity while keeping the core local experience intact.

Target outcomes:

- Add sign in, sign out, and session restoration.
- Add account state to profile or settings.
- Decide supported login methods.
- If social login is offered, include Sign in with Apple or confirm the selected login setup avoids Apple login-rule issues.
- Signed-out behavior is intentional and clearly handled.
- Auth state does not break local workout logging.

Suggested issues:

- Add Clerk authentication
- Add account settings shell

## Phase 4: Convex Backend Foundation

Create the authenticated backend structure before implementing the iOS sync engine.

Target outcomes:

- Convex project is configured for development and production.
- Clerk identity is connected to Convex auth.
- Convex schema matches the sync-ready local model.
- Backend functions support authenticated user-scoped reads and writes.
- Functions exist for upsert, delete or tombstone, and fetching changes.
- Backend access rules prevent users from reading or writing other users' data.

Suggested issue:

- Create Convex schema and authenticated sync APIs

## Phase 5: Sync Engine

Implement cloud sync incrementally, starting with simple entities before completed workout history.

V1 workout sync should not include in-progress active workouts. Active workouts remain local SwiftData drafts until the user finishes them; once a workout is completed, its workout session, logged exercises, and logged sets become eligible for Convex sync. Mid-workout cross-device resume and cloud backup of active drafts are deferred until after v1 unless user demand proves the added sync complexity is worthwhile.

Target outcomes:

- Local changes are tracked in an outbox or equivalent sync metadata.
- Local changes can be pushed to Convex.
- Remote changes can be pulled into SwiftData.
- Failed syncs retry without duplicating records.
- Sync handles create, update, and delete.
- UI communicates basic sync state: idle, syncing, offline, failed, and last synced.

Suggested entity order:

1. User settings
2. Exercises
3. Completed workout sessions
4. Logged exercises
5. Logged sets

Suggested issues:

- Implement local sync metadata and outbox
- Sync settings and exercises
- Sync workout sessions, logged exercises, and logged sets
- Add sync status, retry, and error recovery UI

## Phase 6: Account Deletion and Privacy Controls

Complete the account lifecycle and App Store privacy requirements.

Target outcomes:

- Users can start account deletion from inside the app.
- Deletion flow includes a clear confirmation step.
- Cloud account data is deleted from Clerk and Convex according to the final architecture.
- Local data behavior is explicit: either delete local data too, or clearly state that local data remains on device.
- Privacy policy and support links are available and accurate.

Suggested issue:

- Add account deletion and privacy controls

## Phase 7: App Store Submission Pack

Prepare release materials and review requirements as a tracked workstream.

Target outcomes:

- App icon, screenshots, description, subtitle, keywords, and category are ready.
- Privacy policy URL and support URL are live.
- App Privacy details accurately describe Clerk, Convex, and any analytics or diagnostics.
- Review notes include demo access or enough instructions for Apple to test account features.
- Production backend is live during review.
- No placeholder screens, labels, links, or metadata remain.

Suggested issue:

- Prepare App Store submission materials

## Phase 8: TestFlight Release Candidate

Validate the release with real-world usage before submitting to App Review.

Target outcomes:

- Internal TestFlight build is validated on physical devices.
- Network failure, airplane mode, sign out/sign in, reinstall, and cross-device sync are tested.
- External TestFlight is used if practical.
- Only release-blocking bugs are fixed during the release candidate window.

Suggested issue:

- Run TestFlight release candidate hardening

## Recommended Issue Order

1. Audit and stabilize local release baseline
2. Make SwiftData models sync-ready
3. Add workout data export
4. Add Clerk authentication
5. Add account settings shell
6. Create Convex schema and authenticated sync APIs
7. Implement local sync metadata and outbox
8. Sync settings and exercises
9. Sync workout sessions, logged exercises, and logged sets
10. Add sync status, retry, and error recovery UI
11. Add account deletion and privacy controls
12. Prepare App Store submission materials
13. Run TestFlight release candidate hardening

## Deferred Until After v1

These features are valuable, but they should not block the first release unless product direction changes:

- Advanced charts and progress analytics
- Training programs and periodization
- HealthKit integration
- Widgets and Live Activities
- Subscriptions or paid plans
- Social sharing
- AI coaching or workout generation
- Team, coach, or multi-user workflows

## Agent Work Strategy

Avoid assigning an agent a broad task such as "build sync." Split work into narrow, verifiable issues with clear success criteria.

Good agent-sized work units:

- Data model sync preparation
- Export implementation
- Auth integration
- Convex schema and functions
- Local sync metadata
- Sync for simple entities
- Sync for workout graph data
- Account deletion
- App Store readiness

Each issue should include expected tests, manual verification steps, and the specific files or systems likely to be touched.
