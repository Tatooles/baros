<!--
Title: a conventional commit in plain language that says what changes for the user,
such as "fix(workout): rest timer keeps counting while the phone is locked".
Fill every section; delete a section's comment once it's filled. A reader who stops
after the opening paragraph should still know what changed and why.
-->

<!-- The problem in a sentence or two, then how this fixes it. No heading. -->

<!-- One bullet per change, said as behavior a user or maintainer notices. -->
-

Fixes #

## Evidence

<!--
Start with one bold line saying what the captures prove.
UI changes: before/after screenshots in a table, with the device, iOS version, and commit for each side.
Motion, timing, gestures, or navigation: a short recording.
List anything you couldn't capture under **Not shown:**.
No visible change: rename this section "No visual impact" and say why.
Upload to GitHub. Never commit evidence.
-->

## Tests

<!--
The commands you ran and their results, starting with scripts/check-changed.sh.
For a bug fix: the test that fails without the fix and passes with it.
size:XL and up: link the full UI suite run (AGENTS.md → "PR size").
-->

## Not in this change

<!-- Known gaps, review suggestions you declined and why, and follow-up issues. Delete if none. -->

<!-- Council review table, if there was one. Then: Created with <model> in <harness>. -->
