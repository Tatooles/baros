# Security Policy

## Supported versions

Security fixes ship in the latest Baros release on the App Store. Older app versions are not patched separately, so please update before reporting.

## Reporting a vulnerability

Please report security issues privately, not in a public issue or pull request.

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the issue, how to reproduce it, and what an attacker could do with it.

You'll get a response in the private advisory thread. Once a fix is available on the App Store, the advisory may be published with credit to you, if you'd like.

## Scope

In scope: the Baros iOS app, its Convex backend functions in `convex/`, and the support site.

Out of scope: values that ship inside the app by design, such as the Clerk publishable key, the Convex deployment URL, and the Sentry DSN. These are not secrets.
