# AGENTS.md

- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- Never open a draft pull request unless the user explicitly asks for one; otherwise, open a regular, ready-for-review pull request.
- Merging `convex/` changes to `main` deploys them to production. Before changing a public Convex function or the schema, read README → "Production deploys" for the compatibility rule with installed app builds.

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
