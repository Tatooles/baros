import { ConvexError } from "convex/values";

// Stable codes on every error a sync mutation throws on purpose, so a client
// can tell a record the server will never accept from a failure that may pass.
// Installed builds treat every server error alike, so codes change nothing
// for them.
export type SyncErrorCode =
  // The caller has no valid identity. Account-wide; retry after sign-in.
  | "unauthenticated"
  // The account is being deleted. Account-wide; writes resume if it is cancelled.
  | "accountDeletionInProgress"
  // The record's workout or logged exercise has not been uploaded yet.
  | "missingParent"
  // The logged exercise names an exercise the server has never received.
  | "missingExerciseReference"
  // The upload itself is invalid and never will be accepted as sent.
  | "invalidPayload";

export function syncError(code: SyncErrorCode, message: string): ConvexError<{ code: SyncErrorCode; message: string }> {
  return new ConvexError({ code, message });
}
