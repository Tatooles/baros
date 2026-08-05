# Clerk controls local owner access; Convex controls synchronization

The Clerk-authenticated identity is the authority for which owner's local data may be displayed and edited, while Convex authentication only gates cloud synchronization. If Convex is loading, offline, or authenticated as a different identity, the app keeps the Clerk owner's local data available, pauses sync, and rejects any mismatched Convex identity; this preserves offline use without allowing cross-owner cloud access.
