# Issue #36 Runbook: Separate Debug App ID

This runbook is the user-facing checklist for making the Debug/Xcode build install as a separate app from the TestFlight/App Store build.

Use this when you want:

- `Lifting Log` from TestFlight/App Store for real day-to-day production use.
- `Lifting Log Dev` from Xcode for local feature work.
- Both apps installed on the same iPhone at the same time.

## Goal

Create a second app identity for development only:

- Production/TestFlight/App Store:
  - App name: `Lifting Log`
  - Bundle ID: `com.kevintatooles.LiftingLog`
  - Clerk: production
  - Convex: production
- Debug/Xcode:
  - App name: `Lifting Log Dev`
  - Bundle ID: `com.kevintatooles.LiftingLog.dev`
  - Clerk: existing development instance
  - Convex: existing development deployment

This does not add another Clerk instance or another Convex deployment.

## Known Values

- Apple Team ID / App ID prefix: `RJGJJ38RV9`
- Production bundle ID: `com.kevintatooles.LiftingLog`
- New Debug bundle ID: `com.kevintatooles.LiftingLog.dev`
- Development Clerk frontend domain: `glad-krill-22.clerk.accounts.dev`
- Development Convex URL: `https://glad-cow-603.convex.cloud`

## Before You Start

Confirm you are working in the development Clerk instance, not production, for the Clerk steps below.

The only manual setup you need to do is:

1. Add a new Apple App ID for the Debug app.
2. Add that Debug app to the existing development Clerk Native Applications config.
3. Tell Codex when those two dashboard changes are done.

Codex will handle the project/code changes after that.

## Phase 1: Add The Debug App ID In Apple Developer

Owner: Kevin

1. Open Apple Developer.
2. Go to:

   ```text
   Certificates, Identifiers & Profiles -> Identifiers
   ```

3. Click the `+` button.
4. Choose:

   ```text
   App IDs
   ```

5. Continue with:

   ```text
   Type: App
   ```

6. Enter:

   ```text
   Description: XC com kevintatooles LiftingLog Dev
   Bundle ID: Explicit
   Bundle ID value: com.kevintatooles.LiftingLog.dev
   ```

7. Enable these capabilities:

   ```text
   Associated Domains
   Sign in with Apple
   ```

8. Click `Continue`.
9. Review the details.
10. Click `Register`.

Expected result:

```text
Apple Developer now has an App ID for com.kevintatooles.LiftingLog.dev.
The prefix/team id is RJGJJ38RV9.
Associated Domains is enabled.
Sign in with Apple is enabled.
```

Do not create a new Clerk instance, Convex deployment, or production domain.

## Phase 2: Add The Debug iOS App In Clerk Development

Owner: Kevin

1. Open Clerk Dashboard.
2. Make sure you are in the development Clerk app/instance.
3. Go to:

   ```text
   Configure -> Developers -> Native applications
   ```

4. Open the `iOS` tab.
5. Click `Add iOS app`.
6. Enter:

   ```text
   App ID prefix: RJGJJ38RV9
   Bundle ID: com.kevintatooles.LiftingLog.dev
   ```

7. Save/add the app.

Expected result:

```text
The iOS applications list includes com.kevintatooles.LiftingLog.dev.
```

## Phase 3: Add The Debug Redirect URL In Clerk Development

Owner: Kevin

Stay on the same Clerk development Native Applications page.

1. Find:

   ```text
   Allowlist for mobile SSO redirect
   ```

2. Add this redirect URL:

   ```text
   com.kevintatooles.LiftingLog.dev://callback
   ```

3. Keep the existing redirect URL:

   ```text
   com.kevintatooles.LiftingLog://callback
   ```

Expected result:

```text
Both redirect URLs are present:
- com.kevintatooles.LiftingLog://callback
- com.kevintatooles.LiftingLog.dev://callback
```

## Phase 4: Confirm Clerk AASA Includes The Debug App

Owner: Kevin

Open this URL in a browser:

```text
https://glad-krill-22.clerk.accounts.dev/.well-known/apple-app-site-association
```

Look for this value:

```text
RJGJJ38RV9.com.kevintatooles.LiftingLog.dev
```

It is okay if the JSON has other values too. The order does not matter.

Expected result:

```text
The AASA file includes RJGJJ38RV9.com.kevintatooles.LiftingLog.dev.
```

If it does not appear immediately, wait a few minutes and refresh. Clerk/Apple-related domain files can lag briefly after dashboard changes.

## Phase 5: Handoff Back To Codex

Owner: Kevin

Send Codex this message:

```text
Debug app ID setup is ready.

Apple Developer:
- Prefix: RJGJJ38RV9
- Bundle ID: com.kevintatooles.LiftingLog.dev
- Associated Domains enabled: yes
- Sign in with Apple enabled: yes

Clerk dev:
- Native iOS app added: com.kevintatooles.LiftingLog.dev
- Redirect URL added: com.kevintatooles.LiftingLog.dev://callback
- AASA includes: RJGJJ38RV9.com.kevintatooles.LiftingLog.dev
```

## Phase 6: Codex Code Changes

Owner: Codex

Codex will then update the project so:

- Debug builds use:

  ```text
  App name: Lifting Log Dev
  Bundle ID: com.kevintatooles.LiftingLog.dev
  Clerk: development
  Convex: development
  ```

- Release builds use:

  ```text
  App name: Lifting Log
  Bundle ID: com.kevintatooles.LiftingLog
  Clerk: production
  Convex: production
  ```

Expected repo changes:

- `project.yml`
- `LiftingLog.xcodeproj/project.pbxproj`
- Configuration tests that prove Debug and Release resolve to the expected app identities.

Codex will verify:

- Debug build settings point at the dev bundle id and dev backend values.
- Release build settings still point at the production bundle id and production backend values.
- Debug can install and launch on your iPhone as `Lifting Log Dev`.

## Phase 7: Phone Verification

Owner: Kevin, with Codex running the build

After Codex installs the Debug build on your phone, verify:

- The installed app name is `Lifting Log Dev`.
- The app does not replace the production/TestFlight `Lifting Log` app.
- Profile shows the `DEV` badge.
- Settings -> Developer Diagnostics shows:

  ```text
  Environment: Development
  Clerk Domain: webcredentials:glad-krill-22.clerk.accounts.dev
  Deployment: https://glad-cow-603.convex.cloud
  ```

When TestFlight is ready, install the TestFlight app and confirm:

- `Lifting Log` and `Lifting Log Dev` are both installed.
- `Lifting Log` does not show the `DEV` badge.
- `Lifting Log Dev` does show the `DEV` badge.

## Done Criteria

This Debug app ID split is done when:

- Apple Developer has `com.kevintatooles.LiftingLog.dev`.
- Clerk development has `com.kevintatooles.LiftingLog.dev` under Native Applications.
- Clerk development has `com.kevintatooles.LiftingLog.dev://callback` in the mobile SSO redirect allowlist.
- Debug installs as `Lifting Log Dev`.
- Release/TestFlight installs as `Lifting Log`.
- Both can live on the same iPhone at the same time.

Do not close issue #36 just because this runbook is complete. Issue #36 still needs production auth/TestFlight verification before closing.
