# Optional App Store update discovery

`AppUpdateService` checks Apple's public lookup endpoint by Baros product ID
6782692304 and the signed-in App Store storefront. It validates product identity,
strict numeric marketing versions and minimum iOS version. No backend or mandatory
update policy is involved.

The last attempt is persisted before asynchronous work and throttles all outcomes
for 24 hours, including offline, malformed and unavailable-storefront results.
A successful response is cached for the remainder of that interval, so deferred
offers survive restart. Foreground revalidates cached results against the current
storefront, installed version, iOS version and dismissed versions. A changed or
unknown storefront suppresses the offer until the next eligible lookup. Clock
rollback conservatively extends the throttle. Later persists that numeric version;
a subsequent release can prompt again. Update opens the regional HTTPS App Store
product URL; installation remains controlled by the App Store.

Only a verified `AppTransaction` with production environment in the production
bundle is eligible. Debug, simulator, UI tests and TestFlight do not perform live
lookups. Unverified/unavailable transactions silently suppress discovery; no
receipt refresh/authentication UI is requested. TestFlight's sandbox environment
is intentionally excluded.

`AppShellView` supplies idle eligibility to `AppUpdatePrompt`: resolved ownership,
completed launch/onboarding decisions, and no nondeleted active workout across any owner (including a
minimized or hidden outgoing-owner workout retained for recovery/discard by #188). The presentation anchor checks the actual window/controller tree
for any presented controller or transition, covering nested feature/Clerk modals.
While an offer is pending it rechecks once per second, allowing dismissal to
settle before presenting a SwiftUI alert. It does no polling without an offer or
while the shell is ineligible/backgrounded. An inline account-resolution gate
introduced by #188 must additionally set `isIdle` false; modal gates are detected
automatically. This change does not modify owner coordination or workout state.

## Deterministic Debug evidence

Launch with `--uitest-update-available`, `--uitest-force-signed-out-auth`,
`--uitest-in-memory-store`, and `--uitest-skip-first-run-experience`.
`--uitest-update-reset` clears only the dedicated update fixture preferences.
Without reset, Later persists across fixture relaunches. The fixture advertises
1.10 over 1.5 and never hits the network. `--uitest-update-delayed` delays the
fixture response four seconds for modal deferral tests. These branches are
compiled only in Debug and use a separate preferences suite.
`--uitest-update-hidden-active-workout` seeds a minimal outgoing-owner active
record only in an in-memory test store. `--uitest-update-hidden-workout-deleted`
marks that fixture deleted, verifying tombstones do not suppress discovery.

## Apple primary documentation checked 2026-10-27

- [Search and lookup API](https://performance-partners.apple.com/search-api): ID-based lookup, software entity, ISO alpha-2 country parameter.
- [Storefront countryCode](https://developer.apple.com/documentation/storekit/storefront/countrycode): ISO alpha-3; Foundation Locale converts to alpha-2, rejecting unknown results.
- [AppTransaction environment](https://developer.apple.com/documentation/storekit/apptransaction/environment): signing environment.
- [AppTransaction shared](https://developer.apple.com/documentation/storekit/apptransaction/shared): verified/unverified results, possible network requirement and thrown errors. Discovery never uses `refresh()`.

Physical App Store/TestFlight distribution and real account storefront changes
require device validation. Simulator fixtures exercise presentation and persistence,
not Apple's live production distribution eligibility or App Store installation.
