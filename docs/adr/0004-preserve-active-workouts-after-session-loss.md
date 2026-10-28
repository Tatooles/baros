# Preserve Active Workouts after session loss

Status: Accepted for 1.5 by Kevin in #188.

## Decision

A confirmed Clerk session ending hides the outgoing owner's data immediately but
never finishes or discards their Active Workout. The saved record remains active.
Starting a second workout is blocked device-wide until the original owner signs
back in and resolves it, or someone explicitly confirms discarding the hidden
workout. The recovery notice reveals no account, workout, exercise, or set details.
A failed discard save keeps the workout and the start block.

Temporary Convex authentication loss, offline operation, and Current Owner
resolving do not terminalize workouts. Recovery UI waits through unknown-owner
startup resolution. Nothing adds a paused/draft state or Active Workout sync.

User-initiated sign-out/switch must successfully finish or discard the outgoing
owner's accessible active workouts before calling Clerk. Another owner's hidden
record is preserved and continues blocking new starts; it must not trap a different
account in a signed-in session. Delete Account still blocks hidden active records,
because its existing local-data reset would erase them. Multiple outgoing workouts
are finalized in one transaction, with timer/sync effects deferred until it saves. Cancel preserves the workout and account.
Confirmation captures the owner and workout IDs; changed inputs invalidate it.
If Clerk fails after successful workout persistence, keep the saved terminal
workout and report the account-action error rather than resurrecting it.

Legacy multiple-active records are never silently discarded on load. They block
starting another workout and can be explicitly resolved. This cannot retroactively
prevent old stores containing multiple records; it prevents adding to them.

## Module and SDK audit

`Core/AccountTransition` contains the account-action gate and durable recovery
policy, plus their small SwiftUI presenters. Callers provide an account action;
the module reuses `ActiveWorkoutEngine.finishWorkout` / `discardWorkout`.
`CurrentOwnerCoordinator` remains the sole authority for owner lifecycle and
local-data visibility. No backend or schema changes are needed.

The pinned Clerk iOS 1.1.3 revision is
`5f9567a1ef4cd47ac4cfe9b1d4c0d400af62202b`.

- `UserProfileView` unconditionally adds Sign Out and can expose Switch Account,
  Add Account, Security/session revocation, and account deletion. Its customization
  interface adds rows/destinations; it cannot replace/remove built-ins or intercept
  their account mutations.
- Baros therefore resolves outgoing-owner active workouts before presenting this profile.
  It dismisses the profile on a Clerk session replacement, including a switch that
  reveals a preserved active workout. While
  that screen is open, the engine blocks workout starts, including another window.
- With an active workout, Settings exposes Baros's direct gated Sign Out and
  gated Manage Account. Without one, the existing Clerk profile opens normally.
- Baros's own Delete Account confirmation uses the same gate before cloud/account
  deletion. Explicit Delete Local Data retains its existing whole-store contract.
- Signed-out sign-in surfaces remain available for recovering the original owner.
  Signing into another owner never bypasses the engine's device-wide start check.

No Clerk fork or parallel finalization path is introduced.

Product decision: https://github.com/Tatooles/baros/issues/188#issuecomment-6459620433
