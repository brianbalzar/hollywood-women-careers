# Licenses

This repository is dual-licensed, because it contains two different kinds of
work.

## Code — MIT

Everything in `R/`, `scripts/`, `tests/`, and `design-system/build/`, plus the
`.scss` and `.qmd` source files, is released under the MIT License. See
[`LICENSE`](LICENSE).

## Written content, figures and derived tables — CC BY 4.0

The report text (`reports/index.qmd` and its rendered output), the research
protocol, the figures in `outputs/figures/`, the aggregate result tables in
`outputs/tables/`, the social cards in `social/`, and the design-system
documentation are released under the
[Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/).

You are free to share and adapt this material, including commercially, provided
you give appropriate credit, link to the license, and indicate if changes were
made.

**Suggested attribution:**

> Balzar, B. (2026). *Women's Career Lifespans in U.S. Entertainment.*
> Licensed under CC BY 4.0.

## Bundled fonts — SIL Open Font License 1.1

`fonts/` contains woff2 subsets of two open-source families, vendored so the
report renders without a network round-trip:

- **Newsreader** — Copyright 2020 The Newsreader Project Authors.
  See `fonts/LICENSE-Newsreader.txt`.
- **IBM Plex Sans** — Copyright 2017 IBM Corp.
  See `fonts/LICENSE-IBM-Plex-Sans.txt`.

Both are licensed under the SIL Open Font License, Version 1.1, which permits
redistribution provided the license travels with the font files. Those license
files are included as that requires. The OFL covers the fonts only; it does not
extend to this project's code or content.

## Source data — not covered by either license

**No IMDb or Billboard source records are redistributed with this project.**

- **IMDb.** The analysis reads IMDb's non-commercial datasets, which are
  governed by [IMDb's own terms](https://developer.imdb.com/non-commercial-datasets/)
  and are **not** included here. `scripts/01_download_imdb.R` fetches them to a
  local cache outside the repository. The files in `data/raw/*_manifest.csv`
  record which dataset versions a given run used; they contain checksums and
  sizes, not data.
- **Billboard.** Chart data is retrieved by `scripts/11_download_billboard.R`
  from the `mhollingshead/billboard-hot-100` archive. Solo artists are matched
  to human records in Wikidata that include a MusicBrainz artist identifier;
  birth date and gender labels come from Wikidata, not a MusicBrainz API query.
  Chart rankings are a factual record, but Billboard asserts rights over its
  charts; no chart data is redistributed here either.

The aggregate tables in `outputs/tables/` are derived statistics — shares,
rates, hazard estimates and confidence intervals computed across millions of
credits — rather than reproductions of any source record, and are published
under CC BY 4.0 on that basis.

If you intend to reuse this work commercially, or to redistribute anything
derived from the source datasets, review the upstream terms yourself. Nothing
here is legal advice.
