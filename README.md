# Baros

Native SwiftUI workout tracker for iPhone with a SwiftData-backed offline workout log.

## Requirements

- Xcode 26+
- iOS Simulator runtime
- XcodeGen

## Commands

- Generate project: `xcodegen generate`
- Build simulator app: `xcodebuild build -project Baros.xcodeproj -scheme Baros -destination generic/platform=iOS\ Simulator -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- Run full XCTest suite: `xcodebuild test -project Baros.xcodeproj -scheme Baros -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- Run unit tests only: `xcodebuild test -project Baros.xcodeproj -scheme BarosUnitTests -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- Run UI tests only: `xcodebuild test -project Baros.xcodeproj -scheme Baros -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -only-testing:BarosUITests -derivedDataPath /private/tmp/codex-ios-app-derived-data`

## CI

Pull requests and pushes to `main` run two GitHub Actions checks:

- `ios-unit-tests`: builds the `BarosUnitTests` scheme and runs `BarosTests`.
- `convex-checks`: runs Convex Vitest coverage and Convex typecheck.

The iOS job intentionally excludes `BarosUITests` from the required PR gate. If `ios-unit-tests` fails, first inspect the GitHub Actions log. The failed workflow run also uploads a `BarosTests-xcresult` artifact containing the `.xcresult` bundle and test log for local Xcode inspection.

The canonical local UI-suite command is the `Run UI tests only` command above. As of issue #63, the expected UI target discovery count is 29 tests; treat a run with fewer discovered or executed tests as partial coverage, not a clean full-suite result. Keep the full UI target out of the required PR gate until it can pass repeated local full-suite runs without known flakes.

Local equivalents:

```sh
xcodebuild test -project Baros.xcodeproj -scheme BarosUnitTests -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.5 -derivedDataPath /private/tmp/codex-ios-app-derived-data
pnpm install --frozen-lockfile
pnpm run convex:test
pnpm run convex:typecheck
```

## Convex Setup

Convex auth requires the Clerk JWT issuer domain to be configured on each Convex deployment. For the current development Clerk instance, set:

```sh
pnpm exec convex env set CLERK_JWT_ISSUER_DOMAIN 'https://glad-krill-22.clerk.accounts.dev'
```

Then push the backend functions to the development deployment:

```sh
pnpm exec convex dev --once
```

Do not rely on a backend fallback for this value. Staging and production deployments should set their own Clerk issuer domain before deploying Convex functions.

### Production Convex reference

Release builds point at the production Convex deployment:

```sh
https://sensible-reindeer-16.convex.cloud
```

Use this section when preparing an App Store release candidate or troubleshooting production auth/sync. Routine app changes do not require running the full production smoke every time.

The production Clerk JWT template should be configured for Convex:

- JWT issuer: `https://clerk.auth.liftinglog.app`
- JWT audience: `convex`

Configure or verify the production Convex deployment with the matching issuer domain:

```sh
pnpm exec convex env --prod set CLERK_JWT_ISSUER_DOMAIN 'https://clerk.auth.liftinglog.app'
pnpm exec convex env --prod get CLERK_JWT_ISSUER_DOMAIN
```

Deploy the current Convex functions to production:

```sh
pnpm exec convex deploy
pnpm exec convex function-spec --prod
```

For RC validation or production auth/sync troubleshooting, run a focused production smoke:

1. Sign in with the production Clerk account flow from a Release or TestFlight build.
2. Confirm Settings shows Sync Status: Up to date.
3. Exercise the release smoke flow that needs Convex auth, such as account deletion.
4. If a direct `authSmoke:me` check is needed, run it from a Debug build temporarily pointed at the production Clerk and Convex values because Developer Diagnostics is Debug-only.

Record smoke-test evidence on the relevant release issue when the check is part of release validation.

## Agent / MCP Workflow

This repo includes `.xcodebuildmcp/config.yaml` for agents that use XcodeBuildMCP.

Install XcodeBuildMCP locally and install its MCP server skill:

```sh
xcodebuildmcp init --client agents --skill mcp
```

Then run project setup as needed:

```sh
xcodebuildmcp setup
```

Keep physical device IDs and machine-specific simulator UUIDs in local session defaults. Do not commit them to the repo config.
