import { type MutationCtx, type QueryCtx } from "../_generated/server";
import { syncError } from "../sync/errors";

type AuthenticatedCtx = Pick<QueryCtx | MutationCtx, "auth">;

export async function requireUser(ctx: AuthenticatedCtx) {
  const identity = await ctx.auth.getUserIdentity();

  if (identity === null) {
    throw syncError("unauthenticated", "Not authenticated");
  }

  return identity;
}

export async function requireOwnerTokenIdentifier(ctx: AuthenticatedCtx) {
  const identity = await requireUser(ctx);
  return identity.tokenIdentifier;
}
