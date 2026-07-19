# App Store Submission Pack

This document is the operator source of truth for submitting Baros 1.0 to App Store Connect.

## App Metadata

- App name: Baros: Workout Tracker
- Subtitle: Simple workout logging
- Primary category: Health & Fitness
- Pricing: Free
- Support URL: https://baros.fit/support
- Privacy Policy URL: https://baros.fit/privacy
- Support contact: support@tatooles.dev
- Copyright: 2026 Kevin Tatooles

## Description Draft

Baros is a private workout tracker for iPhone. Record exercises, sets, weights, reps, notes, and completed workouts without needing an account. Sign in when you want account-backed sync across devices.

The app focuses on fast workout entry, offline-first local logging, workout history, exercise management, data export, and clear privacy controls.

## Keywords Draft

workout, lifting, gym, strength, log, tracker, fitness, exercise, sets, reps

## Age Rating Notes

Baros does not include user-generated public content, commerce, gambling, medical diagnosis, or regulated medical-device functionality. It is a workout logging utility and does not provide medical advice.

## App Privacy Worksheet

### Data Not Linked to an Account

Local workout data can remain only on the user's device when the user is signed out. This includes exercises, sets, workout sessions, notes, settings, and workout history stored locally by the app.

### Data Linked to an Account

When a user signs in, Baros uses Clerk for authentication and Convex for account-scoped sync. Account-linked data can include:

- Email address or Apple private relay email used for authentication.
- Name, display name, and any Clerk profile metadata if enabled or provided.
- Authentication identifiers and session data processed by Clerk.
- Synced exercises, workout sessions, logged exercises, logged sets, and user settings stored in Convex.

### Tracking

Baros does not use third-party advertising, cross-app tracking, or product analytics in the v1 release.

### Diagnostics

Apple, Clerk, Convex, Vercel, and platform providers may process standard service diagnostics needed to operate, secure, and troubleshoot their services. Baros does not add a custom analytics SDK in v1.

## Review Notes Draft

Baros supports signed-out local workout logging. Account creation is optional and enables account-backed sync.

Reviewers can test the app by creating an account with email/password or Sign in with Apple. A disposable reviewer account can be created in production before submission; do not commit that password to the repo.

Important review paths:

1. Open the app and start a local workout.
2. Add exercises, sets, weights, and reps.
3. Finish the workout and view it in History.
4. Open Settings and confirm Export Workout History is present.
5. Sign in and confirm sync status is visible.
6. Open Settings > Privacy & Data and confirm account deletion is available for signed-in users.
7. Open Privacy Policy and Support links from Settings.

Production services:

- Clerk production associated domain: clerk.auth.liftinglog.app
- Convex production deployment URL: https://sensible-reindeer-16.convex.cloud

## Screenshot Plan

Capture final screenshots after UI stabilizes:

- Start workout screen.
- Active workout with exercises and sets.
- Workout history.
- Exercise library.
- Profile or Settings showing sync/export/privacy controls.

## Release Checklist

- Support site is deployed at https://baros.fit/support and remains available at https://support.liftinglog.app/support during the transition.
- Privacy policy is deployed at https://baros.fit/privacy and remains available at https://support.liftinglog.app/privacy during the transition.
- App Settings opens both URLs.
- Release bundle identifier is com.kevintatooles.LiftingLog.
- Release display name is Baros.
- Release build uses production Clerk publishable key.
- Release build uses webcredentials:clerk.auth.liftinglog.app.
- Release build uses https://sensible-reindeer-16.convex.cloud.
- [x] App target includes PrivacyInfo.xcprivacy with required-reason API declarations, including UserDefaults usage, and archive/upload validation passes before App Store submission.
- Final app icon ticket is complete before submission.
- App Store screenshots are final.
- [x] Export compliance answer is ready for standard HTTPS encryption use.
- Pricing and availability are set to Free and the intended launch regions.

## Production Smoke Test

Before submitting to App Review:

1. Install a Release or TestFlight-style build.
2. Create or sign into a disposable production account.
3. Complete one workout.
4. Confirm sync reaches production Convex.
5. Sign out and sign back in.
6. Confirm the completed workout is visible.
7. Export workout history.
8. Confirm account deletion is present in Settings.

If any step fails, document the blocker in issue 14 and do not submit to App Review.
