import { type AuthConfig } from "convex/server";

const clerkJwtIssuerDomain = process.env.CLERK_JWT_ISSUER_DOMAIN!;

export default {
  providers: [
    {
      type: "customJwt",
      issuer: clerkJwtIssuerDomain,
      jwks: `${clerkJwtIssuerDomain}/.well-known/jwks.json`,
      algorithm: "RS256",
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
