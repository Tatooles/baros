# Baros

Baros records workouts locally and can connect owner-scoped data to cloud sync.

## Language

**Current Owner**:
The validated identity, if any, whose owner-scoped data the app may display and synchronize. Its lifecycle has three states: local-only, resolving, and active. While the app determines an identity, the current owner is resolving. If no signed-in identity owns the data, the app operates local-only.
A previously validated owner remains current during temporary revalidation when the signed-in identity has not changed. Its cached data remains visible, while cloud synchronization waits for successful validation.
While that owner is resolving, their local changes remain owner-scoped and queue for later synchronization.
An owner identified by the signed-in account may access and edit their local data while backend authentication is resolving; cloud synchronization remains paused.
Being offline does not clear the current owner. The owner and cached data remain available until the app confirms a sign-out or a different identity.
When the signed-in identity changes, the previous owner's data becomes inaccessible immediately while the new owner is resolving.
Clearing the current owner removes access to that owner's local data and cloud synchronization; it does not itself delete stored records. Removing local data after sign-out is a separate workflow.
_Avoid_: Sync Access, authentication state, sync state

**Unclaimed Local Data**:
Local data that has never been assigned to an owner. When someone begins in local-only mode and later signs in to a new account, unclaimed local data becomes theirs and uploads to that account. Data associated with a previous owner is not unclaimed and must never move to a different owner.
_Avoid_: Unowned data, hidden owner data

**Active Workout**:
A workout in progress whose exercises and sets remain editable until the workout is finished or discarded.
_Avoid_: Workout draft, live session

**Exercise Performance**:
A completed workout in which an exercise has at least one completed set. An exercise counts at most once per workout, even when it appears more than once.
_Avoid_: Completed set count, exercise appearance
