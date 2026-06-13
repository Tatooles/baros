# Issue #36 Runbook: Clerk Production Environment

This runbook tracks the manual dashboard work needed before the app can use production Clerk and production Convex for TestFlight and App Store release.

## Goal

Configure the release environment so:

- Debug/local builds continue using development Clerk and development Convex.
- Release/TestFlight/App Store builds use production Clerk and production Convex.
- Sign in with Apple, email/password, Convex auth, sync, and account deletion all work in a production-like TestFlight build.

For v1, do not create a separate staging environment. Use two environments only:

- Development: local development, simulator testing, disposable dev data.
- Production: TestFlight, App Store, production release validation.

## Known App Values

- Apple Team ID: `RJGJJ38RV9`
- Bundle ID: `com.kevintatooles.LiftingLog`
- Development Clerk frontend domain: `glad-krill-22.clerk.accounts.dev`
- Development Convex deployment URL: `https://glad-cow-603.convex.cloud`

Production values will come from the Clerk and Convex dashboards.

## References

- Clerk production deployment: https://clerk.com/docs/guides/development/deployment/production
- Clerk Sign in with Apple setup: https://clerk.com/docs/guides/configure/auth-strategies/social-connections/apple
- Convex Clerk auth: https://docs.convex.dev/auth/clerk
- Apple TestFlight: https://developer.apple.com/testflight/

## Phase 1: Create Clerk Production Instance

Owner: Kevin

1. Open the Clerk Dashboard.
2. Switch from the current development instance to the instance dropdown.
3. Create a production instance.
4. Prefer cloning settings from development unless Clerk warns that a setting must be configured manually.
5. Record these production values somewhere private:
   - Production publishable key, expected prefix `pk_live_`.
   - Production Frontend API / issuer domain.
   - Any Clerk dashboard warnings still blocking production deployment.

Do not commit Clerk secret keys. The iOS app should only need the publishable key.

## Phase 2: Register Native iOS App In Clerk

Owner: Kevin

1. In the production Clerk instance, open Native Applications.
2. Add or confirm the iOS application.
3. Use:
   - App ID Prefix / Team ID: `RJGJJ38RV9`
   - Bundle ID: `com.kevintatooles.LiftingLog`
4. Confirm Clerk shows the native app as configured for production.
5. Record the production associated domain value, expected format:
   - `webcredentials:` followed by the production Frontend API domain.

This value will later replace the development-only associated domain for Release builds.

## Phase 3: Configure Production Sign In With Apple

Owner: Kevin

1. In Clerk production, add Apple as an SSO/social connection.
2. Enable it for sign-up and sign-in.
3. Use custom credentials for production.
4. In Apple Developer, confirm or create the App ID for `com.kevintatooles.LiftingLog`.
5. Ensure the App ID has the Sign in with Apple capability enabled.
6. Create/configure the Apple Services ID required by Clerk.
7. Add Clerk's production Frontend API domain to the Services ID domain configuration.
8. Add Clerk's return URL from the Clerk dashboard to the Services ID return URLs.
9. Create/configure the Apple private key for Sign in with Apple.
10. Enter the Team ID, Services ID, Key ID, and private key into Clerk production.
11. Save the configuration.

Keep the Apple private key secure. Do not put it in the repository.

## Phase 4: Resolve Hide My Email / Private Relay

Owner: Kevin

1. In Clerk's Apple setup, note the Email Source for Apple Private Email Relay.
2. In Apple Developer, configure the email source if Clerk requires it for users who choose Hide My Email.
3. Decide whether v1 requires Clerk-sent account emails to reach users using Hide My Email.
4. Record the decision for App Store submission materials:
   - Configured and verified, or
   - Not used by v1 auth flow, with rationale.

This feeds issue #14 App Privacy and App Review notes.

## Phase 5: Configure Convex Production Auth

Owner: Kevin, with Codex if CLI help is needed

1. Identify or create the production Convex deployment.
2. Set the production Clerk JWT issuer domain on that Convex deployment:

   ```sh
   pnpm exec convex env set CLERK_JWT_ISSUER_DOMAIN 'https://YOUR_PRODUCTION_CLERK_ISSUER_DOMAIN'
   ```

3. Deploy Convex functions to the production deployment.
4. Record the production Convex deployment URL.

The existing `convex/auth.config.ts` reads `CLERK_JWT_ISSUER_DOMAIN`, so the production deployment must have that environment variable set before auth can work.

## Phase 6: Handoff Back To Codex For Code Changes

Owner: Codex

Come back to Codex with these production values:

- Production Clerk publishable key (`pk_live_...`)
- Production Clerk Frontend API / issuer domain
- Production Clerk associated domain (`webcredentials:...`)
- Production Convex deployment URL

Expected code/config work:

1. Make Clerk configuration build-aware:
   - Debug uses development publishable key and associated domain.
   - Release uses production publishable key and associated domain.
2. Make Convex configuration build-aware:
   - Debug uses development Convex URL.
   - Release uses production Convex URL.
3. Update entitlements so Release uses the production associated domain.
4. Add a small `DEV` environment badge in Profile/Settings for Debug builds only.
5. Expand Developer Diagnostics to show:
   - Environment name
   - Clerk associated domain
   - Convex deployment URL
   - Auth state and auth smoke result
6. Update tests for development and release configuration behavior.
7. Update README or release docs with the final production setup.

## Phase 7: TestFlight Verification

Owner: Kevin, with Codex for debugging if needed

Use a Release/TestFlight build and a disposable production account.

Verify:

- App installs from TestFlight on a physical device.
- Email/password sign-up and sign-in work.
- Sign in with Apple works.
- Sign in with Apple using Hide My Email behaves as expected.
- Developer Diagnostics reports the production Convex URL.
- Convex auth smoke check succeeds and shows the production Clerk issuer.
- Create workout data, sync it, reinstall/sign in, and confirm data returns.
- Account deletion removes Clerk account data and Convex sync data.
- Local signed-out/offline logging still behaves as expected.

## Phase 8: Feed Issue #14

Owner: Kevin

Record these outputs for App Store submission materials:

- Production backend is live for review.
- App Review test account instructions, if using email/password.
- Sign in with Apple availability.
- Clerk data collected for App Privacy.
- Convex data stored for App Privacy.
- Hide My Email / Private Relay decision.
- Support and privacy policy URLs.

## Done Criteria For Issue #36

- Production Clerk environment is configured.
- Production native iOS app is registered in Clerk.
- Production Sign in with Apple works on physical device/TestFlight.
- Production Convex auth accepts Clerk tokens from the production issuer.
- Release build does not use `pk_test_` or development Convex URL.
- Debug build still uses development services.
- Clerk-related App Privacy and App Review notes are ready for issue #14.
