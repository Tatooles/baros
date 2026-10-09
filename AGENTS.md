# AGENTS.md

- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- Never open a draft pull request unless the user explicitly asks for one; otherwise, open a regular, ready-for-review pull request.
- Merging `convex/` changes to `main` deploys them to production. Before changing a public Convex function or the schema, read README → "Production deploys" for the compatibility rule with installed app builds.

## Pull requests

- UI or visual changes need before/after screenshots in the PR description. For new UI, include screenshots of the new screen or state.
- Changes to motion, timing, gestures, navigation, or other interactions need a short screen recording showing the changed behavior.
- Capture evidence from the running app after the final relevant changes. State the device or simulator and iOS version. Build and test success do not substitute for visual evidence.
- Upload PR evidence directly to GitHub and verify that it renders in the PR. Never commit PR-only screenshots or recordings, including directories such as `.github/pr-assets/`.
- If presentation-related files change without affecting visible UI or interactions, explain why in the PR description under "No visual impact."

<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

<!-- convex-ai-end -->

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `Tatooles/baros`; external PRs are not a triage surface. For issues, milestones, and linking PRs to issues, see `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Use a single-context domain docs layout. See `docs/agents/domain.md`.
