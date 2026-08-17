#!/usr/bin/env python3
"""Re-derive R/theme_hwc.R and reports/hwc.scss from design-system/tokens.css.

tokens.css is the contract handed back by Claude Design. Nothing downstream
hard-codes a hex or a size: this script parses the token block and emits both
consumer layers, so a token change is a one-command rebuild rather than a
hand-translation.

    python3 build/derive_from_tokens.py

Scale bridge
------------
Tokens are authored in CSS pixels against a --figure-max wide figure. R figures
are authored in inches. The bridge is one constant:

    DESIGN_PX_PER_IN = 100

i.e. an R figure is sized so that one design pixel renders as one design pixel
when the figure is displayed at --figure-max. That makes every derived point
size and line width a pure function of the tokens:

    pt   = token_px * 72 / DESIGN_PX_PER_IN
    mm   = token_px * 25.4 / DESIGN_PX_PER_IN
    lwd  = mm / 0.75                      (ggplot2 linewidth unit)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths as P

ROOT = P.ROOT
TOKENS = P.tokens_path()
OUT_R = P.OUT_R          # <repo>/R/theme_hwc.R
OUT_SCSS = P.OUT_SCSS    # <repo>/reports/hwc.scss

DESIGN_PX_PER_IN = 100.0
GGPLOT_LINEWIDTH_MM = 0.75          # ggplot2: linewidth 1 == 0.75 mm

# --------------------------------------------------------------------- parse
src = open(TOKENS, encoding="utf-8").read()


def block(selector_hint, after=0):
    """Return the body of the first {...} block whose selector contains the hint."""
    i = src.index(selector_hint, after)
    start = src.index("{", i)
    depth, j = 0, start
    while True:
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return src[start + 1:j], j


def decls(body):
    out = {}
    # strip comments so a hex inside /* ... */ never becomes a token
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    for m in re.finditer(r"(--[\w-]+)\s*:\s*([^;]+);", body):
        out[m.group(1)] = m.group(2).strip()
    return out


light_body, end = block(".viz-root, .ds-root")
LIGHT = decls(light_body)
dark_body, _ = block('[data-theme="dark"] .viz-root')
DARK = decls(dark_body)

missing = [k for k in ("--series-1", "--series-2", "--font-serif", "--font-sans",
                       "--figure-max", "--chart-stroke") if k not in LIGHT]
if missing:
    sys.exit(f"tokens.css is missing required tokens: {missing}")

# guard the locked decisions — a silent hue change here would invalidate the
# colour-vision validation the whole system rests on
LOCKED = {"--series-1": "#2a78d6", "--series-2": "#eb6834"}
for k, v in LOCKED.items():
    if LIGHT[k].lower() != v:
        sys.exit(f"LOCKED token {k} changed to {LIGHT[k]} (expected {v}). "
                 "Re-run scripts/validate_palette.js before allowing this.")

px = lambda k: float(re.match(r"[\d.]+", LIGHT[k]).group())
pt = lambda k: round(px(k) * 72 / DESIGN_PX_PER_IN, 2)
mm = lambda k: round(px(k) * 25.4 / DESIGN_PX_PER_IN, 3)
lwd = lambda k: round(mm(k) / GGPLOT_LINEWIDTH_MM, 3)
q = lambda k: LIGHT[k].strip()


def family(token):
    """First family in a CSS font stack, unquoted."""
    first = q(token).split(",")[0].strip()
    return first.strip('"').strip("'")


SERIF = family("--font-serif")
SANS = family("--font-sans")
FIG_MAX = px("--figure-max")
BASE_PT = pt("--fs-body")

# R figure sizes, in inches, derived from the token widths
W_WIDE = round(FIG_MAX / DESIGN_PX_PER_IN, 2)
W_HALF = round((FIG_MAX - px("--panel-gap")) / 2 / DESIGN_PX_PER_IN, 2)

# tokens.css names a Google Fonts URL. A remote @import would make
# `quarto render` depend on network access and would defeat embed-resources,
# so the faces are self-hosted and inlined. See build/embed_fonts.py.
FACES = os.path.join(P.FONTS, "faces-embedded.css")
if not os.path.exists(FACES):
    sys.exit("fonts/faces-embedded.css missing — run: python3 design-system/build/embed_fonts.py")
FONT_FACES = open(FACES, encoding="utf-8").read()

print(f"tokens.css -> {len(LIGHT)} light tokens, {len(DARK)} dark overrides")
print(f"  serif={SERIF!r} sans={SANS!r} figure-max={FIG_MAX:.0f}px "
      f"-> wide {W_WIDE}in, half {W_HALF}in, base {BASE_PT}pt")

# ------------------------------------------------------------------- emit R
r_colors = [
    ("women", "--series-1", "categorical slot 1 - women-coded (LOCKED)"),
    ("men", "--series-2", "categorical slot 2 - men-coded (LOCKED)"),
    ("ghost", "--series-ghost", "non-identity context trace; never a series"),
    ("surface", "--surface-1", "carded figure surface"),
    ("plane", "--page-plane", "page bed; the default figure background"),
    ("ink", "--text-primary", "headlines, hero numerals"),
    ("ink_body", "--text-body", "running body copy"),
    ("ink_2", "--text-secondary", "notes, sources, legends"),
    ("muted", "--text-muted", "kickers, axis labels"),
    ("gridline", "--gridline", "gridlines, table row rules"),
    ("baseline", "--baseline", "axis rule"),
    ("rule_emphatic", "--rule-emphatic", "the one 2px rule on the page"),
    ("good", "--status-good", "status - reserved, never a series"),
    ("warning", "--status-warning", "status - reserved"),
    ("serious", "--status-serious", "status - reserved (marks only; fails as text)"),
    ("critical", "--status-critical", "status - reserved"),
    ("delta_negative", "--delta-negative", "text-legible negative delta; 4.77:1 on plane"),
]
seq = [LIGHT[f"--seq-{n}"] for n in (100, 200, 300, 400, 500, 600, 700)]

col_lines = "\n".join(
    f'  {name:<15}= "{LIGHT[tok]}",{"":<2}# {note}' for name, tok, note in r_colors)
dark_pairs = "\n".join(
    f'  {name:<15}= "{DARK.get(tok, LIGHT[tok])}",'
    for name, tok, _ in r_colors if tok in DARK)

R = f'''# ---------------------------------------------------------------------------
# theme_hwc.R  —  figure design system for
# "Women's Career Lifespans in U.S. Entertainment"
#
#   GENERATED FILE — do not edit by hand.
#   Source of truth: tokens.css
#   Regenerate:      python3 build/derive_from_tokens.py
#
# Wire it in with two lines at the top of a plotting script:
#
#   source("R/theme_hwc.R")
#   ggplot2::theme_set(theme_hwc()); hwc_set_geom_defaults()
#
# Scale bridge: tokens are authored in CSS pixels against a {FIG_MAX:.0f}px figure.
# One design pixel == 1/{DESIGN_PX_PER_IN:.0f} inch, so a "wide" figure is {W_WIDE} inches and every
# point size below is token_px * 72 / {DESIGN_PX_PER_IN:.0f}. Do not hand-tune these; change the
# token and regenerate.
# ---------------------------------------------------------------------------

# ---- tokens ---------------------------------------------------------------

hwc_colors <- list(
{col_lines}
  seq            = c({", ".join(f'"{s}"' for s in seq)})
)

#' Dark-mode token overrides. Unreviewed by design as of this generation —
#' see NOTES.md. Use theme_hwc(mode = "dark") only for screen output.
hwc_colors_dark <- list(
{dark_pairs}
  seq            = hwc_colors$seq
)

hwc_credit_values <- c(
  "women-coded" = hwc_colors$women, "men-coded"   = hwc_colors$men,
  "Women-coded" = hwc_colors$women, "Men-coded"   = hwc_colors$men,
  "women"       = hwc_colors$women, "men"         = hwc_colors$men
)

#' Type scale, in points, derived from the token pixel scale.
hwc_type <- list(
  hero       = {pt("--fs-hero")},   display    = {pt("--fs-display")},
  tile       = {pt("--fs-tile")},   h1         = {pt("--fs-h1")},
  h2         = {pt("--fs-h2")},     h3         = {pt("--fs-h3")},
  standfirst = {pt("--fs-standfirst")}, body   = {pt("--fs-body")},
  small      = {pt("--fs-small")},  caption    = {pt("--fs-caption")},
  micro      = {pt("--fs-micro")},  note       = {pt("--fs-note")},
  label      = {pt("--fs-label")},  axis       = {pt("--fs-axis")},
  parity     = {pt("--fs-parity")}
)

#' Mark weights, as ggplot2 linewidth values.
hwc_marks <- list(
  series   = {lwd("--chart-stroke")},   # {q("--chart-stroke")}
  ghost    = {lwd("--chart-ghost")},    # {q("--chart-ghost")}
  rule     = {lwd("--chart-rule")},     # {q("--chart-rule")}
  dot_r    = {px("--chart-dot") / 2:.2f},
  dot_halo = {lwd("--chart-dot-halo")}
)

# ---- fonts ----------------------------------------------------------------

#' Resolve the design system's two families, with a loud warning on fallback.
#'
#' The system pairs a serif for titles and displayed numerals with a sans for
#' body, tables and all chart text. Neither ships with Windows or macOS. If a
#' family is missing the figures still render, but they will not match the
#' report, so this warns once per session rather than failing silently.
#'
#' The repository's bundled WOFF2 files are registered automatically when
#' systemfonts is available. A system installation remains a valid fallback.
.hwc_theme_root <- local({{
  source_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (is.null(source_file) || !nzchar(source_file)) {{
    normalizePath(".", winslash = "/", mustWork = FALSE)
  }} else {{
    dirname(dirname(normalizePath(source_file, winslash = "/", mustWork = FALSE)))
  }}
}})

.hwc_register_bundled_fonts <- function(available = character()) {{
  if (!requireNamespace("systemfonts", quietly = TRUE)) return(character())
  specs <- list(
    "{SERIF}" = c(
      plain = "newsreader-latin-300-normal.woff2",
      bold = "newsreader-latin-600-normal.woff2"
    ),
    "{SANS}" = c(
      plain = "ibm-plex-sans-latin-400-normal.woff2",
      bold = "ibm-plex-sans-latin-600-normal.woff2"
    )
  )
  registered <- character()
  for (family in names(specs)) {{
    if (family %in% available) next
    files <- file.path(.hwc_theme_root, "fonts", specs[[family]])
    if (!all(file.exists(files))) next
    ok <- tryCatch({{
      systemfonts::register_font(
        name = family,
        plain = unname(files[[1]]),
        bold = unname(files[[2]])
      )
      TRUE
    }}, error = function(e) FALSE)
    if (ok) registered <- c(registered, family)
  }}
  registered
}}

hwc_fonts <- local({{
  warned <- FALSE
  function() {{
    want <- list(serif = "{SERIF}", sans = "{SANS}")
    have <- character()
    if (requireNamespace("systemfonts", quietly = TRUE)) {{
      have <- unique(systemfonts::system_fonts()$family)
      have <- unique(c(have, .hwc_register_bundled_fonts(have)))
    }}
    fallback <- list(serif = c("Georgia", "Times New Roman", "serif"),
                     sans  = c("Segoe UI", "Helvetica Neue", "Arial", "sans"))
    out <- list()
    missing <- character()
    for (slot in names(want)) {{
      if (want[[slot]] %in% have) {{
        out[[slot]] <- want[[slot]]
      }} else {{
        missing <- c(missing, want[[slot]])
        hit <- fallback[[slot]][fallback[[slot]] %in% have]
        out[[slot]] <- if (length(hit)) hit[1] else ""
      }}
    }}
    if (length(missing) && !warned) {{
      warned <<- TRUE
      warning(
        "theme_hwc: design font(s) not installed: ", paste(missing, collapse = ", "),
        ".\\n  Figures will render in a fallback and will NOT match the report.",
        "\\n  Bundled fonts could not be registered; install them locally.",
        "\\n  Also install the 'ragg' and 'systemfonts' packages for reliable",
        " font rendering on Windows.",
        call. = FALSE
      )
    }}
    out
  }}
}})

# ---- theme ----------------------------------------------------------------

#' Report figure theme.
#'
#' Serif titles, sans everything else. Horizontal hairline grid only, solid
#' never dashed. No panel border, no vertical grid, no minor grid. Axis rule on
#' the x baseline only. Legend top-left, under the subtitle.
#'
#' @param base_size body size in points; defaults to the token value
#' @param grid one of "y" (default), "x", "both", "none"
#' @param mode "light" (default) or "dark"
theme_hwc <- function(base_size = {BASE_PT}, grid = "y", mode = c("light", "dark")) {{
  mode <- match.arg(mode)
  k <- if (mode == "dark") hwc_colors_dark else hwc_colors
  f <- hwc_fonts()
  rel <- function(pt_value) ggplot2::rel(pt_value / base_size)
  half <- base_size / 2

  th <- ggplot2::theme_minimal(base_size = base_size, base_family = f$sans) +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = k$plane, colour = NA),
      panel.background = ggplot2::element_rect(fill = k$plane, colour = NA),
      panel.border     = ggplot2::element_blank(),

      panel.grid.major = ggplot2::element_line(colour = k$gridline,
                                               linewidth = hwc_marks$rule,
                                               linetype = "solid"),
      panel.grid.minor = ggplot2::element_blank(),

      axis.line.x = ggplot2::element_line(colour = k$baseline, linewidth = hwc_marks$rule),
      axis.line.y = ggplot2::element_blank(),
      axis.ticks  = ggplot2::element_blank(),
      axis.text   = ggplot2::element_text(colour = k$muted, size = rel(hwc_type$axis),
                                          family = f$sans),
      axis.title  = ggplot2::element_text(colour = k$ink_2, size = rel(hwc_type$micro),
                                          family = f$sans),
      axis.title.x = ggplot2::element_text(margin = ggplot2::margin(t = half)),
      axis.title.y = ggplot2::element_text(margin = ggplot2::margin(r = half)),

      # titles are serif: the editorial voice. Everything else stays sans.
      plot.title.position = "plot",
      plot.title = ggplot2::element_text(
        family = f$serif, colour = k$ink, face = "plain",
        size = rel(hwc_type$h1), lineheight = {q("--lh-title")},
        margin = ggplot2::margin(b = half * 0.7)),
      plot.subtitle = ggplot2::element_text(
        family = f$sans, colour = k$ink_2,
        size = rel(hwc_type$small), lineheight = {q("--lh-note")},
        margin = ggplot2::margin(b = half * 1.5)),
      plot.caption.position = "plot",
      plot.caption = ggplot2::element_text(
        family = f$sans, colour = k$muted, hjust = 0,
        size = rel(hwc_type$note), lineheight = {q("--lh-note")},
        margin = ggplot2::margin(t = half * 1.8)),

      legend.position      = "top",
      legend.justification = "left",
      legend.title         = ggplot2::element_blank(),
      legend.text          = ggplot2::element_text(colour = k$ink_2, family = f$sans,
                                                   size = rel(hwc_type$micro)),
      legend.key           = ggplot2::element_blank(),
      legend.margin        = ggplot2::margin(b = half),
      legend.box.spacing   = ggplot2::unit(0, "pt"),

      strip.text = ggplot2::element_text(
        family = f$sans, colour = k$ink, face = "bold", hjust = 0,
        size = rel(hwc_type$small), margin = ggplot2::margin(b = half * 0.6)),
      strip.background = ggplot2::element_blank(),
      panel.spacing    = ggplot2::unit({pt("--panel-gap")}, "pt"),

      plot.margin = ggplot2::margin(half * 1.5, half * 1.5, half, half * 1.5)
    )

  if (grid == "y")    th <- th + ggplot2::theme(panel.grid.major.x = ggplot2::element_blank())
  if (grid == "x")    th <- th + ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
  if (grid == "none") th <- th + ggplot2::theme(panel.grid.major = ggplot2::element_blank())
  th
}}

# ---- scales ---------------------------------------------------------------

scale_colour_hwc <- function(...) {{
  ggplot2::scale_colour_manual(values = hwc_credit_values, na.value = hwc_colors$muted, ...)
}}
scale_color_hwc <- scale_colour_hwc

scale_fill_hwc <- function(...) {{
  ggplot2::scale_fill_manual(values = hwc_credit_values, na.value = hwc_colors$muted, ...)
}}

#' Single-hue sequential scale, for magnitude only. Never for nominal categories.
scale_fill_hwc_seq <- function(...) {{
  ggplot2::scale_fill_gradientn(colours = hwc_colors$seq, ...)
}}

scale_y_hwc_pct <- function(breaks = scales::breaks_width(0.1), ...) {{
  ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 1),
                              breaks = breaks, ...)
}}

# ---- annotation helpers ---------------------------------------------------

#' Parity / reference rule with a small-caps label at the right edge.
#' Dotted, per the token system's parity treatment; every other rule is solid.
hwc_reference <- function(yintercept, label = NULL, x = Inf) {{
  f <- hwc_fonts()
  layers <- list(ggplot2::geom_hline(
    yintercept = yintercept, colour = hwc_colors$muted,
    linewidth = hwc_marks$rule, linetype = "dotted"))
  if (!is.null(label)) {{
    layers <- c(layers, list(ggplot2::annotate(
      "text", x = x, y = yintercept, label = toupper(label), family = f$sans,
      hjust = 1.05, vjust = -0.7, size = hwc_type$parity / ggplot2::.pt,
      colour = hwc_colors$muted)))
  }}
  layers
}}

#' Change-point mark. The default caption is deliberate: this is where the
#' decline SLOWS. Never label it as a cliff.
hwc_change_point <- function(xintercept, label, sub = "decline slows", y = Inf) {{
  f <- hwc_fonts()
  txt <- if (is.null(sub)) label else paste0(label, "\\n", sub)
  list(
    ggplot2::geom_vline(xintercept = xintercept, colour = hwc_colors$muted,
                        linewidth = hwc_marks$rule, alpha = 0.5),
    ggplot2::annotate("text", x = xintercept, y = y, label = txt, family = f$sans,
                      hjust = -0.08, vjust = 1.2, size = hwc_type$axis / ggplot2::.pt,
                      lineheight = 1.05, colour = hwc_colors$ink_2)
  )
}}

#' Direct series label, placed where the series separate — never at a
#' converging end. Sans, bold, ink-coloured: text never wears the series hue.
hwc_direct_label <- function(x, y, label, nudge_y = 0) {{
  f <- hwc_fonts()
  ggplot2::annotate("text", x = x, y = y + nudge_y, label = label, family = f$sans,
                    colour = hwc_colors$ink, fontface = "bold",
                    size = hwc_type$small / ggplot2::.pt)
}}

#' Mark a capped series end, so a stop never reads as the end of the data.
hwc_sample_cap <- function(x, y, label = "sample cap, not the end of the data") {{
  f <- hwc_fonts()
  ggplot2::annotate("text", x = x, y = y, label = label, family = f$sans,
                    hjust = 1, vjust = 1.9, size = hwc_type$axis / ggplot2::.pt,
                    colour = hwc_colors$muted)
}}

#' The mark specs, as geom defaults. Call once after sourcing.
hwc_set_geom_defaults <- function() {{
  ggplot2::update_geom_defaults("line",    list(linewidth = hwc_marks$series))
  ggplot2::update_geom_defaults("point",   list(size = hwc_marks$dot_r))
  ggplot2::update_geom_defaults("ribbon",  list(alpha = 0.13, colour = NA))
  ggplot2::update_geom_defaults("boxplot", list(linewidth = hwc_marks$rule))
  invisible(TRUE)
}}

# ---- output ---------------------------------------------------------------

#' Save a report figure at a size derived from the token figure widths.
#'
#' Uses ragg when available, which is the only reliable way to get a named
#' font family onto a PNG on Windows.
#'
#' @param variant "wide" ({W_WIDE}in, the full-bleed figure width),
#'   "half" ({W_HALF}in, side-by-side), "square" (social), "story" (vertical social)
hwc_save <- function(plot, path, variant = c("wide", "half", "square", "story"),
                     dpi = 200, bg = hwc_colors$plane) {{
  variant <- match.arg(variant)
  dims <- switch(variant,
    wide   = c({W_WIDE}, {round(W_WIDE * 0.53, 2)}),
    half   = c({W_HALF}, {round(W_HALF * 0.78, 2)}),
    square = c(12.0, 12.0),
    story  = c(10.8, 13.5)
  )
  args <- list(filename = path, plot = plot, width = dims[1], height = dims[2],
               dpi = dpi, bg = bg, units = "in")
  if (requireNamespace("ragg", quietly = TRUE)) args$device <- ragg::agg_png
  do.call(ggplot2::ggsave, args)
  invisible(path)
}}

#' Standard source and interpretation-boundary caption. Every figure gets one.
hwc_caption <- function(source = c("imdb", "billboard"), extra = NULL) {{
  source <- match.arg(source)
  base <- switch(source,
    imdb = paste(
      "Source: IMDb non-commercial datasets, U.S.-market titles, release years 2000 to the",
      "latest complete year.\\n\\"Women-coded\\" and \\"men-coded\\" are predominant IMDb",
      "credit-metadata classes, not self-identified gender. Public credits measure observed",
      "opportunity, not who was available, auditioned, declined, or retired."),
    billboard = paste(
      "Source: Billboard Hot 100, 1995-2025, matched to MusicBrainz solo artists with",
      "birth-year and gender metadata\\n(49.8% of chart rows classified). Groups and",
      "ambiguous names are excluded rather than assigned a gender.")
  )
  if (is.null(extra)) base else paste0(extra, "\\n", base)
}}

# ---- vocabulary -----------------------------------------------------------

#' The two parity ages, named. NOTES.md flagged that "parity age" was being
#' used for both; these are the agreed names.
#'
#' @param share_by_age named numeric vector, ages as names
#' @return list(last_at_parity, crossing, share_at_crossing)
hwc_parity_ages <- function(share_by_age) {{
  ages <- as.integer(names(share_by_age))
  ord <- order(ages); ages <- ages[ord]; v <- unname(share_by_age[ord])
  below <- which(v < 0.5)
  stays <- below[vapply(below, function(i) all(v[i:length(v)] < 0.5), logical(1))]
  if (!length(stays)) return(list(last_at_parity = NA_integer_, crossing = NA_integer_,
                                  share_at_crossing = NA_real_))
  i <- stays[1]
  list(
    last_at_parity    = ages[i - 1],   # last age at or above 50%  (the hero numeral)
    crossing          = ages[i],       # first age below 50%, and it never returns
    share_at_crossing = v[i]
  )
}}
'''

os.makedirs(os.path.dirname(OUT_R), exist_ok=True)
os.makedirs(os.path.dirname(OUT_SCSS), exist_ok=True)
open(OUT_R, "w", encoding="utf-8").write(R)
print("wrote", os.path.relpath(OUT_R, ROOT))

# ---------------------------------------------------------------- emit SCSS
# --- the token block, re-emitted as CSS custom properties -------------------
def custom_property_block():
    lines = ["\n// Tokens as custom properties, so inline HTML in the .qmd can use var().",
             "// Light only: dark mode is declared in tokens.css but unreviewed (NOTES.md).",
             ":root {"]
    for k, v in LIGHT.items():
        lines.append(f"  {k}: {v};")
    lines.append("}")
    return "\n".join(lines)


def scss_defaults():
    rows = []
    for name, tok in [
        ("hwc-surface", "--surface-1"), ("hwc-plane", "--page-plane"),
        ("hwc-ink", "--text-primary"), ("hwc-ink-body", "--text-body"),
        ("hwc-ink-standfirst", "--text-standfirst"),
        ("hwc-ink-2", "--text-secondary"), ("hwc-muted", "--text-muted"),
        ("hwc-gridline", "--gridline"), ("hwc-baseline", "--baseline"),
        ("hwc-hairline", "--hairline"), ("hwc-hairline-strong", "--hairline-strong"),
        ("hwc-hairline-soft", "--hairline-soft"), ("hwc-rule-emphatic", "--rule-emphatic"),
        ("hwc-women", "--series-1"), ("hwc-men", "--series-2"),
        ("hwc-ghost", "--series-ghost"), ("hwc-delta-negative", "--delta-negative"),
        ("hwc-seq-100", "--seq-100"), ("hwc-seq-200", "--seq-200"),
        ("hwc-seq-300", "--seq-300"), ("hwc-seq-400", "--seq-400"),
        ("hwc-seq-500", "--seq-500"), ("hwc-seq-600", "--seq-600"),
        ("hwc-seq-700", "--seq-700"),
    ]:
        rows.append(f"${name}: {LIGHT[tok]};")
    for name, tok in [
        ("hwc-fs-hero", "--fs-hero"), ("hwc-fs-display", "--fs-display"),
        ("hwc-fs-tile", "--fs-tile"), ("hwc-fs-h1", "--fs-h1"),
        ("hwc-fs-h2", "--fs-h2"), ("hwc-fs-h3", "--fs-h3"),
        ("hwc-fs-standfirst", "--fs-standfirst"), ("hwc-fs-body", "--fs-body"),
        ("hwc-fs-lede", "--fs-lede"), ("hwc-fs-small", "--fs-small"),
        ("hwc-fs-caption", "--fs-caption"), ("hwc-fs-micro", "--fs-micro"),
        ("hwc-fs-note", "--fs-note"), ("hwc-fs-label", "--fs-label"),
        ("hwc-fs-axis", "--fs-axis"),
        ("hwc-measure", "--measure"), ("hwc-figure-max", "--figure-max"),
        ("hwc-ledger-label", "--ledger-label"), ("hwc-card-pad", "--card-pad"),
        ("hwc-card-radius", "--card-radius"),
        ("hwc-sp-fig", "--sp-fig"), ("hwc-sp-section", "--sp-section"),
        ("hwc-tr-title", "--tr-title"), ("hwc-tr-label", "--tr-label"),
        ("hwc-tr-ledger", "--tr-ledger"),
        ("hwc-lh-title", "--lh-title"), ("hwc-lh-body", "--lh-body"),
        ("hwc-lh-note", "--lh-note"),
    ]:
        rows.append(f"${name}: {LIGHT[tok]};")
    return "\n".join(rows)


CUSTOM_PROPS = custom_property_block()

SCSS = f'''/*-- scss:defaults --*/
// ---------------------------------------------------------------------------
// hwc.scss — Quarto theme layer for
// "Women's Career Lifespans in U.S. Entertainment"
//
//   GENERATED FILE — do not edit by hand.
//   Source of truth: tokens.css
//   Regenerate:      python3 build/derive_from_tokens.py
//
// Layer it over a light bootswatch base:
//
//   format:
//     html:
//       theme: [cosmo, hwc.scss]
// ---------------------------------------------------------------------------

// Self-hosted @font-face rules, inlined as base64 woff2 so the report renders
// offline and embed-resources has nothing external left to fetch.
// Sources: @fontsource/newsreader, @fontsource/ibm-plex-sans (both SIL OFL).
{FONT_FACES}

$font-family-serif:      {q("--font-serif")} !default;
$font-family-sans-serif: {q("--font-sans")} !default;

{scss_defaults()}

$font-size-root:   $hwc-fs-body !default;
$line-height-base: $hwc-lh-body !default;
$body-color:       $hwc-ink-body !default;
$body-bg:          $hwc-plane !default;
$link-color:       $hwc-seq-500 !default;
$code-color:       $hwc-seq-600 !default;
$code-bg:          #f2f1ed !default;
$table-border-color: $hwc-gridline !default;
$toc-color:        $hwc-ink-2 !default;
$headings-font-family: $font-family-serif !default;
$headings-font-weight: {q("--fw-serif-reg")} !default;

/*-- scss:rules --*/
{CUSTOM_PROPS}

// The serif carries the editorial voice; the sans carries the evidence.
// Chart text, tables, notes and sources are always sans, with tabular figures.

body {{
  background: $hwc-plane;
  color: $hwc-ink-body;
  font-family: $font-family-sans-serif;
  -webkit-font-smoothing: antialiased;
}}

main.content, #quarto-document-content {{ max-width: $hwc-measure; }}

// ------------------------------------------------------------------ masthead
#title-block-header {{
  padding-bottom: 1.6rem;
  margin-bottom: $hwc-sp-section;
  border-bottom: 1px solid $hwc-hairline-strong;

  .title {{
    font-family: $font-family-serif;
    font-weight: {q("--fw-serif")};
    font-size: $hwc-fs-display;
    line-height: {q("--lh-display")};
    letter-spacing: {q("--tr-display")};
    color: $hwc-ink;
    max-width: 18ch;
  }}
  .subtitle {{
    font-family: $font-family-serif;
    font-weight: {q("--fw-serif")};
    font-size: $hwc-fs-standfirst;
    line-height: {q("--lh-standfirst")};
    color: $hwc-ink-standfirst;
    margin-top: 1rem;
    max-width: 44ch;
  }}
  .quarto-title-meta {{
    font-family: $font-family-sans-serif;
    font-size: $hwc-fs-label;
    text-transform: uppercase;
    letter-spacing: $hwc-tr-label;
    color: $hwc-muted;
    margin-top: 1.8rem;
  }}
}}

// ------------------------------------------------------------------ headings
h1, h2, h3, h4 {{
  font-family: $font-family-serif;
  font-weight: {q("--fw-serif-reg")};
  letter-spacing: $hwc-tr-title;
  color: $hwc-ink;
}}
h2 {{
  font-size: $hwc-fs-h2;
  line-height: $hwc-lh-title;
  margin-top: $hwc-sp-section;
  padding-top: 1.6rem;
  border-top: 1px solid $hwc-hairline-strong;
}}
h2:first-of-type {{ border-top: none; padding-top: 0; margin-top: 0; }}
h3 {{
  font-size: $hwc-fs-h3;
  letter-spacing: {q("--tr-h3")};
  margin-top: 2.4rem;
}}

// --------------------------------------------------------------------- prose
p {{
  font-family: $font-family-sans-serif;
  font-size: $hwc-fs-body;
  line-height: $hwc-lh-body;
  max-width: 68ch;
}}

// ------------------------------------------------------- the caption ledger
// Replaces the tinted callout boxes. A small-caps label in its own column,
// the text beside it, a hairline above — so an interpretation boundary reads
// as part of the figure's apparatus, not as a warning sticker on it.
.definition, .boundary, .caution-note, figcaption,
.figure-caption, .quarto-float-caption {{
  display: grid;
  grid-template-columns: $hwc-ledger-label 1fr;
  gap: 0 1.5rem;
  border-top: 1px solid $hwc-hairline-soft;
  padding-top: 0.85rem;
  margin: 1.6rem 0;
  font-family: $font-family-sans-serif;
  font-size: $hwc-fs-micro;
  line-height: $hwc-lh-note;
  color: $hwc-ink-2;
  text-align: left;

  > :first-child {{ margin-top: 0; }}
  > :last-child  {{ margin-bottom: 0; }}
  p {{ grid-column: 2; font-size: inherit; max-width: 74ch; margin: 0 0 0.5rem; }}
  p:last-child {{ margin-bottom: 0; }}
}}

// The ledger label. Authored as the div's first strong/em, or via ::before.
.definition::before, .boundary::before, .caution-note::before {{
  grid-column: 1;
  grid-row: 1 / -1;
  font-size: $hwc-fs-axis;
  font-weight: {q("--fw-label")};
  text-transform: uppercase;
  letter-spacing: $hwc-tr-ledger;
  color: $hwc-muted;
  line-height: $hwc-lh-note;
}}
figcaption::before, .figure-caption::before, .quarto-float-caption::before {{
  content: "Note";
  grid-column: 1;
  grid-row: 1 / -1;
  font-size: $hwc-fs-axis;
  font-weight: {q("--fw-label")};
  text-transform: uppercase;
  letter-spacing: $hwc-tr-ledger;
  color: $hwc-muted;
  line-height: $hwc-lh-note;
}}
.definition::before    {{ content: "How to read"; }}
.boundary::before      {{ content: "Boundary"; }}
.caution-note::before  {{ content: "Coverage"; }}

// The one emphatic rule on the page: the closing boundary statement.
.boundary.closing {{
  border-top: 2px solid $hwc-rule-emphatic;
  padding-top: 1.1rem;
  font-size: $hwc-fs-lede;
}}

blockquote {{
  border: none;
  border-left: 2px solid $hwc-ink;
  padding: 0 0 0 1.4rem;
  margin: 1.8rem 0;
  font-family: $font-family-serif;
  font-size: $hwc-fs-standfirst;
  font-weight: {q("--fw-serif")};
  line-height: {q("--lh-standfirst")};
  color: $hwc-ink-standfirst;
  p {{ font-family: inherit; font-size: inherit; margin-bottom: 0.4rem; }}
}}

// ------------------------------------------------------------------- figures
// Full-bleed is the default: the figure breaks the text measure and is opened
// and closed by hairline rules. The card is reserved for the Billboard
// companion — the card MEANS "narrower companion study", it is not decoration.
figure, .quarto-figure {{
  margin: $hwc-sp-fig calc((#{{$hwc-measure}} - #{{$hwc-figure-max}}) / 2);
  max-width: $hwc-figure-max;
  border-top: 1px solid $hwc-hairline-strong;
  border-bottom: 1px solid $hwc-hairline-strong;
  padding: 1.6rem 0;
  background: none;
  border-radius: 0;

  img {{ width: 100%; height: auto; border-radius: 0; }}
}}

// `::: {{.companion}}` around a figure marks it as the carded companion.
.companion figure, figure.companion {{
  background: $hwc-surface;
  border: 1px solid $hwc-hairline;
  border-radius: $hwc-card-radius;
  padding: $hwc-card-pad;
  max-width: $hwc-measure;
  margin-left: 0;
  margin-right: 0;
}}

@media (max-width: 1240px) {{
  figure, .quarto-figure {{ margin-left: 0; margin-right: 0; max-width: 100%; }}
}}

// -------------------------------------------------------------------- tables
table, .table {{
  font-family: $font-family-sans-serif;
  font-size: $hwc-fs-note;
  font-variant-numeric: tabular-nums;
  border-collapse: collapse;
  width: 100%;
  margin: 1.6rem 0 2rem;

  caption {{
    caption-side: top;
    text-align: left;
    font-size: $hwc-fs-axis;
    text-transform: uppercase;
    letter-spacing: $hwc-tr-ledger;
    font-weight: {q("--fw-label")};
    color: $hwc-muted;
    font-variant-numeric: normal;
    padding-bottom: 0.6rem;
  }}
  thead th {{
    color: $hwc-ink-2;
    font-weight: {q("--fw-label")};
    font-variant-numeric: normal;
    border-bottom: 1px solid $hwc-baseline !important;
    border-top: none !important;
    white-space: nowrap;
    padding: 0.5rem 0.65rem;
  }}
  td, tbody th {{
    border-bottom: 1px solid $hwc-gridline;
    border-top: none !important;
    padding: 0.45rem 0.65rem;
  }}
  th:not(:first-child), td:not(:first-child) {{ text-align: right; }}
  th:first-child, td:first-child {{ text-align: left; }}
  tbody tr:nth-child(odd) > * {{ background: transparent !important; }}
  tbody tr:hover > * {{ background: rgba($hwc-ink, 0.035) !important; }}
  tbody tr:last-child td {{ border-bottom: none; }}
}}

// ------------------------------------------------------------- hero & tiles
// Displayed numerals are serif; their labels and meta stay sans.
.hero-figure {{
  font-family: $font-family-serif;
  font-weight: {q("--fw-serif")};
  font-size: $hwc-fs-hero;
  line-height: {q("--lh-hero")};
  letter-spacing: {q("--tr-hero")};
  color: $hwc-ink;
  margin: 0.2rem 0 0.6rem;
}}
.stat-row {{
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(calc(#{{$hwc-measure}} / 5), 1fr));
  gap: 0;
  margin: 2rem 0;
  border-top: 1px solid $hwc-hairline-soft;
}}
.stat-row > div {{
  padding: 1rem 1.2rem 1rem 0;
  strong {{
    display: block;
    font-family: $font-family-serif;
    font-weight: {q("--fw-serif-reg")};
    font-size: $hwc-fs-tile;
    letter-spacing: $hwc-tr-title;
    color: $hwc-ink;
  }}
  span {{
    font-family: $font-family-sans-serif;
    font-size: $hwc-fs-note;
    color: $hwc-ink-2;
  }}
  .delta-down {{ color: $hwc-delta-negative; font-weight: {q("--fw-label")}; }}
}}

// -------------------------------------------------------------- inline marks
.k-women::before, .k-men::before {{
  content: "";
  display: inline-block;
  width: 0.5em; height: 0.5em;
  border-radius: 50%;
  margin-right: 0.35em;
  vertical-align: 0.08em;
}}
.k-women::before {{ background: $hwc-women; }}
.k-men::before   {{ background: $hwc-men; }}

// ----------------------------------------------------------------- code, toc
div.sourceCode {{
  background: $code-bg;
  border: 1px solid $hwc-hairline;
  border-radius: 6px;
  font-size: $hwc-fs-note;
}}
details > summary {{
  font-family: $font-family-sans-serif;
  font-size: $hwc-fs-micro;
  color: $hwc-ink-2;
  cursor: pointer;
}}
#TOC, nav[role="doc-toc"] {{
  font-family: $font-family-sans-serif;
  font-size: $hwc-fs-note;
  a {{
    color: $hwc-ink-2;
    border-left: 2px solid transparent;
    padding-left: 0.7rem;
    &:hover {{ color: $hwc-ink; }}
  }}
  .active, a.active {{
    color: $hwc-ink !important;
    font-weight: {q("--fw-label")};
    border-left-color: $hwc-women;
  }}
  > h2, .toc-title {{
    font-family: $font-family-sans-serif;
    font-size: $hwc-fs-axis;
    text-transform: uppercase;
    letter-spacing: $hwc-tr-label;
    color: $hwc-muted;
    font-weight: {q("--fw-label")};
  }}
}}

// --------------------------------------------------------------------- print
@media print {{
  body {{ background: #fff; }}
  figure, .quarto-figure, table {{ break-inside: avoid; margin-left: 0; margin-right: 0; }}
  #TOC, nav[role="doc-toc"], details {{ display: none; }}
  h2 {{ break-after: avoid; }}
}}
'''

open(OUT_SCSS, "w", encoding="utf-8").write(SCSS)
print("wrote", os.path.relpath(OUT_SCSS, ROOT))
