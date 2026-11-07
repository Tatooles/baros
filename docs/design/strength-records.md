# Strength records in Exercise History

Issue: [#175](https://github.com/Tatooles/baros/issues/175)

Status: design approved on 2026-09-06, including the calculation and comparison rules, informational Records card, and inline gold source-set badges. The final visual review confirmed “Heaviest Rep” naming and badge placement immediately to the left of the weight and reps. Ready for implementation when requested.

> **2026-11 redesign.** The calculation, equipment, tie-breaking, and lifecycle
> rules below still apply unchanged. The presentation was reworked after a
> design council review; see [Revised presentation](#revised-presentation-2026-11),
> which supersedes "Presentation elaboration", "Source set badges", and
> "Information text" where they conflict.

## Outcome and scope

Exercise History should show the heaviest weight actually recorded and the best estimated one-repetition maximum, with enough source context to understand each. Add one restrained Records card below the exercise heading and above the existing workout cards.

The first version contains current all-time records only. Charts, trends, record history, celebrations, notifications, formula settings, coaching, and persisted calculated records are outside this issue.

## Accepted calculation contract

Both records use the current owner's visible, finished, nondeleted workouts and their nondeleted exercise occurrences and completed sets. Reuse Exercise History's existing identity resolution and visibility rules. A completed checkbox alone does not qualify a set: weight must be valid, finite, and positive, and reps must be valid and positive under the existing input policy.

| Record | Eligible set kinds | Reps | Value |
| --- | --- | --- | --- |
| Heaviest Rep | Working, warmup, drop, failure | Any valid positive count | Recorded weight |
| Estimated 1RM | Working, failure | 1–10 | Recorded weight for one rep; Epley `weight × (1 + reps / 30)` for 2–10 reps |

RPE is neither required nor used to adjust the estimate. Select the largest eligible result independently for each record. An estimate can be lower than Heaviest Rep when the heavier set is ineligible for estimation; do not increase or fabricate the estimate to conceal this distinction.

Calculations and comparisons use canonical stored weight before display conversion or rounding. Display the current weight preference using existing formatting. Changing units must not change the winning source set. Do not infer body mass, assistance, per-hand multipliers, machine ratios, or total load from a name or equipment tag.

## Accepted equipment boundary

First match the existing resolved exercise identity. Within that identity, only occurrences whose historical equipment matches the equipment shown in the Exercise History heading can contribute records. Bodyweight and resistance-band occurrences do not contribute either record in this version.

Equipment means the resolved historical equipment used by the existing history presentation, not a substitution from today's exercise library. The heading currently represents the resolved history summary, which may differ from current library metadata. The same exercise ID can contain different historical equipment; records must not combine those equipment groups. Renaming alone does not split an existing linked exercise identity, and name similarity must not merge otherwise distinct identities.

Keep the full chronological history visible. If it contains equipment different from the record scope, show a short scope caption, such as “Barbell records,” so the smaller comparison set is understandable.

## Presentation elaboration

Use the existing card treatment and typography. Place “Records” and an accessible information button in the card header. Following the 2026-09-07 refinement, use a quiet gold uppercase section label, a subtle one-point gold border, and two equal-width record columns separated by generous space. Align labels and values at the top; put weight/reps, set/date, and workout title on separate lines. Fall back to vertically stacked records with a divider at accessibility text sizes or when the columns cannot fit, allowing long source titles to wrap. Following visual review, the record rows have no tap action or disclosure chevron. Show the record sources directly in the history below using set badges.

Illustrative content, not real user data:

```text
Records                                   ⓘ

Heaviest Rep
225 lb
225 lb × 1 rep · Set 3
Upper Body · Sep 4, 2026
───────────────────────────────────────────
Estimated 1RM
≈ 245 lb
210 lb × 5 reps · Set 2
Upper Body · Sep 2, 2026
```

Show the source set's original history set number, including gaps left by incomplete sets, and the source workout's displayed date. The history below preserves its existing exercise occurrence groups. Both record rows remain visible when they share a source workout or set.

Use the approximate marker for Estimated 1RM, including when its winning source is a single. The information view explains that a single contributes its recorded load unchanged. Accessible labels should speak the metric, value and unit, source weight and reps, workout, and date; label the info button “About strength records.”

### Source set badges

Mark the actual winning set rows in the existing Exercise History workout cards. Place a small, noninteractive gold “Heaviest rep” or “Est. 1RM” badge inline, immediately to the left of the set's weight and reps. Use legible gold surfaces and contrasting text in both appearances. If one set holds both records, show both badges in the area to the left of the value; that badge group may wrap when needed without truncating labels or the weight and reps. The summary and information sheet also use “Heaviest Rep.” This naming change preserves the agreed maximum-load calculation; it does not require a one-rep set.

Badges mark the exact sources of the two current all-time records at the top. They do not mark every past personal record or every tied set. Use the same winning set identities and equipment scope as the summary; edits, deletion, completion changes, or a new winner update both presentations together. No badge appears for an unavailable record or excluded equipment. VoiceOver should include the full record name when reading the set.

Existing workout-header navigation is outside this change; no new record-specific destination, jump-to-set interaction, or tap behavior is introduced.

## Information text

Present a small native sheet titled “About strength records” with a Done action and these short explanations:

- **Heaviest Rep:** “Your heaviest recorded weight for at least one completed rep in a finished workout. Includes warmup, working, drop, and failure sets.”
- **Estimated 1RM:** “An estimate from completed working and failure sets of 1–10 reps. For 2–10 reps, we use the Epley formula: weight × (1 + reps ÷ 30). A single rep uses its recorded weight. The estimate does not account for effort.”
- **Comparison:** “Records use matching equipment. Bodyweight and resistance-band exercises are not included. Weight means the load you recorded.”
- **Source badges and updates:** “Badges mark the sets behind your current records. One set can hold both. For equal records, the most recent workout is shown. Records and badges update when your saved workouts change.”

Do not present the value as a recommended training load or a measurement of current ability.

## Sparse history and lifecycle elaboration

| Situation | Presentation or behavior |
| --- | --- |
| One eligible set | Show whichever records it qualifies for; no minimum workout count. |
| Heaviest Rep exists, but no estimation candidate | Keep the second row, without navigation or a numeric zero: “No estimate yet” and “Requires a completed working or failure set of 1–10 reps with weight.” |
| Neither record has a candidate, but matching equipment is supported | Show one compact message: “No records yet” and “Requires a completed set with weight and reps in a finished workout.” |
| Bodyweight or resistance-band heading | Omit the Records card; keep existing history available. |
| Missing or unrecognized heading equipment | Omit the Records card until the comparison scope can be resolved; do not guess an equipment class. |
| Missing or unrecognized occurrence equipment | Exclude that occurrence from the records. |
| Exact tie before display rounding | Use the most recent source workout by its displayed `startedAt` date. Within a tied workout, prefer lower exercise order, then lower set order; use stable IDs as a final deterministic fallback. |
| Different underlying values round to the same display | Preserve the actual larger result as the winner. |
| A record source is edited, deleted, or uncompleted | Recalculate from eligible saved history and select the next winner, or show the appropriate empty state. |
| One set holds both records | Show both record badges on that exact set; keep both summary rows. |
| Weight preference or Current Owner changes | Refresh the display and eligible history under existing visibility rules. |

Do not retain a deleted record as a historical achievement. Derive records from the full matching history, not only a recent-workout preview or visible scroll region. Avoid a new persistence, migration, or sync contract.

## Revised presentation (2026-11)

The first version answered "what are my two highest numbers?" but not "how is
my lifting going?", and it asked people to match set numbers and dates by hand.
The revision keeps the calculation and changes how the screen tells the story.

- **Records surface.** One full-width card below the heading, with
  "Records" and the information button as its section header. When the history
  mixes equipment, the header adds a caption such as "Barbell sets only".
- **Heaviest Rep leads.** It is a recorded lift, so it is the largest number on
  the screen. Its source line reads `reps · date · workout`, with the year only
  outside the current year.
- **Estimated 1RM follows, deliberately smaller.** It keeps the `≈` marker and
  rounds to a whole pound or half kilogram after the winner is chosen, so it
  never reads more exact than the inference behind it. Its source reads
  `From weight × reps · date · workout`, or "From the same set" when one set
  holds both records. The card ends with "Estimates come from logged sets and
  don't account for effort."
- **Records reveal their source.** Each record row is a button. Tapping it
  scrolls the source workout into view in the log below, washes that row with
  `brandAccentMuted` for about 1.6 seconds, and moves VoiceOver focus to it.
  Scrolling is not animated with Reduce Motion. This replaces the original "no
  tap action" rule; there is still no separate record destination.
- **Progression chart.** With at least three workouts that have an eligible
  estimate, the card shows "Estimated 1RM by workout": the best eligible
  estimate from each workout as points joined by a line, on a real date axis.
  There is no trend line, smoothing, projection, or "now" label. The current
  record point is larger and a "Record" legend names it. Dragging selects a
  workout and shows `date · ≈ value from weight × reps`. VoiceOver reads a
  summary and exposes an audio graph.
- **No estimate / no records.** "No estimate yet — Needs a completed set of 1–10
  reps with weight." and "No records yet — Log a weight and reps on a completed
  set to see records here." No zeros, no extra explanation in the card; the
  information sheet holds the full rules.
- **Exercise History log.** Each Exercise Performance is one row in a single
  grouped list: the History date tile, workout title and set count as the
  button that opens the workout, then every completed set across the full row
  width. Occurrence boundaries, other-equipment identity labels, and exercise
  notes are preserved.
- **Set boxes.** Each completed set is a one-line `recessedSurface` box that
  fits its content: `weight × reps`, then `@RPE` only when logged. No box
  reserves space for a missing RPE or has a fixed width, so no box shows empty
  space inside it. At accessibility sizes each set takes its own line.
- **Source markers.** The source set's box adds a faint neutral outline and a
  small trophy; the box itself carries no record name. The workout's subtitle
  names the record after the set count (`3 sets · 🏆 Est. 1RM`). If one set
  holds both records, the subtitle names both, joined by "·". If different
  sets in one workout hold them, each name carries its value
  (`Heaviest rep 235 × 1 · Est. 1RM 210 × 6`). At accessibility sizes the
  record name takes its own line. Markers are neutral, not cobalt or gold:
  they are informational, not interactive. The workout row's VoiceOver label
  ends with "holds … record", and each set still speaks its record names.
- **Quick History.** The active workout's Quick History uses the same rows for
  the last three workouts, with record sets marked from the full history. It
  shows no Records card, and its summary matches the Exercise History heading.
- **Information sheet.** Opens at a medium detent. It leads with "Records
  describe sets you've saved. They aren't a measure of what you can lift
  today.", explains both records, notes that warmup and drop sets don't count
  toward the estimate, and says that tapping a record shows its set.
- **Accessibility.** Numbers never wrap between digits: the unit moves to its
  own line first, then the number scales down. At accessibility sizes the row's
  trailing arrow becomes a "Show set" label below the source. Record labels
  speak "about" for the estimate and full unit names.

## Implementation verification targets

When implementation is authorized, verify calculation boundaries (one, ten, and eleven reps), each set kind, invalid/missing/zero values, and the independent winners. Cover equipment changes under one exercise ID, ambiguous snapshot identities, owner isolation, exact ties, unit changes, and record-source edits/deletions. Confirm presentation with sparse history, long workout names, larger accessibility text, two badges on one set, and exact agreement between summary sources and badge placement. Verify record rows are informational and existing workout-header navigation still works. Keep simulator and physical-device evidence separate.

## Evidence and implementation entry points

- `Baros/Features/History/ExerciseHistoryDetailView.swift`: insertion point, current unit setting, and existing workout navigation.
- `Baros/Features/History/ExerciseHistorySummary.swift`: conservative identity resolution and heading metadata.
- `Baros/Features/History/ExerciseHistorySessionGroup.swift`: eligible visible workout groups and occurrence/set context.
- `Baros/Features/History/ExerciseHistoryPerformanceRow.swift`: log rows, set boxes, and source markers, shared with Quick History.
- `Baros/Core/Models/LoggedSet.swift`, `Baros/Core/Domain/WorkoutNumericInputPolicy.swift`, and `Baros/Core/Domain/MeasurementUnit.swift`: stored values, numeric validation, and unit conversion.

The selected ten-rep cap is a product boundary, not a guarantee of accuracy across exercises. [Reynolds, Gordon, and Robergs (2006)](https://www.unm.edu/~rrobergs/478RMStrengthPrediction.pdf) studied chest press and leg press, found better prediction from lower-repetition tests, and recommended no more than ten repetitions for linear prediction in those exercises. Their tests used repetition maximum effort; ordinary logged sets need the effort limitation stated above.

No ADR is needed: these derived calculations and presentation choices remain inexpensive to revise and do not introduce a new durable data contract.
