# Investigating hangs with MetricKit and UI context

Baros enables the Sentry Cocoa MetricKit integration for builds where Sentry itself is enabled. The SDK subscribes to Apple's hang, CPU, and disk-write diagnostic reports. Ordinary crash reporting and the existing durable-sync privacy boundary remain unchanged. Raw MetricKit attachments are disabled.

This improves the evidence available for investigation; it does not guarantee a report or root cause for every freeze and does not detect arbitrary incorrect app behavior.

## Read the report correctly

- The supported MetricKit mechanisms are `mx_hang_diagnostic`, `mx_cpu_exception`, and `mx_disk_write_exception`. The pinned SDK reports these as warnings, so fatal-only alert rules do not cover them.
- The pinned SDK uses `MXDiagnosticPayload.timeStampBegin` as the event timestamp. `diagnostic_timestamp_basis=payload_interval_start` makes that explicit. It is not an exact interaction time or delivery time.
- The SDK applies the current Sentry scope and build to reports that may describe earlier activity. Baros moves the current release, dist, distribution channel, app/device/OS context, and validated UI context into `diagnostic_delivery`. `received_at` is the Unix time when the report passes the final filter.
- Top-level release/dist, user, trace, and breadcrumbs are removed from MetricKit events to avoid attributing an older diagnostic to a newer build, signed-in owner, or unrelated interaction. The original diagnostic exceptions, duration text, threads, stack samples, and debug-image UUIDs remain intact.
- `diagnostic_delivery` describes the receiving app. Do not use its build or screen as proof of the incident's source. The stock integration does not expose the diagnostic's original app-version metadata to `beforeSend`; an incident release may therefore be unknown. Use diagnostic binary UUIDs and the matching dSYMs to locate the affected code.
- Ordinary crash/legacy-hang events retain their incident context. MetricKit is an additional diagnostic source, not evidence that `BAROS-IOS-X` was a particular app defect or a false positive.

## UI context

The existing `ui_surface` tag names the top covered surface. The allowlisted `ui` context adds `base_screen` (`launch`, `home`, `history`, `profile`) and `scene_phase` (`active`, `inactive`). Launch presentations distinguish `onboarding`, `whats_new`, and `active_workout`; `exercise_picker` identifies Add Exercise over Active Workout. These labels identify covered surfaces, not every nested navigation destination or modal in the app.

Workout scale remains bucketed, and focused fields remain categories. Counts may be absent while the shell begins presenting a workout before its content appears. Backgrounding removes visible UI context; foregrounding restores the current surface without stale field focus. Dismissal restores the underlying tab. Predefined, deduplicated breadcrumbs record tab/presentation/lifecycle transitions and existing Add Exercise/search transitions.

No user-authored content, exact workout values, search text, or record/account identifiers are added. Sync events still remove UI context and use their strict existing allowlist.

## Validation and detector cutover

**The existing Sentry app-hang detector remains enabled.** Do not disable it solely because the option compiles or unit tests pass. The temporary overlap can produce separate reports for the same hang. Track the source by exception mechanism; do not assume one-to-one matching or deduplicate unrelated samples by title.

Required release evidence:

1. Build/run a Debug copy on a physical iPhone with Sentry explicitly enabled and the existing project DSN. Keep the Development environment and development bundle ID; do not replace the App Store installation or clear app data. Start from a clean app launch so SDK subscriptions are installed.
2. While attached in Xcode, choose **Debug > Simulate MetricKit Payloads**. Inspect the actual events in the existing Sentry project. Record the build/source revision and event links for the supported diagnostic types. Verify mechanism, timestamp-basis label, preserved diagnostic data, and the explicitly labeled delivery context. Synthetic payloads validate subscription/conversion/transport, not capture of a real user hang.
3. Exercise onboarding, What's New, main tabs, Active Workout, and Add Exercise. Verify covered context on inspected diagnostic/test events, including dismissal and background/foreground transitions. Delivery UI on synthetic MetricKit reports should describe where the report was received.
4. Verify the release archive contains app/extension dSYMs and the existing `project.yml` upload phase sends them to Sentry. Confirm a matching binary UUID in Sentry Debug Files and readable app frames using a suitable fixture or controlled device diagnostic. Apple's stock synthetic payload can refer to unrelated sample binaries; it alone cannot prove Baros symbolication. Do not ship a deliberate hang trigger.
5. Record local tests, hosted CI, device behavior, event ingestion, and dSYM evidence separately. A simulator cannot demonstrate real MetricKit delivery. Retain missing evidence as pending.
6. Once those checks pass, explicitly disable both `enableAppHangTracking` and `enableAppHangTrackingV2` in the main app's Sentry options, keeping `enableMetricKit` enabled. Verify ordinary crash and sync reporting still work. Check that the relevant Sentry alerts include MetricKit warning events before relying on them. This cutover needs its own reviewed change if validation happens after this PR merges.

## Implementation references

- `Baros/Core/Sync/SentrySyncObservability.swift`: enablement, final event filtering, and timing/attribution handling.
- `Baros/Core/Observability/UIHangContextObservability.swift`: bounded screen/presentation state and transitions.
- `Baros/App/AppShellView.swift`: shell/lifecycle observation; workout/picker views retain their existing context hooks.
- `project.yml`: release dSYM generation and upload. The project already emits dSYMs in Debug too.
- [Sentry MetricKit integration](https://docs.sentry.io/platforms/apple/configuration/metric-kit/)
- [Sentry hang detector migration guidance](https://docs.sentry.io/platforms/apple/configuration/app-hangs/)
- [Pinned SDK diagnostic mapping](https://github.com/getsentry/sentry-cocoa/blob/9.25.0/Sources/Swift/Core/MetricKit/SentryMXManager.swift)
- [Pinned SDK scope/default application before beforeSend](https://github.com/getsentry/sentry-cocoa/blob/9.25.0/Sources/Sentry/SentryClient.m)
