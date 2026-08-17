# Women's Career Lifespans in U.S. Entertainment

**[Read the report →](https://brianbalzar.github.io/hollywood-women-careers/)**

How screen-acting opportunity changes with performer age, and whether the age
pattern differs between women-coded and men-coded IMDb credits in American film
and scripted television — with a parallel analysis of Billboard Hot 100 solo
artists.

The project separates three questions that are usually collapsed into one:

1. Do substantial screen credits become less frequent with age?
2. Does that contraction happen earlier or faster for women-coded performers?
3. Do the prominence and content of the remaining roles narrow with age?

It defines a **confirmed five-year career interruption** separately from a
permanent exit: a performer may later return after the observed gap.

---

## What the analysis finds

- Women-coded performers hold roughly half of U.S.-market principal screen roles
  at **age 28**, and never hold half again. By 50 they hold about **a quarter of
  film roles** and **30% of television roles**.
- The estimated change point in the log-odds slope is **age 42 in film** (95%
  bootstrap CI 41–44) and **44 in television**. This is where the decline
  *slows*, not where it begins — the steep fall runs through the 30s, and the
  post-change slope is roughly a quarter of the pre-change slope. There is no
  cliff at 35.
- At age 30, an established women-coded career is **1.28×** as likely as a
  comparable men-coded career to be in its last year before a five-year
  interruption (95% CI 1.22–1.34). The two hazards converge again after 40.
- Among performers who *keep* working, median remaining workload as a share of
  their own peak favours men from the late 30s, widest at **age 40** (8.7
  points). The two curves cross after 60.
- On the Hot 100, women-coded artists' share of classified solo chart
  participation falls below parity at **age 21** — roughly a decade earlier than
  on screen.

Every figure in the report carries the interpretation boundary that goes with
it. See [What this cannot show](#what-this-cannot-show).

---

## Reproducing it

Requires R (≥ 4.2) and [Quarto](https://quarto.org). Source data downloads are
intentionally opt-in and are **not** included in this repository.

```r
source("scripts/00_check_environment.R")
source("scripts/01_download_imdb.R")     # opt-in download, large
source("scripts/02_run_feasibility.R")   # synthetic pipeline validation
source("scripts/03_build_real_credits.R")
source("scripts/04_build_opportunity_panel.R")
source("scripts/05_descriptive_analysis.R")
source("scripts/06_build_career_spells.R")
source("scripts/07_fit_models.R")
source("scripts/08_sensitivity_analysis.R")
source("scripts/09_character_label_exploration.R")
source("scripts/10_validate_analysis.R")
source("scripts/11_download_billboard.R") # opt-in download
source("scripts/12_match_billboard_artists.R")
source("scripts/13_billboard_age_analysis.R")
```

Then render:

```
quarto render reports/index.qmd
```

`scripts/10_validate_analysis.R` writes `outputs/tables/validation_checks.csv`,
which asserts that the analytic tables exist, that ages and chronology are
valid, that all 17 result tables were written, and that bootstrap intervals are
well formed. Run it before trusting any output.

### Data storage

IMDb files are large and are cached outside the repository. Set
`HOLLYWOOD_CAREERS_CACHE` to choose a location; if the configured path cannot be
created, the code falls back to `data/raw` and reports that choice. **Source
data are never modified in place, and never committed.**

The fitted survival model (`outputs/models/career_exit_model.rds`, ~38 MB) is
also excluded from version control. It regenerates from
`scripts/07_fit_models.R`.

### Data sources and credit

- Screen records come from the
  [IMDb Non-Commercial Datasets](https://developer.imdb.com/non-commercial-datasets/).
- Weekly Hot 100 history comes from the maintained
  [`mhollingshead/billboard-hot-100`](https://github.com/mhollingshead/billboard-hot-100)
  archive of [Billboard Hot 100](https://www.billboard.com/charts/hot-100/) records.
- Solo-artist birth date, gender label, and MusicBrainz artist identifier are
  queried through the [Wikidata Query Service](https://query.wikidata.org/).

The August 17, 2026 source snapshots are documented in `data/raw/*_manifest.csv`.
Upstream source rows are not redistributed; see [`LICENSE-CONTENT.md`](LICENSE-CONTENT.md)
for attribution, reuse boundaries, and licensing notes.

---

## Repository layout

```
R/                  helpers, path resolution, and the figure design system
scripts/            the numbered, ordered pipeline
reports/            index.qmd — the report source — plus its SCSS theme
outputs/tables/     aggregate result tables (CC BY 4.0)
outputs/figures/    rendered figures (CC BY 4.0)
social/             1200x1200 social cards
design-system/      self-contained HTML design-system previews
tests/              testthat unit tests for the IMDb helpers
```

Design decisions for the figures and the report — the validated palette, the
faceting rule, the annotation conventions — are documented in
[`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md).

The full methodology, including estimands, scope, classification thresholds and
the planned character-content phase, is in
[`RESEARCH_PROTOCOL.md`](RESEARCH_PROTOCOL.md).

---

## What this cannot show

Public credits measure **observed opportunity**. They do not reveal who was
available, who auditioned, who declined a role, who retired, or who was offered
work and turned it down. The results describe an opportunity gap; they do not by
themselves identify its cause or establish discriminatory intent.

"Women-coded" and "men-coded" are predominant IMDb credit-metadata classes, not
self-identified gender. A performer is classified only when at least 90% of
their classified principal credits fall in one IMDb category; everyone else is
reported as ambiguous and excluded from binary comparisons.

A five-year interruption is **not** necessarily permanent — a performer can
later return.

The Billboard extension is deliberately narrower: it covers identifiable solo
artists with birth-year and gender metadata, which is 49.8% of chart rows. Bands,
unresolved collaborations and ambiguous names are excluded rather than assigned
a gender. Chart presence measures commercial visibility, not recording
employment, artistic output, or touring.

Causal attribution would require casting, audition, union-employment or earnings
data. None of that is public.

---

## License

Code is MIT. Report text, figures and derived tables are CC BY 4.0. No IMDb or
Billboard source records are redistributed. See
[`LICENSE-CONTENT.md`](LICENSE-CONTENT.md) for the full breakdown and the
upstream data terms.

## Citation

See [`CITATION.cff`](CITATION.cff), or:

> Balzar, B. (2026). *Women's Career Lifespans in U.S. Entertainment.*
> https://github.com/brianbalzar/hollywood-women-careers
