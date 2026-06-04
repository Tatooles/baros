import { query } from "./_generated/server";
import { requireUser } from "./lib/auth";

export const me = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireUser(ctx);

    return {
      tokenIdentifier: identity.tokenIdentifier,
      subject: identity.subject,
      issuer: identity.issuer,
      email: identity.email ?? null,
    };
  },
});
