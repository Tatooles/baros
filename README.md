# Lifting Log

Native SwiftUI workout logging app for iPhone with a SwiftData-backed offline workout log.

## Requirements

- Xcode 26+
- iOS Simulator runtime
- XcodeGen

## Commands

- `xcodegen generate`
- `xcodebuild build -project LiftingLog.xcodeproj -scheme LiftingLog -destination generic/platform=iOS\ Simulator -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 16,OS=18.6 -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 16,OS=18.6 -only-testing:LiftingLogTests -derivedDataPath /private/tmp/codex-ios-app-derived-data`
- `xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 16,OS=18.6 -only-testing:LiftingLogUITests -derivedDataPath /private/tmp/codex-ios-app-derived-data`

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
