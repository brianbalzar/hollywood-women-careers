# Brief for Claude Design

**Project:** *Women's Career Lifespans in U.S. Entertainment* — a reproducible
study of how screen-acting and Hot 100 charting opportunity change with age, and
whether the age pattern differs by gender-coded credit class.

**Register:** data journalism. The figure title carries the finding, the subtitle
carries the denominator, and the note carries what the measure cannot show. It
should read like a Pudding or Upshot piece that a methodologist would still sign
off on.

**Your job:** make these ten previews publishable. Push the typography,
composition, hierarchy and figure framing as far as you can — then hand back the
refined previews *and* a single tokens file so the R and SCSS layers can be
mechanically re-derived from your decisions.

---

## What is in the bundle

Ten self-contained HTML files. Each inlines its own CSS and JS, embeds the real
result-table values it plots, and carries a first-line `@dsCard` marker.

```
foundations/color.html           the two-hue palette and its validation record
foundations/type.html            six-step scale, numeral rules
foundations/chart-anatomy.html   mark specs, label rules, the four attachments
charts/opportunity-share.html    small multiples — the report's spine chart
charts/interruption-hazard.html  two-series levels + single-series ratio with CI
charts/billboard.html            share line, dumbbell with CIs, quantile boxes
components/stat-tiles.html       hero figure + four stat tiles
components/data-table.html       the table treatment
components/callouts.html         definition / boundary / caution variants
```

Open any one in a browser. No build step, no server, no network.

---

## Locked — please do not change these

These are not stylistic preferences. Each one is load-bearing.

**1. The palette pairing and slot order.** Blue `#2a78d6` is always women-coded;
orange `#eb6834` is always men-coded, in every figure, regardless of which series
is larger at a given age. The pair was validated for colour-vision deficiency,
lightness band, chroma floor and surface contrast in both light and dark modes
(worst adjacent CVD ΔE 24.7 light / 26.8 dark, against a target of 8). It was
chosen over the conventional blue↔pink specifically to avoid encoding gender with
the stereotyped hue the study is measuring.

If you want to propose different hues, that is welcome — but return them as a
*candidate set* flagged in `NOTES.md` rather than applied, so they can be re-run
through the validator before adoption. Anything applied silently has to be
reverted.

**2. Scope is faceted, never coloured.** Film / television / overall appear as
small multiples with a shared axis and a grey ghost trace. They must never become
a third and fourth categorical hue — that would make blue mean two different
things across the report.

**3. Every number.** All values are real, drawn from the project's result tables,
and verified against source CSVs. Do not adjust a value, extend a series, round
differently, or invent a data point to make a composition work. If a chart is
awkward because the data is awkward, change the composition.

**4. The notes and sources.** Every figure carries an interpretation boundary and
a source line. They can be restyled, repositioned, or made more elegant — they
cannot be shortened into uselessness or dropped. Specifically these must survive:
the women-coded/men-coded metadata caveat, the "confirmed interruption, not
retirement" caveat, and the Billboard coverage and sample-size exclusions.

**5. Sample-size caps stay visible.** Where a chart drops data (Billboard bands
under 15 artist-years, the share line stopping at 45), the caption names the cap
and the reason. Silent truncation reads as "we covered everything."

**6. The four attachments.** Each chart ships with a hover layer, a table view, a
note, and a source. The table view exists so no value is reachable only through a
tooltip — please keep it, and keep it keyboard-reachable.

---

## Open — please push hard here

- **Typography.** The six-step scale is serviceable, not designed. Rhythm,
  weights, optical sizes, the relationship between figure title and subtitle,
  and the treatment of the kicker are all yours.
- **Figure framing.** The card is a 10px-radius hairline box on a warm off-white.
  It is a default, not a decision. Consider full-bleed figures, rules instead of
  boxes, a stronger kicker system, or letting the chart breathe out of the text
  measure.
- **Composition and hierarchy.** Which figure leads. How the hero number relates
  to the charts around it. Whether the small multiples want to be three-up,
  stacked, or something else entirely.
- **The callouts.** Three variants that currently look like tinted boxes. The
  interpretation boundaries are central to this project's credibility — they
  deserve a treatment that reads as integral rather than as a warning label.
- **The table treatment.** It is quiet and correct and slightly lifeless.
- **Dark mode.** Both modes are selected rather than flipped, but the dark mode
  has had far less attention than the light one.
- **Chart annotation.** Change-point marks, parity rules and direct labels are
  functional. They could be considerably more expressive without becoming loud.

---

## What to hand back

**1. The ten refined preview files**, same paths, still self-contained, still
carrying their `@dsCard` first-line markers.

**2. `tokens.css`** — a single file at the bundle root defining every design
decision as CSS custom properties, in exactly this shape, with both modes
declared under both the media query and the `[data-theme="dark"]` scope:

```css
.viz-root {
  /* surfaces */   --surface-1: …;  --page-plane: …;
  /* ink */        --text-primary: …; --text-secondary: …; --text-muted: …;
  /* chrome */     --gridline: …; --baseline: …; --hairline: …;
  /* series */     --series-1: …; --series-2: …; --series-ghost: …;
  /* sequential */ --seq-100 … --seq-700;
  /* status */     --status-good: …; --status-warning: …;
                   --status-serious: …; --status-critical: …;
  /* type */       --font-sans: …; --fs-hero … --fs-micro; --lh-body: …;
  /* space */      --sp-1 … --sp-8; --measure: …;
}
```

Every token that appears in the previews must appear here, and nothing in the
previews should use a raw hex or a magic pixel value that is not in this file.
This is the contract that lets `R/theme_hwc.R` and `reports/hwc.scss` be
regenerated from your work instead of hand-translated.

**3. `NOTES.md`** — short. What you changed and why; anything you wanted to change
but could not without touching a locked item; any candidate palette or type
proposals for validation.

---

## Context worth having

The underlying findings, so the emphasis lands in the right place:

- Women-coded performers hold half of U.S.-market principal screen roles at 28,
  and never hold half again. By 50 they hold about a quarter of film roles.
- The estimated change points (film 42, television 44) are where the decline
  **slows**, not where it starts. Do not let a composition imply a cliff at 42.
- The Billboard extension is a parallel case in a different industry, deliberately
  narrower in scope. It should feel like a companion, not a second study.

The project's own framing is worth reading if you want it: it can quantify an
observed opportunity gap and test when it appears; it cannot identify audition
pools, offers, availability, voluntary retirement, or caregiving constraints, and
it does not claim to. The design should carry that restraint without being timid.
