# Active Workout navigation design

Decision date: 2026-08-17

## Decision

Baros uses three permanent native tabs in this order: **History, Home, Profile**. Home is selected by default.

An Active Workout is a focused, full-height session presented above the tab shell. The native sheet grabber is its only visible minimize control. Minimizing keeps the workout active and reveals a native bottom accessory; tapping that accessory returns to the same workout.

The accessory uses the accepted status-rich treatment: workout name, minute-level elapsed time, and completed/total set progress. Its entire surface is one **Return to Workout** action.

## Navigation model

| State or event | Presentation | Tab behavior |
| --- | --- | --- |
| No Active Workout | Tabs only; no accessory | Home is the default |
| Start or relaunch with an Active Workout | Full-height workout session | Home remains underneath |
| Minimize | Session closes; accessory appears | Reveal the tab underneath |
| Reopen from History or Profile | Session appears above that tab | Preserve the selected tab |
| Finish, discard, or owner change | Session and accessory disappear | Select Home |

The minimized state is not restored across process relaunch. If an Active Workout exists at launch, Baros presents it directly as required by #174.

## Native presentation

- Keep SwiftUI's native `TabView` and iOS 26 Liquid Glass tab bar.
- Present the workout with a native full-height sheet and visible system grabber. Do not add a custom chevron or minimize button.
- Keep the workout's existing elapsed-time, set-progress, and Finish header unchanged.
- Keep the tab bar at normal size with `tabBarMinimizeBehavior(.never)` in the first version.
- Use `tabViewBottomAccessory` for the minimized workout. Do not add custom glass chrome.
- Keep accessory content expanded above the tab bar; inline adaptation is deferred.

Apple documents the bottom accessory as supplementary content above a normal tab bar and inline content when the bar collapses. Baros intentionally keeps the normal expanded placement for the first version. [Apple: `tabViewBottomAccessory`](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)) and [Apple: `TabViewBottomAccessoryPlacement`](https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement)

## Prototype result

A native SwiftUI prototype was built and visually inspected on an iPhone 17 Simulator running iOS 26.4 with Baros's dark theme. With the accessory present, the system widened the three-tab capsule to the accessory's outer width, so the two native glass surfaces aligned.

Three treatments were compared. The status-rich treatment was accepted over a quieter row and the no-accessory baseline.

- [Throwaway prototype branch](https://github.com/Tatooles/baros/tree/codex/issue-47-accessory-prototype)
- [Accepted status-rich render](https://github.com/Tatooles/baros/blob/codex/issue-47-accessory-prototype/Baros/Features/Prototype/Screenshots/status-rich.jpg)
- [Quiet alternative](https://github.com/Tatooles/baros/blob/codex/issue-47-accessory-prototype/Baros/Features/Prototype/Screenshots/quiet.jpg)
- [No-accessory baseline](https://github.com/Tatooles/baros/blob/codex/issue-47-accessory-prototype/Baros/Features/Prototype/Screenshots/baseline.jpg)

## OS availability

Baros keeps its iOS 26.0 deployment target.

- On iOS 26.1 and later, use `tabViewBottomAccessory(isEnabled:content:)` to show and hide the accessory.
- On iOS 26.0, conditionally compose the original accessory modifier at one shell boundary.
- Keep tab selection and navigation paths outside that compatibility boundary.

The newer overload exists specifically for dynamic accessory visibility. Supporting iOS 26.0 requires a small localized fallback, not a second navigation architecture. [Apple: dynamically enabled bottom accessory](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isEnabled:content:))

## Accessibility and adaptive layout

- Expose the accessory as one button labeled **Return to Workout**.
- Include workout name, elapsed time, and set progress in its accessibility value.
- Keep the full surface at least 44 points tall.
- Do not announce periodic elapsed-time updates automatically.
- At accessibility text sizes, simplify the visible row to workout name and elapsed time rather than shrinking or truncating text; keep set progress in the accessibility value.
- Treat sheet dismissal, including the VoiceOver dismissal action, as minimize—never finish or discard.
- Resign workout field focus through the existing commit path before minimizing so pending drafts are retained.

Apple's sheet guidance identifies the grabber as both a visual resizability affordance and a control VoiceOver can use. [Apple HIG: Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)

## Rejected alternatives

- **Conditional pinned Workout tab:** changes the available tab set as workout state changes and weakens navigation predictability.
- **Permanent dual-purpose Workout control:** changes between an action and a destination, which conflicts with tab semantics and duplicates Home's start flow.
- **Workout inside Home's navigation stack:** leaves Home visibly selected while showing no Home content.
- **Custom tab bar:** gives up native Liquid Glass behavior, accessibility, and system adaptation without solving a product requirement.

## Scope boundary

Issue #47 owns the permanent tab shell, Active Workout presentation, minimize/reopen behavior, accessory, and lifecycle selection mechanics. Issue #174 owns Home and the Start Workout flow. Inline accessory adaptation and a workout-specific bottom utility bar are future refinements.
