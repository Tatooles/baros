# Lifting Log

Native SwiftUI workout logging app for iPhone with a SwiftData-backed offline workout log.

## Requirements

- Xcode 26+
- iOS Simulator runtime
- XcodeGen

## Commands

- `xcodegen generate`
- `xcodebuild build -project LiftingLog.xcodeproj -scheme LiftingLog -destination generic/platform=iOS\ Simulator -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLogUnitTests -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.0 -only-testing:LiftingLogUITests -derivedDataPath /private/tmp/codex-ios-app-derived-data`

## CI

Pull requests and pushes to `main` run two GitHub Actions checks:

- `ios-unit-tests`: builds the `LiftingLogUnitTests` scheme and runs `LiftingLogTests`.
- `convex-checks`: runs Convex Vitest coverage and Convex typecheck.

The iOS job intentionally excludes `LiftingLogUITests` from the required PR gate. If `ios-unit-tests` fails, first inspect the GitHub Actions log. The failed workflow run also uploads a `LiftingLogTests-xcresult` artifact containing the `.xcresult` bundle and test log for local Xcode inspection.

Local equivalents:

```sh
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLogUnitTests -destination platform=iOS\ Simulator,name=iPhone\ 17,OS=26.5 -derivedDataPath /private/tmp/codex-ios-app-derived-data
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
