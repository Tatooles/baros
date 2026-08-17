# Active Workout pinned-tab patterns

Research date: 2026-08-17

## Accepted direction

Baros will not use a conditional pinned tab. The permanent tab order is History, Home, Profile, with Home selected by default. Active Workout is a focused full-screen session that can be minimized without being finished. Its sole visible minimize affordance is the native system grabber: swipe or VoiceOver dismissal minimizes the workout, while Finish remains a separate action in the existing workout header. While minimized, a native tab-view bottom accessory shows the workout name, minute-level elapsed time, and completed/total set progress and reopens the session as one full-surface action. The first version keeps the tab bar at normal size, so the accessory stays expanded above it; an inline adaptive layout is deferred.

An iPhone 17 Simulator prototype using Baros's dark theme confirmed that the native expanded accessory and the three-tab capsule share the same outer width while the accessory is present. The prototype compared a status-rich row, a quiet row, and no accessory; the status-rich row was accepted.

At accessibility text sizes, the visible status row may simplify to workout name and elapsed time rather than shrink or truncate. Set progress remains in the combined VoiceOver value, the accessory remains one Return to Workout action, and periodic time updates do not trigger announcements.

Baros retains its iOS 26.0 deployment target. The dynamically enabled accessory overload is available on iOS 26.1 and later. The iOS 26.0 fallback conditionally composes the original accessory modifier at one shell boundary; deployment support is not narrowed for this convenience API.

The selected permanent tab remains underneath the full-screen workout. Start and active-workout relaunch put Home underneath; reopening from History or Profile preserves that tab so minimizing returns to the person's prior context. Finish, discard, and owner-change removal always select Home, following #174.

This direction preserves truthful tab selection and uses Apple's explicitly dynamic accessory pattern. A conditional pinned tab remains useful research evidence and a rejected alternative.

The absence of the tab bar during the focused workout leaves room for a future workout-specific bottom utility bar. That possibility is intentionally outside #47; the navigation design must not define or implement its contents.

## Platform findings

- SwiftUI defines `TabPlacement.pinned` and `TabContent.tabPlacement(_:)`. Apple's example applies `.tabPlacement(.pinned)` to a normal Downloads destination rather than a Search tab, establishing that pinned placement is not semantically restricted to search. [Apple: `tabPlacement(_:)`](https://developer.apple.com/documentation/swiftui/tabcontent/tabplacement(_:))
- UIKit describes pinned placement as putting a tab at the trailing edge of the tab bar. [Apple: `UITab.Placement.pinned`](https://developer.apple.com/documentation/uikit/uitab/placement/pinned)
- Apple cautions that not every `TabView` style supports every placement. A native iPhone prototype was therefore used before rejecting the pinned-tab direction and accepting the expanded accessory. [Apple: `TabPlacement`](https://developer.apple.com/documentation/swiftui/tabplacement)
- A bottom accessory is a different native pattern. On iPhone it appears above a normal-size tab bar and can move inline when the bar collapses. Apple presents this as suitable for persistent status content, including the Music MiniPlayer pattern. [Apple: `tabViewBottomAccessory`](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)) and [Apple HIG: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

## Terminology

| Term | Meaning | Fit for Baros |
| --- | --- | --- |
| Pinned tab | A real top-level destination placed at the trailing edge of the tab bar | Rejected for Active Workout because its conditional presence destabilizes the tab set |
| Conditional pinned tab | Product-specific phrase for a pinned tab that exists only during an Active Workout | Rejected alternative |
| Detached or separated tab | Informal visual description | Useful in conversation, but less precise |
| Floating action button / center action button | A visually prominent control that performs or launches an action | Fits Bevel's `+`-style inspiration, but not Baros if tapping switches to a persistent workout destination |
| Bottom accessory / mini-player | Persistent status and re-entry content attached to a tab bar | Accepted re-entry pattern while an Active Workout is minimized |

## Comparable products and patterns

- **Bevel**: the supplied screenshot shows a circular `+` control detached from the main tab capsule. Treat it as visual inspiration for prominence, not proof of navigation semantics; `+` conventionally signals creation/logging.
- **YouTube**: official help directs people to tap **Create** at the bottom and then choose an operation such as Video or Live. This is an action-control precedent, not a destination precedent. [YouTube Help: Upload videos](https://support.google.com/youtube/answer/57407) and [Create a live stream](https://support.google.com/youtube/answer/9228390)
- **Fitbit**: official help describes a lower-right `+` used to add an activity. This is another adjacent floating-action precedent. [Fitbit Help: Add, edit, or delete data and activities](https://support.google.com/fitbit/answer/14236402)
- **Strava**: official help calls **Record** a bottom-navigation destination and uses it to enter and return to the recording experience. This is behaviorally closer to Active Workout, although the cited documentation does not establish a detached visual treatment. [Strava Help: Recording an Activity](https://support.strava.com/en-us/articles/15402137-recording-an-activity)
- **Nike Run Club**: official help treats **Run** as a dedicated tab for configuring and starting a run. It supports the high-priority workout-destination model, but not necessarily a separated tab. [Nike Help: Get started in NRC](https://www.nike.com/help/a/nrc-start-run)
- **Apple Music on iOS 26**: Apple's tab-bar guidance uses the MiniPlayer as the canonical attached accessory for an ongoing activity. This is the strongest precedent for Baros's accepted Active Workout accessory. [Apple HIG: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

## Design boundary

Do not assign the Search role to Active Workout. Search is a semantic role with search-specific behavior and presentation. The accepted design uses a bottom accessory for re-entry and does not add an Active Workout tab. [Apple: Search tab role](https://developer.apple.com/documentation/swiftui/tabrole/search)
