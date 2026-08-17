# Design system — publishable outputs

Visual layer for *Women's Career Lifespans in U.S. Entertainment*. Register:
data journalism. The figure title carries the finding, the subtitle carries the
denominator, the note carries what the measure cannot show.

**`tokens.css` is the contract.** It came back from a Claude Design pass and is
the single source of truth. `R/theme_hwc.R` and `reports/hwc.scss` are
*generated* from it — do not edit either by hand.

```
python3 design-system/build/embed_fonts.py        # vendor + inline the webfonts
python3 design-system/build/derive_from_tokens.py # -> R/theme_hwc.R, reports/hwc.scss
python3 design-system/build/gen.py                # -> design-system/*.html
python3 design-system/build/social.py             # -> social/*.html
node    design-system/build/shoot.mjs             # render + audit previews
node    design-system/build/shoot-social.mjs      # render + audit social cards
```

Change a token, run those, and the whole system moves together.

## What is here

| Path | What it is |
|---|---|
| `tokens.css` | **The contract.** Every colour, size, weight and geometry value. |
| `NOTES.md` | Claude Design's rationale, and what it flagged as open. |
| `R/theme_hwc.R` | *Generated.* ggplot2 theme, scales, annotation helpers, save sizes. |
| `reports/hwc.scss` | *Generated.* Quarto theme layer, with the fonts inlined. |
| `fonts/` | Self-hosted woff2 + their OFL licenses. |
| `design-system/` | Ten HTML previews. |
| `social/` | 1200×1200 cards. |

## Wiring it in

**Figures.** Two lines at the top of any plotting script (`05`, `07`, `13`):

```r
source("R/theme_hwc.R")
ggplot2::theme_set(theme_hwc()); hwc_set_geom_defaults()
```

Then swap the hand-rolled colour vectors for `scale_colour_hwc()`, and `ggsave()`
for `hwc_save(p, path, "wide")`.

**Report.** One line in `_quarto.yml`:

```yaml
format:
  html:
    theme: [cosmo, hwc.scss]
```

## The type pairing

The system is now **two families**, not one:

- **Newsreader** (serif) — page title, standfirst, headings, figure titles, and
  every *displayed* numeral (hero figure, stat-tile values).
- **IBM Plex Sans** — body copy, notes, sources, tables, and **all chart text**,
  with tabular figures on axis ticks and table columns.

Chart text is never serif. That split is the point: the serif does the editorial
voice, the sans does the evidence.

**Only five weights exist as faces** — Newsreader 300/400/500/600, Plex
400/500/600. Any other weight gets synthesised by the browser into a faux bold,
so every rule is written against a `--fw-*` token rather than a number. The
render audit fails the build if it finds a synthesised weight, including the
`700` that `<strong>` and `<th>` default to.

**The fonts are self-hosted, not linked.** `tokens.css` names a Google Fonts URL
in its header comment, but a remote `@import` would make `quarto render` depend
on network access and would defeat `embed-resources: true`. So they are vendored
from npm (`@fontsource/*`) and inlined as base64 woff2 in both the SCSS and the
previews. Both families are SIL OFL; the licenses ship in `fonts/` as that
license requires.

**R figures need the fonts installed locally** — inlining only helps the browser.
Install Newsreader and IBM Plex Sans from fonts.google.com, plus the `systemfonts`
and `ragg` R packages. `theme_hwc()` warns once per session if a family is
missing rather than silently falling back, and `hwc_save()` uses ragg when it is
available, which is the only reliable way to get a named family onto a PNG on
Windows.

## The rules that are not cosmetic

**Blue is always women-coded, orange always men-coded.** Fixed slot order, every
figure, regardless of which series is larger. Validated for colour-vision
deficiency, lightness band, chroma floor and surface contrast in both modes —
worst adjacent CVD ΔE 24.7 light / 26.8 dark against a target of 8. The
generator **hard-fails** if either hue changes in `tokens.css`, because a silent
change there would invalidate that validation.

Blue↔orange was chosen over blue↔pink to avoid encoding gender with the
stereotyped hue the study measures.

**Scope never gets a hue.** Film / television / overall is faceted into small
multiples with a shared axis and a ghost trace.

**The card means something.** Full-bleed is the default figure treatment: the
figure breaks the 700px text measure out to 1180px, opened and closed by hairline
rules. The card is reserved for the Billboard companion — it marks the narrower
companion study. Use `::: {.companion}` to get it. Card radius is 0; a rounded
box read as UI chrome beside a squared full-bleed figure.

**Callouts are a caption ledger, not tinted boxes.** A small-caps label in a
118px column, the text beside it, a hairline above — so an interpretation
boundary reads as part of the figure's apparatus rather than a warning sticker.
`.definition` → "How to read", `.boundary` → "Boundary", `.caution-note` →
"Coverage", `figcaption` → "Note". `.boundary.closing` gets the one 2px rule on
the page.

**Direct labels go where series separate, not where they end.** Hazard and taper
curves converge at the right edge; `hwc_direct_label()` places at the point of
widest separation.

**Say what was dropped.** `hwc_sample_cap()` labels a capped series end on the
chart itself, so a stop never reads as the end of the data.

## The two parity ages

`NOTES.md` flagged that "parity age" was being used for two different numbers.
Resolved, with `hwc_parity_ages()` returning both:

- **`last_at_parity` = 28** — the last age at which women hold ≥50%. Film 50.8%,
  all titles 50.6%. **This is the hero numeral.**
- **`crossing` = 29** — the first age below 50%, and it never returns. Film
  48.9%, all titles 49.1%.

Both are true; use the names, not "parity age".

## Adopted from the Claude Design pass

`--delta-negative: #c0472a` (light) / `#f08a6a` (dark) was flagged for
validation and **passes**: 4.77:1 on the page plane, 4.90:1 on the surface,
7.91:1 dark. Claude Design's diagnosis was right — `--status-serious` measures
2.50:1 and genuinely fails as text. It is text-only and never a mark.

## Still open

- **Dark mode is declared, not designed.** `tokens.css` carries a full dark
  scope, and the previews validate in it, but the five tokens this pass added
  (`--text-body`, `--text-standfirst`, the three hairline weights,
  `--rule-emphatic`) are unreviewed. The serif at weight 300 on a dark plane will
  likely need 400. `reports/hwc.scss` emits light values only.
- **The previews carry the new tokens but not the new composition.** They pick up
  the palette, the type pairing and the mark weights automatically, because
  `build/lib.py` reads `tokens.css`. They were *not* restructured into
  full-bleed, the caption ledger, or the linked hover layer — Claude Design's
  reference implementation (`Career Lifespans Report.dc.html`) and
  `data/hwc-data.js` were never written to the project, so there was nothing to
  port from. Retrieve that file from Claude Design if you want the composition.
- **Section rhythm has three values** (`--sp-lead` 88, `--sp-section` 80,
  `--sp-fig` 64). Probably one too many; worth collapsing once the page has real
  length.
- **`tokens.css` sits at the repo root**, though its own header suggests
  `design-system/tokens.css`. Left at the root so there is exactly one copy; the
  generators read it from there.

## Corrections carried forward from the data

Building against the real result tables surfaced four things the figures must
respect:

1. **The change point is where the decline slows**, not a cliff. Film 42,
   television 44, overall 43; the post-change slope is roughly a quarter of the
   pre-change slope. `hwc_change_point()` defaults its caption to "decline slows".
2. **The taper gap closes, then reverses.** Median taper favours men from the
   late 30s (widest at 40, 8.7 points) but the curves cross after 60, and on
   severe taper men overtake after about 65.
3. **The Billboard tail is noise.** Past 54 the classified sample falls under 15
   artist-years per group and return rates swing between 0% and 100%. Excluded
   from chart *and* table, with the exclusion named.
4. **The five-year return CIs overlap at every band.** The post-40 divergence is
   suggestive, not established.

## Sizes

`hwc_save(p, path, variant)` — derived from the token figure widths, so an R
figure displayed at `--figure-max` renders one design pixel per design pixel:

| variant | inches | use |
|---|---|---|
| `wide` | 11.8 × 6.25 | full-bleed report figures |
| `half` | 5.78 × 4.51 | side-by-side pairs |
| `square` | 12 × 12 | social |
| `story` | 10.8 × 13.5 | vertical social |

All at 200 dpi on the page plane.
