# Issue #47 Active Workout accessory prototype

This throwaway native SwiftUI prototype answers whether an expanded bottom accessory feels visually balanced above Baros's three permanent tabs on iOS 26. It compares a status-rich accessory, a quiet accessory, and the baseline with no accessory; use the prototype-only arrow control to switch variants.

The accepted direction is **A — Status-rich**. On iPhone, the system widens the three-tab capsule to the accessory's outer width while the accessory is present, so the two native Liquid Glass surfaces align. The accepted row shows workout name, minute-level elapsed time, and completed/total set progress as one Return to Workout action.

The prototype also records the deployment boundary: iOS 26.1 and later use `tabViewBottomAccessory(isEnabled:content:)`, while iOS 26.0 conditionally composes the original accessory modifier.
