# Sentry sync observability manual QA

Use this checklist for issue #50 after the implementation build passes unit tests. The Sentry website steps are intentionally manual and should be performed by the project owner.

## Sentry project setup

1. Open the existing `baros-ios` project in the `kevin-tatooles` organization and confirm its platform is iOS.
2. Keep the project slug used by `SENTRY_PROJECT` in `project.yml` synchronized with any future slug change.
3. Under **Security & Privacy**, keep default data scrubbing enabled and prevent storage of IP addresses.
4. Add these sensitive field names to the project's scrubbing rules: `ownerTokenIdentifier`, `owner_subject`, `authorization`, `session_token`, `email`, `workout_notes`, `set_notes`, `record_id`, `client_id`, `request_body`, and `response_body`.
5. Leave Spike Protection disabled for this project.
6. Create an alert named `Baros persistent sync failure` that emails the maintainer for every captured event with `component=sync` and `outcome=failure`. Do not include `outcome=recovered`.
7. Keep the alert action throttle at **Get notified on every trigger**. Do not add an ingestion filter that discards stored events.

## Archive and symbols

1. Add `SENTRY_AUTH_TOKEN` to the merge/archive Xcode Cloud workflow as a secret environment variable. Do not add it to the repository, app bundle, or event data.
2. Let the merge-triggered Xcode Cloud workflow archive the Release configuration. The repository's pre-`xcodebuild` script installs `sentry-cli` only for archive actions, and the archive must fail if the CLI or token is unavailable.
3. In **Project Settings > Debug Files**, verify the uploaded dSYM UUID matches the archived Baros binary.
4. Retain the distributed archive.

## TestFlight event verification

1. Install the archived build through TestFlight and sign in with a disposable Current Owner.
2. Force a completed failed outbox push twice through the approved test setup.
3. Verify Sentry stores two events under one issue with the same stable fingerprint and shows one distinct affected user.
4. Repeat with a second disposable Current Owner and verify the distinct affected-user count increases to two without creating a separate issue solely for that owner.
5. Restore synchronization and verify one informational `Sync Recovery` event appears without a failure email.
6. Confirm the event tags include `component`, `sync_phase`, `entity_kind`, `operation`, `outcome`, `failure_category`, `error_code`, and `distribution_channel=testflight`.
7. Confirm the event has the expected release, build (`dist`), and `production` environment.

## Privacy inspection

Inspect the raw JSON for a failure and recovery event. It must not contain raw Current Owner values, provider subjects, email addresses, names, authentication tokens, workout content, record or Convex document identifiers, URLs, headers, request or response bodies, localized error descriptions, or unrelated breadcrumbs.

The only Sentry user field may be an ID beginning with `owner_v1_`. Confirm that changing Current Owner or signing out clears the prior scope before generating another event.

## Delivery review

Open Sentry Stats and record accepted, filtered, rate-limited, invalid, and client-discarded outcomes for the test window. Issue #50 can be closed only after the archive symbols, grouping, event count, affected-owner count, privacy inspection, recovery behavior, and alert behavior are all verified.
