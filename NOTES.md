# NOTES.md

Design pass on the Claude Design bundle. One flagship file was built and
verified: `Career Lifespans Report.dc.html` — the report opening, Figure 1 as
full-bleed small multiples, Figure 2 (Billboard) as a carded companion. Every
decision below is expressed as a token in `tokens.css`.

Not yet done: the remaining eight preview files, and the interruption-hazard
and career-taper figures. They are next, and they inherit these decisions
rather than restating them.

## Changed

**Type is now a pairing, not one system sans.** Newsreader (serif, 300/400,
optical sizing) carries the page title, standfirst, figure titles and every
displayed numeral; IBM Plex Sans carries body copy, notes, sources, tables and
all chart text. The register the brief asked for — data journalism a
methodologist signs off on — is carried by that split: the serif does the
editorial voice, the sans does the evidence. Plex's tabular figures handle
axis ticks and table columns, so the proportional/tabular rule survives intact.

The six-step scale became a fourteen-step one. Six steps could not hold a
150px hero numeral, a 76px title, three distinct figure-title sizes and four
sizes of small print without either doubling up roles or leaving gaps. The
scale is in `tokens.css` with the role each step serves.

**Figure framing is mixed, and the frame now means something.** Figure 1 is
full-bleed: no box, opened and closed by hairline rules, breaking out past the
700px text measure to the 1180px figure width. Figure 2 is carded. The card is
no longer the default container — it marks the Billboard extension as the
narrower companion study, which is the distinction the brief asked the design
to carry. Card radius went to 0; a rounded box read as UI chrome next to a
squared full-bleed figure.

**Callouts are gone.** The three tinted boxes are replaced by a caption
ledger: a small-caps label in a 118px column, the text beside it, a hairline
above. Notes, boundaries and sources all use it, so an interpretation boundary
looks like part of the figure's apparatus rather than a warning sticker
attached to it. The boundary statement that closes the page gets the same
ledger with a 2px rule instead of a hairline — the only emphatic rule on the
page. Nothing was shortened: the credit-metadata caveat, the
confirmed-interruption caveat, and the Billboard coverage and sample-size
exclusions all appear verbatim.

**The hover layer is linked.** Hovering any of the three small multiples
brushes all three at the same age and prints one readout line above the
figure — no floating tooltip. Panels are keyboard-reachable: focus sets the
readout to age 40, arrow keys step it. The readout sits in its own reserved
row with a fixed min-height, so idle and hovered states occupy identical space
and the chart cannot shift under the cursor. The `<details>` table view stays.

**Chart annotation.** The parity rule is a 1px dotted rule with a small-caps
"PARITY" label at the right edge. The change point is a plain vertical mark
labelled "decline slows", worded so the mark cannot read as a cliff. The film
panel carries one dot at age 28, the last age at or above 50%, computed from
the series rather than hard-coded. The Billboard series stops where the
≥15-artist-year rule stops it, and the stop is labelled on the chart —
"series stops at 45 / sample cap, not the end of the data" — as well as in
the note.

## Untouched

Palette hues and slot order. Scope stays faceted; the ghost trace is the only
non-identity mark and it never becomes a hue. Every plotted value comes
straight from the bundle's embedded result tables, extracted verbatim into
`data/hwc-data.js` — no value adjusted, extended, rounded differently or
invented. Status colours remain non-series.

## Wanted, but locked

**The hero numeral is 28, not 29.** `head.parity_film` is 29 — the first age
*below* half. The composition needed the age at which parity still holds, so
the hero reads 28 with the gloss "At 29 the share is 48.9%, and it does not
reach 50% again at any later age." Both numbers are in the data and both are
stated; nothing was rounded to make it work. Worth agreeing on one name for
each, though: "parity age" currently means the crossing in the tables and the
last age at parity in the prose.

**Small multiples stayed three-up.** Stacking them would have let each panel
carry its own y labels and change-point label. Three-up won because the
shared-axis comparison is the whole point of faceting, and the brief locks
faceting. The cost is that only the leftmost panel can afford y labels and
only the film panel can afford the "decline slows" label without collision.

## For validation before adoption

No palette change is proposed. One addition needs the validator:

- **`--delta-negative: #c0472a`** — used for the "↓ 22.3 pts vs age 30" tile
  delta. `--status-serious` (`#ec835a`) does not clear text contrast at 12px
  on `--page-plane`, and the delta is text, not a mark. This is that hue
  darkened to a legible ink, not a new palette entry, but it should go through
  the contrast gate before it is treated as one. Dark-mode counterpart
  `#f08a6a` is untested.

## Open

**Dark mode is declared, not designed.** Light only was the call this round.
`tokens.css` declares the full dark scope under both the media query and
`[data-theme="dark"]`, carrying the bundle's existing validated re-steps
forward unchanged, plus new values for the tokens this pass added
(`--text-body`, `--text-standfirst`, the three hairline weights,
`--rule-emphatic`). Those five are unreviewed. The serif at 300 weight on a
dark plane will likely need 400.

**Section rhythm has three values, not one.** `--sp-lead` 88, `--sp-section`
80, `--sp-fig` 64. That is one more than the vertical rhythm probably needs;
worth collapsing to two once the remaining figures are in and the page has a
real length.

## Handoff

- `tokens.css` — the contract. `R/theme_hwc.R` and `reports/hwc.scss` should be
  re-derived from it, not hand-translated.
- `Career Lifespans Report.dc.html` — the reference implementation of the
  decisions above.
- `data/hwc-data.js` — the bundle's result-table values, extracted verbatim.
  A convenience for the preview layer; the CSVs remain the source of truth.
