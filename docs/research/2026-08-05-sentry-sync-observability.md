# Sentry sync observability research for issue #50

**Date:** 2026-08-05

**Status:** Research only; no SDK integration has been implemented

**Scope:** [`Tatooles/baros#50`](https://github.com/Tatooles/baros/issues/50), milestone `1.1 release`

## Recommendation

Implement issue #50 as a narrow error-monitoring feature:

1. Add the Sentry Apple SDK through Swift Package Manager.
2. Start it only in an explicitly enabled, production-like configuration.
3. Put a small application-owned `SyncObservability` boundary between sync code and Sentry.
4. Send only classified durable failures and recovery transitions as events; keep ordinary lifecycle activity and early transient failures as breadcrumbs.
5. Construct events from an allow-listed, privacy-safe data model. Attach only a stable Pseudonymous Current Owner ID for distinct-owner counts; do not pass Baros's raw owner identifier, sync errors, or diagnostic strings to Sentry.
6. Group events with a stable sync fingerprint, send every classified durable occurrence, and keep Sentry's error sample rate at 100%. Do not add application-side repeat suppression, cooldowns, sampling, or event caps.
7. Upload the exact archive dSYMs for every TestFlight/App Store build and configure one useful notification path in Sentry.

This matches the issue's actual purpose: detecting users stuck in non-crashing client sync states. It is not a general Sentry rollout. Session Replay, broad performance tracing/profiling, screenshots, view hierarchy capture, logs, metrics, and user feedback should remain out of scope.

## Current repository fit

- `project.yml` is the XcodeGen source of truth. Swift packages are declared in its `packages` section and attached to the `Baros` target through `dependencies`.
- [`Baros/App/BarosApp.swift`](../../Baros/App/BarosApp.swift) is a SwiftUI `@main` app whose initializer is the correct early initialization point. Sentry's Apple guide specifically says a SwiftUI app without an app delegate should call `SentrySDK.start` in the `App` conformer's initializer. ([Sentry manual Apple setup](https://docs.sentry.io/platforms/apple/guides/ios/manual-setup/))
- Debug currently has `BAROS_ENVIRONMENT=Development`; Release overrides it with `BAROS_ENVIRONMENT=Production`. Because both TestFlight and App Store distribution normally use Release, that setting proves "production-like" but does not by itself distinguish the channels.
- `DEBUG_INFORMATION_FORMAT` is already `dwarf-with-dsym`, including Release. Apple says Release builds place symbols in a companion dSYM and an archive gathers the matching binary and dSYMs; the build UUIDs must match for symbolication. ([Apple: Building your app to include debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information))
- `SyncScheduler` already records structured failure reasons (`failedOutboxPush`, `incompleteRemotePull`, and `syncError`) and the sync/outbox model has status counts and attempt counts. Those are better observability inputs than user-facing or diagnostic strings.
- Some current error values and fixtures contain raw owner tokens or entity UUIDs. Sentry's Swift error capture sends the error domain, code, and Swift error description, so calling `SentrySDK.capture(error:)` on those existing values could disclose associated values. ([Sentry: Capturing Errors](https://docs.sentry.io/platforms/apple/guides/ios/usage/))

## Required setup versus optional products

| Capability | Issue #50 decision | Reason |
| --- | --- | --- |
| Apple error SDK, DSN, initialization | **Required** | Transport for non-fatal sync events and breadcrumbs |
| Release, build (`dist`), and environment metadata | **Required** | Makes field failures attributable to a shipped binary/channel |
| Application-owned classification, privacy mapping, and stable grouping | **Required** | This is the issue's core value and testable domain logic |
| dSYM upload | **Required for shipped builds** | Sentry requires matching dSYMs to symbolicate native stack traces ([Sentry dSYM guide](https://docs.sentry.io/platforms/apple/guides/ios/dsym/)) |
| Project privacy/data-scrubbing review | **Required** | SDK defaults include some automatic network data unless disabled |
| Monitors/Alerts configuration | **Required** | Capturing an event without routing it does not notify the maintainer |
| Base crash, app-hang, and release-health behavior | **Incidental SDK baseline; no custom work in #50** | The Apple SDK enables crash handling, app-hang tracking, and automatic sessions by default. Do not expand this ticket into crash/hang tuning. ([Sentry Apple options](https://docs.sentry.io/platforms/apple/guides/ios/configuration/options/)) |
| Session Replay | **Out of scope** | Separate product, broader privacy and runtime cost; replay sample rates default to zero |
| Tracing / broad performance monitoring / profiling | **Out of scope** | Transaction tracing is opt-in and unrelated to durable sync-state classification ([Sentry sampling](https://docs.sentry.io/platforms/apple/guides/ios/configuration/sampling/)) |
| Screenshots and view hierarchy | **Out of scope** | Disabled by default and may contain personal/user content |
| Sentry Logs, Metrics, User Feedback, attachments | **Out of scope** | Not needed for the acceptance criteria; each adds a separate data surface |
| Source-context upload | **Optional later** | Not required for symbolication; `--include-sources` uploads source code in addition to dSYMs |
| Convex server observability | **Out of scope** | Convex logs remain the source for backend execution; #50 covers the client state and client call site |

## 1. Install with Swift Package Manager

Sentry recommends Swift Package Manager for Apple apps. For a normal iOS app such as Baros, select the released binary `Sentry` product. `SentrySPM` is the compile-from-source product and is not needed here; `SentrySwiftUI` is deprecated because SwiftUI support is included in the main SDK. The package URL is:

```text
https://github.com/getsentry/sentry-cocoa.git
```

Only one linking/product variant should be selected. ([Sentry: Swift Package Manager](https://docs.sentry.io/platforms/apple/guides/ios/install/swift-package-manager/), [Sentry Cocoa package products](https://github.com/getsentry/sentry-cocoa/blob/9.23.0/Package.swift))

For this XcodeGen project, the eventual implementation should:

- add the package under `packages` in `project.yml`;
- select the `Sentry` product in the `Baros` target dependency;
- regenerate the Xcode project rather than editing `Baros.xcodeproj` by hand.

### Official wizard versus Baros's XcodeGen source of truth

Sentry's project onboarding recommends the Sentry wizard as its automatic configuration path. For a conventional Xcode project, the wizard installs the SDK, updates the app delegate or SwiftUI `App` initializer with a default configuration and sample error, adds an Upload Debug Symbols build phase, and creates a gitignored `.sentryclirc` containing the symbol-upload credentials. ([Sentry Apple installation](https://docs.sentry.io/platforms/apple/guides/ios/#install), [Sentry wizard source](https://github.com/getsentry/sentry-wizard))

That recommendation is compatible with this research, but the wizard must not become a second source of project configuration in Baros. It patches generated Xcode project state, while Baros owns dependencies, build settings, and build scripts in `project.yml`. Running XcodeGen later could overwrite wizard-only package or build-phase changes.

Use one of these equivalent implementation workflows:

1. Configure Sentry manually from the wizard's instructions, expressing the Swift package and symbol-upload phase directly in `project.yml`; or
2. Run the wizard on a clean temporary branch as a scaffold/diff generator, inspect every change, port the durable dependency and build-script changes into `project.yml`, and discard generated-project-only edits.

In either workflow:

- replace the wizard's sample error and default SDK options with the production-only, privacy-restricted initialization in the next section;
- do not enable tracing, replay, screenshots, or other optional products merely because an onboarding example includes them;
- never commit `.sentryclirc` or its auth token; provide the upload token through an approved local secret store and Xcode Cloud/CI secret configuration;
- regenerate `Baros.xcodeproj` with XcodeGen and verify the package dependency and Upload Debug Symbols phase survive regeneration.

The wizard handles mechanical SDK setup only. It does not replace the Baros-owned `SyncObservability` boundary, durable-failure classifier, privacy allow-list, completeness policy, stable grouping, or unit tests required by issue #50.

As of this research, the latest published SDK release is `9.23.0` (2026-07-22). Use that stable release or re-check the releases page immediately before implementation rather than pinning to an unreleased `main` version. ([Sentry Cocoa 9.23.0](https://github.com/getsentry/sentry-cocoa/releases/tag/9.23.0), [Sentry mobile SDK release channels](https://docs.sentry.io/platforms/apple/guides/ios/releases/))

## 2. Initialize SwiftUI only when explicitly enabled

Sentry documents two relevant behaviors:

- With no DSN, the SDK sends no events.
- `options.enabled = false` stops sends but does not remove all instrumentation overhead; to disable Sentry completely, conditionally avoid `SentrySDK.start`. ([Sentry Apple options](https://docs.sentry.io/platforms/apple/guides/ios/configuration/options/))

Therefore, the recommended boundary is an application configuration value such as `SENTRY_ENABLED`, plus a non-empty DSN, rather than merely `#if !DEBUG`. Release is production-like today, but an explicit flag keeps previews, local Release runs, tests, and future configurations controllable.

Illustrative configuration shape (not implementation):

```swift
init() {
    if ObservabilityConfiguration.isEnabled {
        SentrySDK.start { options in
            options.dsn = ObservabilityConfiguration.dsn
            options.environment = ObservabilityConfiguration.environment
            options.releaseName = ObservabilityConfiguration.releaseName
            options.dist = ObservabilityConfiguration.buildNumber

            options.sendDefaultPii = false
            options.enableCaptureFailedRequests = false
            options.enableNetworkBreadcrumbs = false
            options.sampleRate = 1.0
            options.beforeSend = ObservabilityEventScrubber.scrub

            // Deliberately do not set tracesSampleRate or a replay sample rate.
        }
    }

    // Existing Baros initialization follows.
}
```

The manual guide's onboarding sample turns on SDK debug logging and 100% tracing to prove installation. Those are onboarding diagnostics, not the recommended production configuration for #50. SDK debug logging is not recommended in production, and tracing remains disabled unless `tracesSampleRate` or `tracesSampler` is set. ([Sentry manual Apple setup](https://docs.sentry.io/platforms/apple/guides/ios/manual-setup/), [Sentry sampling](https://docs.sentry.io/platforms/apple/guides/ios/configuration/sampling/))

### Automatic HTTP capture should be disabled for this ticket

The Apple SDK enables failed HTTP request capture by default for `500...599`, and enables network breadcrumbs by default. Failed-request events can include request/response headers; network URLs are sanitized by removing query and fragment, but the remaining path can still contain PII. ([Sentry: HTTP Client Errors](https://docs.sentry.io/platforms/apple/guides/ios/configuration/http-client-errors/), [Sentry: Data Collected](https://docs.sentry.io/platforms/apple/guides/ios/data-management/data-collected/))

Disable both automatic failed-request events and automatic network breadcrumbs for #50. The app-owned layer should report a small, safe Convex failure category/code and a manual sync breadcrumb instead. This avoids duplicate Convex events and keeps the ticket aligned with app-side durable state rather than all HTTP failures.

## 3. Release, build, TestFlight, and App Store channel

Sentry environments are free-form, case-sensitive values created when the first event arrives. Releases can span environments. If no Apple release name is supplied, the SDK derives one from `CFBundleIdentifier`, `CFBundleShortVersionString`, and `CFBundleVersion`, such as `my.project.name@2.3.12+1234`. ([Sentry environments](https://docs.sentry.io/platforms/apple/guides/ios/configuration/environments/), [Sentry releases](https://docs.sentry.io/platforms/apple/guides/ios/configuration/releases/))

Use explicit values so the runtime event, release object, and symbol-upload build agree:

- `releaseName`: `com.kevintatooles.LiftingLog@<marketing-version>+<build-number>`
- `dist`: the App Store build number (`CFBundleVersion`)
- environment:
  - `testflight` when a separately built artifact is exclusively a beta;
  - `production` for an App Store artifact.

### Important same-binary limitation

TestFlight builds are uploaded to App Store Connect and can later be submitted to the App Store unchanged. Apple describes TestFlight as beta distribution of uploaded builds, and a build can remain available to testers after it goes live. ([Apple TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview))

Consequently, a compile-time setting cannot truthfully change from `testflight` to `production` when the same binary is promoted. For Baros's likely workflow:

1. Keep the Sentry `environment` as `production` (or a neutral `release`) for that shared production-like binary.
2. Resolve the distribution channel after launch and attach a low-cardinality event/scope tag such as `distribution_channel=testflight|app_store`.
3. Do not delay Sentry startup waiting for StoreKit.

Apple's `AppTransaction.shared` returns verified App Store-signed app transaction information asynchronously and can require network connectivity; its `environment` is an `AppStore.Environment` (`production`, `sandbox`, or `xcode`). ([Apple `AppTransaction.shared`](https://developer.apple.com/documentation/storekit/apptransaction/shared), [Apple `AppStore.Environment`](https://developer.apple.com/documentation/storekit/appstore/environment)) TestFlight uses the sandbox StoreKit environment, but that signal should be treated as a late tag, not a prerequisite for early crash/error initialization. ([Apple: Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox))

If the release process instead creates distinct TestFlight and App Store archives, set separate Sentry environments in those workflows and omit runtime channel detection.

## 4. Application-owned observability architecture

Sync code should depend on a Baros-owned protocol and sanitized value types, not `SentrySDK`:

```text
SyncScheduler / SyncCoordinator / recovery code
                    |
                    v
       SyncObservability (application protocol)
          | classify + sanitize
          v
       SyncObservationSink
          |                  |
          v                  v
  Sentry adapter       Recording/no-op sink
  (Release runtime)    (unit tests/disabled builds)
```

Recommended responsibilities:

- `SyncObservability` accepts typed lifecycle facts, not arbitrary strings or `Error`.
- A pure classifier decides breadcrumb-only, durable failure, or recovery transition.
- Every classified durable failure is emitted; there is no application-owned suppression ledger, cooldown, repeat deduplication, or event cap.
- A mapper creates an allow-listed `SanitizedSyncEvent`.
- `SentrySyncObservationSink` is the only type that imports Sentry.
- A no-op sink is installed when observability is disabled.

Sentry's capture APIs support errors, messages, and events; breadcrumbs are buffered and attached to the next event rather than creating issues themselves. ([Sentry: Capturing Errors](https://docs.sentry.io/platforms/apple/guides/ios/usage/), [Sentry: Breadcrumbs](https://docs.sentry.io/platforms/apple/guides/ios/enriching-events/breadcrumbs/))

### Event contract

Use low-cardinality **tags** only for fields that must be searched or filtered. Tags are indexed/searchable; custom contexts are visible but not searchable. ([Sentry tags](https://docs.sentry.io/platforms/apple/guides/ios/enriching-events/tags/), [Sentry contexts](https://docs.sentry.io/platforms/apple/guides/ios/enriching-events/context/))

| Location | Allowed values |
| --- | --- |
| Tags | `component=sync`, `sync_phase`, `entity_kind`, `operation`, `outcome`, `failure_category`, stable `error_code`, `distribution_channel` |
| Context `sync` | bounded integer counts (`attempt_count`, pending/failed/recovered outbox counts), retry state, classifier version |
| Pseudonymous user | required stable Pseudonymous Current Owner ID in Sentry's user `id` field; no email, name, raw owner value, or provider identifier |
| Breadcrumbs | request/start/retry, push/pull success or failure category, recovery start/end with counts, owner-change category without either owner value |
| Automatic metadata | Sentry's app version, OS, device/runtime, release, dist, environment |

Use a local/per-capture scope for sync-specific tags, context, severity, and the Pseudonymous Current Owner ID. Sentry clones the scope for a capture callback so the modifications do not leak to later events. Global scope state must be explicitly cleared on sign-out/owner change. This identifier lets Sentry distinguish repeated events from one Current Owner from events affecting many Current Owners; Sentry's Issue Details reports both total event count and affected-user count. ([Sentry scopes](https://docs.sentry.io/platforms/apple/guides/ios/enriching-events/scopes/), [Sentry Issue Details](https://docs.sentry.io/product/issues/issue-details/))

### Prohibited data

Never send:

- exercise names;
- workout names, workout notes, set notes, or other user-created fitness content;
- email, display name, or authentication provider profile data;
- Clerk session/JWT/access/refresh tokens, authorization headers, cookies, or DSNs/auth tokens;
- raw owner token identifier, Clerk subject, or unhashed user identifier;
- entity UUIDs, local database row identifiers, Convex document IDs, mutation payloads, or full outbox records;
- request/response bodies;
- raw URLs, query strings, fragments, or headers;
- `localizedDescription`, `lastFailure.message`, full diagnostic snapshots, stack locals, or arbitrary log lines.

In particular, do not forward the current raw `SyncCoordinatorError.ownerMismatch(entityKind:entityID:)` or `SyncScheduler.lastFailure.message`. Build a new sanitized event from enum/category/code fields.

## 5. Privacy and scrubbing

### SDK defaults and client-side guard

`sendDefaultPii` defaults to `false`. With that default, Sentry says the Apple SDK does not send the user's IP address; enabling it allows the backend to infer the IP and active integrations to add PII. Keep it false. ([Sentry Apple options](https://docs.sentry.io/platforms/apple/guides/ios/configuration/options/), [Sentry: Data Collected](https://docs.sentry.io/platforms/apple/guides/ios/data-management/data-collected/))

`beforeSend` is the last SDK-side opportunity to modify or drop an event, after scope data has been applied. Use it as defense in depth:

- drop any event from the sync adapter that lacks the expected marker/schema version;
- remove request, user email/name/IP, extras, and unapproved contexts;
- reject suspicious keys and values (`authorization`, `token`, `owner`, `email`, raw UUID/token shapes);
- enforce maximum string lengths;
- return `nil` if the event cannot be proven safe.

Also use `beforeBreadcrumb` if automatic breadcrumbs are ever re-enabled. Sentry recommends SDK-side `beforeSend`, `beforeBreadcrumb`, and `beforeSendSpan` when data must not leave the device. ([Sentry: Scrubbing Sensitive Data](https://docs.sentry.io/platforms/apple/guides/ios/data-management/sensitive-data/), [Sentry filtering](https://docs.sentry.io/platforms/apple/guides/ios/configuration/filtering/))

This hook is a backstop, not the primary sanitizer. The primary rule is typed allow-list construction: raw sensitive data should never enter the event.

### Server-side scrubbing

Sentry provides server-side data scrubbing for common credential-like keys, but it must be verified in the actual project rather than assumed. Review **Settings > Projects > Baros > Security & Privacy**:

- keep data scrubbing enabled;
- enable prevention of IP-address storage;
- add project-specific sensitive field names such as `ownerTokenIdentifier`, `owner_subject`, `authorization`, `session_token`, `workout_notes`, and equivalents;
- do not mark these as safe fields.

Organization-wide rules override project rules. Server-side scrubbing prevents storage, not transmission, so it is secondary to on-device sanitization. Sentry also warns that tagged sensitive values require separate tag deletion even after events are removed. ([Sentry server-side data scrubbing](https://docs.sentry.io/security-legal-pii/scrubbing/server-side-scrubbing/))

### Pseudonymous owner identifier

A stable hash is still an identifier. If Baros uses it to correlate diagnostics back to an account, Apple may consider the diagnostics linked to the user. Apple says data is not linked only when direct identifiers are stripped and re-linkage is prevented; a User ID includes an account-level ID that identifies an account. ([Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/))

Issue #50 requires distinct affected-owner counts, so attach a Pseudonymous Current Owner ID when a Current Owner exists:

- derive a versioned, domain-separated, one-way value that is stable for the same Current Owner across installations;
- do not put it in the fingerprint, because that would create one issue per user;
- put it only in Sentry's user `id` field, not a searchable custom tag;
- truncate to the minimum length needed for collision resistance;
- document that the maintainer must not reverse or join it outside the limited support purpose;
- clear it on owner change/sign-out.

Do not attach a Current Owner identifier while Baros is local-only or the Current Owner is resolving. Keep `sendDefaultPii = false`; the pseudonymous `id` is the only approved user field. A stable hash is pseudonymous rather than anonymous, so the privacy review must treat these diagnostics as potentially linked. ([Sentry mobile privacy](https://docs.sentry.io/security-legal-pii/security/mobile-privacy/))

### Privacy manifest and App Store disclosures

The current app privacy manifest already covers Baros data practices, but Sentry's manifest guidance adds crash data, performance data, other diagnostic data, and the System Boot Time required-reason API. Sentry says a dynamically linked framework's manifest is processed automatically, while a statically linked library requires the app to provide/merge the declarations. ([Sentry Apple privacy manifest](https://docs.sentry.io/platforms/apple/guides/ios/data-management/apple-privacy-manifest/), [Apple required-reason APIs](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api))

Because the recommended `Sentry` product is statically linked, implementation must follow Sentry's static-link guidance: re-run the privacy report/archive validation and merge any required app-owned declarations into `Baros/PrivacyInfo.xcprivacy`; do not replace the app's existing declarations. Also update App Store Connect privacy answers and the published privacy policy before shipping. Apple requires disclosures to include third-party SDK practices and to stay current when practices change. ([Apple: Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/))

Sentry's generic example marks its diagnostic categories unlinked. Baros should not copy that answer blindly: attaching a stable owner pseudonym may make those diagnostics linked under Apple's definition.

## 6. Durable classification, complete recording, grouping, and platform limits

### Initial classification policy

| Signal | Classification | Action |
| --- | --- | --- |
| First offline, timeout, cancellation, unavailable network, signed-out/no-owner condition | Transient | Safe breadcrumb only |
| Retry scheduled and attempt count below threshold | Transient | Safe breadcrumb only |
| Same sanitized signature reaches 3 attempts without success | Durable | Capture one warning/error event |
| Failed outbox count remains non-zero after an explicit retry/cycle | Durable | Capture one event |
| Scheduler records `failedOutboxPush`, `incompleteRemotePull`, or a completed-cycle `syncError` | Durable | Capture one event after mapping to a safe category/code |
| Owner mismatch prevents applying a mutation | Durable client-state failure | Capture immediately, without owner/entity IDs |
| Stale intent/outbox entries are discarded or retargeted during recovery | Recovery transition | Capture one low-severity recovery event with counts; add before/after breadcrumbs |
| Convex client call still fails after the app's retry policy | Durable client-side call failure | Capture safe operation/category/code; use Convex logs for server detail |
| Successful routine cycle | Normal | Breadcrumb only when useful; no event |
| Previously reported signature succeeds | Recovery | Capture the Sync Recovery transition; a later durable failure starts a new failure sequence |

The attempt threshold defines when a Transient Sync Condition becomes a Durable Sync Failure; it is classification, not event-volume suppression. Start with the issue's stated durable signals and adjust the classification only from evidence.

### Stable signature and Sentry fingerprint

Build a versioned signature only from low-cardinality safe fields:

```text
baros-sync-v1 | phase | entity-kind | operation | failure-category | stable-error-code | outcome
```

Do not include owner hash, entity ID, raw message, URL, attempt count, or OS version. Use the same fields as the Sentry event fingerprint so events with the same operational cause group into one issue across users and releases.

Sentry groups events with the same fingerprint into an issue and supports overriding the Apple event's fingerprint. Its default grouping falls back through fingerprint, stack trace, exception, and message; changing messages are therefore a poor grouping key. ([Sentry SDK fingerprinting](https://docs.sentry.io/platforms/apple/guides/ios/usage/sdk-fingerprinting/), [Sentry issue grouping](https://docs.sentry.io/concepts/data-management/event-grouping/))

### Grouping without app-side suppression

Sentry grouping does not reduce event volume; it groups accepted events for investigation while retaining their occurrence count and timeline. Send one event for every completed occurrence classified as a durable failure, and use the stable fingerprint only to group matching events into the same issue.

Do not add an application-owned suppression ledger, cooldown, repeat deduplication, per-launch cap, or `beforeSend` duplicate rejection. The distinction between a Transient Sync Condition and a Durable Sync Failure remains classification: internal retry attempts and ordinary offline/resolving states are not separate durable failures, but no classified durable occurrence is intentionally withheld.

### Sampling and Sentry limits

Keep `options.sampleRate = 1.0` for these classified events. Sentry's error sample rate is random, defaults to 1, and applies equally to all errors; any lower value would deliberately discard part of the failure population. Do not configure a Baros DSN rate limit or enable project Spike Protection for this project. ([Sentry sampling](https://docs.sentry.io/platforms/apple/guides/ios/configuration/sampling/))

This configuration removes deliberate Baros-side loss, but Sentry is still telemetry rather than an exact accounting system. Subscription quota exhaustion, Sentry internal limits, SDK queue/cache overflow, network failure, or a server-directed `429` backoff can still drop events; the SDK must obey Sentry's rate-limit protocol. Monitor Sentry's Stats outcomes for accepted, filtered, rate-limited, and client-discarded events, and keep enough event quota for the expected population. If exact once-only accounting is required, issue #50 needs a separate durable first-party acknowledgement path rather than relying on Sentry alone. ([Sentry SDK rate limiting](https://develop.sentry.dev/sdk/rate-limiting/), [Sentry Stats](https://docs.sentry.io/product/stats/))

## 7. DSN and upload credentials

The DSN identifies the destination project and permits submission, not read access. Sentry explicitly says DSNs are safe to keep public, can be rotated/revoked, and are necessarily exposed in shipped client apps. ([Sentry DSN explainer](https://docs.sentry.io/concepts/key-terms/dsn-explainer/))

Therefore:

- the Release DSN does not need secret storage;
- it is still configuration, so keep one source of truth and avoid copying it through unrelated files;
- an empty/missing DSN should disable startup safely;
- rotate it if abused.

The **Sentry organization auth token used for dSYM upload is a secret**. It authorizes Sentry API actions and must exist only in the CI/Xcode Cloud secret environment or an approved local secret store. Never place it in `project.yml`, an xcconfig checked into Git, the application bundle, or a Sentry event. The dSYM guide requires an auth token and separately uses the public DSN for runtime ingestion. ([Sentry dSYM guide](https://docs.sentry.io/platforms/apple/guides/ios/dsym/))

## 8. dSYM upload for TestFlight and App Store

Sentry requires matching dSYMs to turn native addresses into function/file/line information. Files should be uploaded before the first released crash/error; previously missing files may take time to apply to new reports, and existing events are not reprocessed. Uploaded files are visible under **Project Settings > Debug Files**. ([Sentry: Uploading Debug Information Files](https://docs.sentry.io/platforms/apple/guides/ios/data-management/debug-files/upload/))

For Baros:

1. Keep `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`.
2. Add the upload step through the XcodeGen source (`project.yml`) or the Xcode Cloud post-build workflow, not as an untracked manual Xcode-project edit.
3. Install/use `sentry-cli` in the archive environment.
4. Pass `SENTRY_ORG`, `SENTRY_PROJECT`, and the secret `SENTRY_AUTH_TOKEN`.
5. Upload `"$DWARF_DSYM_FOLDER_PATH"` with `sentry-cli debug-files upload`.
6. For distribution CI, fail the build/archive on upload failure; Sentry recommends considering a hard failure when symbols may be difficult to recover.
7. Do not add `--include-sources` for issue #50.
8. Verify the build UUID appears in **Project Settings > Debug Files** before inviting testers/submitting.
9. Retain the Xcode archive for every distributed build.

The same archive dSYM covers both TestFlight and App Store when the exact binary is promoted. A separately archived App Store build needs its own matching upload. Apple says every binary and dSYM pair is tied by UUID and that archives for distributed builds must be retained. ([Apple: Building your app to include debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information))

## 9. Unit testing without network calls

Do not initialize Sentry in classification tests. Test the application boundary:

1. **Classifier tests:** typed inputs produce `.breadcrumb`, `.durableFailure`, `.recovery`, or `.ignore`.
2. **Completeness tests:** every classified durable occurrence reaches the recording sink, including repeated matching occurrences; no cooldown, sampling, deduplication, or cap drops one.
3. **Privacy mapping tests:** every event is constructed from the allow-list; raw owner/entity identifiers, UUIDs, URLs, tokens, notes, localized error messages, and unexpected dictionary keys are absent.
4. **Scope and owner-count tests:** the same Current Owner produces the same pseudonym across installations; different owners do not; owner change/sign-out clears it; only the `id` user field is present; event-local context does not leak.
5. **Recording sink tests:** inject an in-memory `RecordingSyncObservationSink` and assert the captured DTO/breadcrumbs.
6. **Sentry adapter mapping tests:** test the pure mapper/scrubber using in-memory objects or an injected capture closure; never call the network transport.

The Sentry adapter itself should be thin enough that one manual integration check is more valuable than a mocked SDK:

- start a production-like build with a real test DSN;
- force one durable sync failure;
- verify its release/environment/tags/context/breadcrumbs and grouping in Sentry;
- force stale-outbox recovery;
- verify one recovery event;
- inspect the raw event JSON for prohibited data;
- repeat the same durable failure and verify every completed occurrence is stored under the same grouped issue.

For tests that must construct the SDK with an empty DSN, Sentry documents that an uninitialized SDK or empty DSN sends no data over the network. That is a safety net, not a substitute for the application-owned recording sink. ([Sentry DSN explainer](https://docs.sentry.io/concepts/key-terms/dsn-explainer/))

## 10. Current Sentry dashboard setup

Sentry's current product model separates detection from action:

```text
Monitor detects a signal -> Sentry creates/updates an Issue -> Alert performs actions
```

Default projects include an Issue Stream Monitor and Error Monitor. Custom Metric Monitors can create issues from thresholds. Alerts then route matching issue transitions to email, Slack, PagerDuty, webhooks, or ticket systems. ([Sentry: Monitors and Alerts](https://docs.sentry.io/product/monitors-and-alerts/), [Sentry: Monitors](https://docs.sentry.io/product/monitors-and-alerts/monitors/), [Sentry: Alerts](https://docs.sentry.io/product/monitors-and-alerts/alerts/))

### Project creation

1. In the Sentry organization, open **Projects > Create Project**.
2. Choose the Apple/iOS platform, name it `baros-ios`, and assign the owning team.
3. Do not accept an onboarding alert throttle that would hide repeated Durable Sync Failures; custom routing is configured below.
4. Create the project and copy its DSN.
5. The DSN remains available at **Project Settings > SDK Setup > Client Keys (DSN)**. ([Sentry: Create a Project](https://docs.sentry.io/product/sentry-basics/getting-started-tutorial/create-new-project/))

### Privacy and ingestion

1. Open **Project Settings > Security & Privacy**.
2. Confirm default data scrubbing is enabled.
3. Prevent storage of IP addresses.
4. Add Baros-specific sensitive field names.
5. Open **Settings > Spike Protection** and leave it disabled for `baros-ios`; it intentionally drops events during a detected spike.
6. After the first archive, verify **Project Settings > Debug Files**.

### Useful issue #50 alert

1. First use the default Error Monitor/grouping with the adapter's stable sync fingerprints.
2. Open **Alerts** (`/monitors/alerts`) and choose **Create Alert**.
3. Source it from `baros-ios` or the relevant Error Monitor.
4. Select the production-like environment(s).
5. Configure an alert for every matching Durable Sync Failure event if Sentry supports that behavior. If it does not, document the exact platform limitation and add the closest event-frequency alert without filtering the stored events.
6. Filter to the Baros sync marker/component and warning/error severity if the UI exposes those attributes for the selected source.
7. Add a direct maintainer action, initially email; add Slack/on-call routing only if that is already an owned operational channel.
8. Name it `Baros durable sync failure`.
9. Exercise it with repeated forced TestFlight failures; confirm every event is stored and document exactly how many notifications Sentry sends.

Do not alert on recovery/info events. Keep those visible for diagnosis and confirmation.

### Optional monitor after real volume exists

Create a volume view or Metric Monitor from an Errors query filtered to `component=sync`, `outcome=failure`, and the production-like environment. Its purpose is measurement and escalation, not filtering: it must not discard or hide the underlying events.

## Acceptance checklist for implementation

- [ ] Sentry package/product is added in `project.yml` and XcodeGen output is regenerated.
- [ ] Sentry startup is skipped in Debug/tests/disabled configurations.
- [ ] TestFlight/App Store environment/channel policy is explicit and verified.
- [ ] Release name and `dist` match the actual bundle version/build.
- [ ] Automatic failed HTTP events and network breadcrumbs are disabled for this scope.
- [ ] `sendDefaultPii` remains false and `beforeSend` enforces the allow-list.
- [ ] A stable Pseudonymous Current Owner ID supports distinct affected-owner counts; raw identifiers and all other user fields are absent.
- [ ] Sync code imports only the Baros observability protocol, not Sentry.
- [ ] Raw `Error`, localized messages, owner tokens, and entity IDs never enter the adapter.
- [ ] Durable classification and fingerprinting have unit tests proving that every repeated durable occurrence reaches a recording sink.
- [ ] The privacy manifest, App Store privacy answers, and published privacy policy are reviewed for the actual configuration.
- [ ] Archive dSYMs upload using a CI secret auth token and appear in Sentry Debug Files.
- [ ] A forced durable failure appears with correct breadcrumbs and no prohibited data.
- [ ] A stale-outbox recovery produces one non-alerting recovery event.
- [ ] A Transient Sync Condition remains a breadcrumb, while every repeated Durable Sync Failure occurrence is stored.
- [ ] Sentry error sampling is 100%, custom DSN rate limits and Spike Protection are off, and Stats is checked for platform-side discarded outcomes.
- [ ] A current Alert notifies for every matching Durable Sync Failure event if Sentry supports it; otherwise, the exact platform limit and closest event-frequency alert are recorded in the release checklist.

## Primary sources

- [GitHub issue #50: Add Sentry observability for sync failures](https://github.com/Tatooles/baros/issues/50)
- [Sentry Apple SDK documentation](https://docs.sentry.io/platforms/apple/guides/ios/)
- [Sentry Cocoa source and releases](https://github.com/getsentry/sentry-cocoa)
- [Sentry Monitors and Alerts](https://docs.sentry.io/product/monitors-and-alerts/)
- [Sentry SDK rate-limiting protocol](https://develop.sentry.dev/sdk/rate-limiting/)
- [Apple: Building your app to include debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)
- [Apple: TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
