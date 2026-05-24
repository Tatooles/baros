# Local Release Baseline Audit Design

## Context

GitHub issue #3 covers Phase 0 of `docs/initial-release-roadmap.md`: audit and stabilize the current local/offline LiftingLog app before adding authentication, export, or cloud sync. The app is currently a native SwiftUI iPhone app backed by SwiftData.

The audit focuses on existing local behavior:

- Workout creation from blank and past workouts.
- Active workout editing.
- Workout finish, discard, and delete behavior.
- Workout and exercise history.
- Exercise library create, edit, archive, and delete behavior.
- Settings persistence and unit conversion.
- SwiftData model and relationship persistence.
- Existing unit and UI test coverage.

## Goal

Establish a trustworthy local release baseline and fix only small Phase 0 blockers discovered during the audit.

The outcome should make clear:

- Which local workflows are release-ready.
- Which workflows are covered by automated tests.
- Which release-critical gaps remain.
- Which fixes, if any, were necessary before future sync/auth/export work.

## Non-Goals

This issue does not add cloud sync, authentication, export, account deletion, App Store metadata, analytics, charts, programs, HealthKit, subscriptions, widgets, or broad visual redesign.

This issue also avoids general refactors unless a narrow change is required to fix a blocker found during the audit.

## Audit Scope

### Workout Creation

- Blank workout starts reliably.
- Repeated start attempts reuse the existing active session instead of creating duplicates.
- Starting from a past workout copies title, notes, exercises, set values, and order.
- Copied past-workout sets start incomplete.
- Starting from a past workout does not mutate the original completed workout.
- Seeded exercises are present for first-run workout creation.

### Active Workout Editing

- Users can add and remove logged exercises.
- Users can add, remove, and reindex sets.
- Users can edit weight, reps, RPE, workout title, workout notes, and exercise notes.
- Set completion updates completed set count and volume.
- Empty workout title drafts are allowed while editing, then finalized to a safe default.
- Keyboard focus traversal works across workout fields, collapsed exercises, and newly added sets.

### Finish, Discard, And Delete

- Finishing a workout marks it completed, stores `endedAt`, stores duration, clears the active workout, and makes it visible in history.
- Discarding a workout clears the active workout and keeps it out of completed history.
- Deleting a completed workout removes it from history and preserves a recoverable UI error path if saving fails.
- Cascade behavior for workout deletion is understood before sync metadata is added.

### History

- Completed workouts appear in reverse chronological order.
- Discarded and active workouts do not appear in completed history.
- Exercise history counts completed sets only.
- Exercise history groups sets by workout session.
- Exercise history uses snapshot names so renamed or archived exercises do not corrupt history display.
- Past-workout reuse offers completed workouts only.

### Exercise Library

- Custom exercises can be created and edited.
- Duplicate active exercise names are rejected.
- Seeded exercises and exercises with history are archived instead of hard-deleted.
- Archived exercises are hidden from normal library and picker flows.

### Settings

- A settings record exists after seed.
- Weight unit changes persist.
- Existing logged set weights convert when the weight unit changes.
- Rest timer changes persist.
- Profile counts reflect completed workouts and active exercises.

### SwiftData Persistence

- Core models persist and fetch by stable UUID.
- Workout session, logged exercise, and logged set relationships persist correctly.
- Timestamps are updated for local edits that affect future sync readiness.
- The app handles launch-time seed data without duplicating settings or seeded exercises.
- The current schema and relationship behavior are documented before Phase 1 sync changes.

### Test Coverage

- Run the full unit test suite.
- Run the UI test suite.
- Map existing tests to the audited workflows.
- Identify release-critical missing tests.
- Add or update tests only when they support a blocker fix or lock down a release-critical local baseline.

## Blocker Criteria

A finding is a Phase 0 blocker if it can cause one of these outcomes:

- Lost, inaccessible, or incorrectly deleted workout data.
- Incorrect saved workout history.
- A broken active workout creation, editing, finish, or discard flow.
- App launch failure or SwiftData initialization failure.
- Settings changes that corrupt logged data.
- A release-critical local workflow with no practical recovery path.

Small fixes are allowed for blockers when they are narrow, directly tied to the audit, and covered by automated or manual verification.

Everything else should be recorded as a follow-up issue or later roadmap work.

## Verification Plan

Automated verification should use the existing project commands from `README.md`:

- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 16,OS=18.6 -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 16,OS=18.6 -only-testing:LiftingLogTests -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 16,OS=18.6 -only-testing:LiftingLogUITests -derivedDataPath /private/tmp/codex-ios-app-derived-data`

Manual verification should cover the critical offline workflows on simulator:

- Fresh launch and seed data.
- Start blank workout, add exercise, enter set values, complete sets, finish workout, inspect history.
- Start from a past workout, confirm copied set state and original history integrity.
- Edit settings, especially weight unit conversion.
- Create, edit, archive, and hide exercises from the library and picker.
- Delete a completed workout from history.

## Deliverable

The issue should end with:

- A concise audit summary.
- Test results.
- Manual verification results.
- Any small blocker fixes made, with rationale.
- Follow-up issues or notes for non-blocking gaps.
