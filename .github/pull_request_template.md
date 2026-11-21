<!--
Title: a conventional commit in plain language that says what changes for the user,
such as "fix(workout): rest timer keeps counting while the phone is locked".
A reader who stops after the opening paragraph should still know what changed and why.
Delete each comment once its section is filled. For a small risk:low or risk:medium PR, the
opening paragraph and Tests are often enough.
-->

<!-- The problem in a sentence or two, then how this fixes it. No heading. -->

<!-- One bullet per change, said as behavior a user or maintainer notices. -->
-

<!-- Closes #<n> when this finishes an issue, Refs #<n> when more PRs follow. Delete if there's no issue. -->
Closes #

## Evidence

<!--
Start with one bold line saying what the captures prove.
UI changes: before/after screenshots in a table, with the device, iOS version, and commit for each side.
Motion, timing, gestures, or navigation: a short recording.
List anything you couldn't capture under **Not shown:**.
Presentation files changed but nothing visible did: rename this section "No visual impact" and say why.
Upload to GitHub. Never commit evidence.
-->

## Tests

<!--
For a bug fix: how it reproduces on main, then the test that fails without the fix and passes with it.
Then the commands you ran and their results, starting with scripts/check-changed.sh.
For a risk:high PR, add the proof AGENTS.md → "PR risk" lists for each area the PR comment names.
-->

## Not in this change

<!-- Known gaps, review suggestions you declined and why, and follow-up issues. Delete if none. -->

<!-- Review summary, if your workflow adds one. Then the model and harness that did the work. -->
