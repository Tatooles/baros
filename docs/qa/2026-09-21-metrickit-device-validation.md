# MetricKit validation progress — 2026-09-21

PR: [#263](https://github.com/Tatooles/baros/pull/263). Acceptance issue: [#262](https://github.com/Tatooles/baros/issues/262).

## Completed

- Built, installed, and launched Baros Dev 1.3 (1) on Kevin's iPhone 17 running iOS 27.0, using the Baros scheme and Debug configuration. Verified the built app has `com.kevintatooles.LiftingLog.dev`, `BarosEnvironment=Development`, `SentryEnabled=YES`, and the existing project DSN. A local app dSYM exists. No App Store app replacement or data reset occurred.
- Installed binary metadata: `f6c545f` with local changes, built at `2026-09-21 23:02:02 -0500`. Those executable changes are the Debug-only opt-in committed as `b904ba0`; subsequent reporting corrections are not included in this installed binary.
- Kevin confirmed normal behavior after opening What's New from Settings, switching tabs, opening a workout and Add Exercise, then backgrounding and reopening the app. This is user-observed UI behavior, not inspection of emitted context. First-run onboarding was not separately verified.
- Configuration checks executed against the actual configuration type with and without `DEBUG`: explicit Development opt-in works only in Debug; missing DSN, disabled flag, and unknown environment remain disabled; Production remains enabled with its existing requirements.
- Hosted unit tests passed on `b904ba0` (838 tests, zero failures), and hosted UI smoke passed in [App CI](https://github.com/Tatooles/baros/actions/runs/35685768602). This result does not validate later revisions.
- Created and read back [Baros MetricKit diagnostics](https://kevin-tatooles.sentry.io/monitors/alerts/6044365/): production-only, diagnostic marker match, no severity/priority filter, email to Kevin, 60-minute per-issue throttle.

## Not yet demonstrated

- The local focused XCTest build succeeded, but its runner stalled and the tool timed out after 300 seconds; the remaining runner was stopped. No passing local XCTest result is claimed for that attempt.
- Xcode's documented simulated-payload command was not accessible through the inspected Xcode 27 UI. No MetricKit payload was injected, and no development event was found in Sentry during this session.
- Actual subscription/delivery, preserved event fields, emitted UI restoration, release dSYM upload and readable Baros frames, and alert email delivery remain unverified. Existing alert configuration and a local dSYM are not proof of these gates.
- The existing hang detector remains enabled. Do not close #262 or claim a validated detector replacement from the build and phone walkthrough alone.
