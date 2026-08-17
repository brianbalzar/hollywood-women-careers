# ---------------------------------------------------------------------------
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
# Scale bridge: tokens are authored in CSS pixels against a 1180px figure.
# One design pixel == 1/100 inch, so a "wide" figure is 11.8 inches and every
# point size below is token_px * 72 / 100. Do not hand-tune these; change the
# token and regenerate.
# ---------------------------------------------------------------------------

# ---- tokens ---------------------------------------------------------------

hwc_colors <- list(
  women          = "#2a78d6",  # categorical slot 1 - women-coded (LOCKED)
  men            = "#eb6834",  # categorical slot 2 - men-coded (LOCKED)
  ghost          = "#c3c2b7",  # non-identity context trace; never a series
  surface        = "#fcfcfb",  # carded figure surface
  plane          = "#f9f9f7",  # page bed; the default figure background
  ink            = "#0b0b0b",  # headlines, hero numerals
  ink_body       = "#1c1b19",  # running body copy
  ink_2          = "#52514e",  # notes, sources, legends
  muted          = "#898781",  # kickers, axis labels
  gridline       = "#e1e0d9",  # gridlines, table row rules
  baseline       = "#c3c2b7",  # axis rule
  rule_emphatic  = "#0b0b0b",  # the one 2px rule on the page
  good           = "#0ca30c",  # status - reserved, never a series
  warning        = "#fab219",  # status - reserved
  serious        = "#ec835a",  # status - reserved (marks only; fails as text)
  critical       = "#d03b3b",  # status - reserved
  delta_negative = "#c0472a",  # text-legible negative delta; 4.77:1 on plane
  seq            = c("#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b")
)

#' Dark-mode token overrides. Unreviewed by design as of this generation —
#' see NOTES.md. Use theme_hwc(mode = "dark") only for screen output.
hwc_colors_dark <- list(
  women          = "#3987e5",
  men            = "#d95926",
  ghost          = "#4a4a46",
  surface        = "#1a1a19",
  plane          = "#0d0d0d",
  ink            = "#ffffff",
  ink_body       = "#ededea",
  ink_2          = "#c3c2b7",
  muted          = "#898781",
  gridline       = "#2c2c2a",
  baseline       = "#383835",
  rule_emphatic  = "#ffffff",
  good           = "#0ca30c",
  delta_negative = "#f08a6a",
  seq            = hwc_colors$seq
)

hwc_credit_values <- c(
  "women-coded" = hwc_colors$women, "men-coded"   = hwc_colors$men,
  "Women-coded" = hwc_colors$women, "Men-coded"   = hwc_colors$men,
  "women"       = hwc_colors$women, "men"         = hwc_colors$men
)

#' Type scale, in points, derived from the token pixel scale.
hwc_type <- list(
  hero       = 108.0,   display    = 54.72,
  tile       = 27.36,   h1         = 24.48,
  h2         = 21.6,     h3         = 17.28,
  standfirst = 16.56, body   = 12.96,
  small      = 10.8,  caption    = 10.08,
  micro      = 9.72,  note       = 9.0,
  label      = 8.64,  axis       = 8.28,
  parity     = 7.92
)

#' Mark weights, as ggplot2 linewidth values.
hwc_marks <- list(
  series   = 0.763,   # 2.25px
  ghost    = 0.508,    # 1.5px
  rule     = 0.339,     # 1px
  dot_r    = 2.00,
  dot_halo = 0.677
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
.hwc_theme_root <- local({
  source_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (is.null(source_file) || !nzchar(source_file)) {
    normalizePath(".", winslash = "/", mustWork = FALSE)
  } else {
    dirname(dirname(normalizePath(source_file, winslash = "/", mustWork = FALSE)))
  }
})

.hwc_register_bundled_fonts <- function(available = character()) {
  if (!requireNamespace("systemfonts", quietly = TRUE)) return(character())
  specs <- list(
    "Newsreader" = c(
      plain = "newsreader-latin-300-normal.woff2",
      bold = "newsreader-latin-600-normal.woff2"
    ),
    "IBM Plex Sans" = c(
      plain = "ibm-plex-sans-latin-400-normal.woff2",
      bold = "ibm-plex-sans-latin-600-normal.woff2"
    )
  )
  registered <- character()
  for (family in names(specs)) {
    if (family %in% available) next
    files <- file.path(.hwc_theme_root, "fonts", specs[[family]])
    if (!all(file.exists(files))) next
    ok <- tryCatch({
      systemfonts::register_font(
        name = family,
        plain = unname(files[[1]]),
        bold = unname(files[[2]])
      )
      TRUE
    }, error = function(e) FALSE)
    if (ok) registered <- c(registered, family)
  }
  registered
}

hwc_fonts <- local({
  warned <- FALSE
  function() {
    want <- list(serif = "Newsreader", sans = "IBM Plex Sans")
    have <- character()
    if (requireNamespace("systemfonts", quietly = TRUE)) {
      have <- unique(systemfonts::system_fonts()$family)
      have <- unique(c(have, .hwc_register_bundled_fonts(have)))
    }
    fallback <- list(serif = c("Georgia", "Times New Roman", "serif"),
                     sans  = c("Segoe UI", "Helvetica Neue", "Arial", "sans"))
    out <- list()
    missing <- character()
    for (slot in names(want)) {
      if (want[[slot]] %in% have) {
        out[[slot]] <- want[[slot]]
      } else {
        missing <- c(missing, want[[slot]])
        hit <- fallback[[slot]][fallback[[slot]] %in% have]
        out[[slot]] <- if (length(hit)) hit[1] else ""
      }
    }
    if (length(missing) && !warned) {
      warned <<- TRUE
      warning(
        "theme_hwc: design font(s) not installed: ", paste(missing, collapse = ", "),
        ".\n  Figures will render in a fallback and will NOT match the report.",
        "\n  Bundled fonts could not be registered; install them locally.",
        "\n  Also install the 'ragg' and 'systemfonts' packages for reliable",
        " font rendering on Windows.",
        call. = FALSE
      )
    }
    out
  }
})

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
theme_hwc <- function(base_size = 12.96, grid = "y", mode = c("light", "dark")) {
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
        size = rel(hwc_type$h1), lineheight = 1.15,
        margin = ggplot2::margin(b = half * 0.7)),
      plot.subtitle = ggplot2::element_text(
        family = f$sans, colour = k$ink_2,
        size = rel(hwc_type$small), lineheight = 1.6,
        margin = ggplot2::margin(b = half * 1.5)),
      plot.caption.position = "plot",
      plot.caption = ggplot2::element_text(
        family = f$sans, colour = k$muted, hjust = 0,
        size = rel(hwc_type$note), lineheight = 1.6,
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
      panel.spacing    = ggplot2::unit(17.28, "pt"),

      plot.margin = ggplot2::margin(half * 1.5, half * 1.5, half, half * 1.5)
    )

  if (grid == "y")    th <- th + ggplot2::theme(panel.grid.major.x = ggplot2::element_blank())
  if (grid == "x")    th <- th + ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
  if (grid == "none") th <- th + ggplot2::theme(panel.grid.major = ggplot2::element_blank())
  th
}

# ---- scales ---------------------------------------------------------------

scale_colour_hwc <- function(...) {
  ggplot2::scale_colour_manual(values = hwc_credit_values, na.value = hwc_colors$muted, ...)
}
scale_color_hwc <- scale_colour_hwc

scale_fill_hwc <- function(...) {
  ggplot2::scale_fill_manual(values = hwc_credit_values, na.value = hwc_colors$muted, ...)
}

#' Single-hue sequential scale, for magnitude only. Never for nominal categories.
scale_fill_hwc_seq <- function(...) {
  ggplot2::scale_fill_gradientn(colours = hwc_colors$seq, ...)
}

scale_y_hwc_pct <- function(breaks = scales::breaks_width(0.1), ...) {
  ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 1),
                              breaks = breaks, ...)
}

# ---- annotation helpers ---------------------------------------------------

#' Parity / reference rule with a small-caps label at the right edge.
#' Dotted, per the token system's parity treatment; every other rule is solid.
hwc_reference <- function(yintercept, label = NULL, x = Inf) {
  f <- hwc_fonts()
  layers <- list(ggplot2::geom_hline(
    yintercept = yintercept, colour = hwc_colors$muted,
    linewidth = hwc_marks$rule, linetype = "dotted"))
  if (!is.null(label)) {
    layers <- c(layers, list(ggplot2::annotate(
      "text", x = x, y = yintercept, label = toupper(label), family = f$sans,
      hjust = 1.05, vjust = -0.7, size = hwc_type$parity / ggplot2::.pt,
      colour = hwc_colors$muted)))
  }
  layers
}

#' Change-point mark. The default caption is deliberate: this is where the
#' decline SLOWS. Never label it as a cliff.
hwc_change_point <- function(xintercept, label, sub = "decline slows", y = Inf) {
  f <- hwc_fonts()
  txt <- if (is.null(sub)) label else paste0(label, "\n", sub)
  list(
    ggplot2::geom_vline(xintercept = xintercept, colour = hwc_colors$muted,
                        linewidth = hwc_marks$rule, alpha = 0.5),
    ggplot2::annotate("text", x = xintercept, y = y, label = txt, family = f$sans,
                      hjust = -0.08, vjust = 1.2, size = hwc_type$axis / ggplot2::.pt,
                      lineheight = 1.05, colour = hwc_colors$ink_2)
  )
}

#' Direct series label, placed where the series separate — never at a
#' converging end. Sans, bold, ink-coloured: text never wears the series hue.
hwc_direct_label <- function(x, y, label, nudge_y = 0) {
  f <- hwc_fonts()
  ggplot2::annotate("text", x = x, y = y + nudge_y, label = label, family = f$sans,
                    colour = hwc_colors$ink, fontface = "bold",
                    size = hwc_type$small / ggplot2::.pt)
}

#' Mark a capped series end, so a stop never reads as the end of the data.
hwc_sample_cap <- function(x, y, label = "sample cap, not the end of the data") {
  f <- hwc_fonts()
  ggplot2::annotate("text", x = x, y = y, label = label, family = f$sans,
                    hjust = 1, vjust = 1.9, size = hwc_type$axis / ggplot2::.pt,
                    colour = hwc_colors$muted)
}

#' The mark specs, as geom defaults. Call once after sourcing.
hwc_set_geom_defaults <- function() {
  ggplot2::update_geom_defaults("line",    list(linewidth = hwc_marks$series))
  ggplot2::update_geom_defaults("point",   list(size = hwc_marks$dot_r))
  ggplot2::update_geom_defaults("ribbon",  list(alpha = 0.13, colour = NA))
  ggplot2::update_geom_defaults("boxplot", list(linewidth = hwc_marks$rule))
  invisible(TRUE)
}

# ---- output ---------------------------------------------------------------

#' Save a report figure at a size derived from the token figure widths.
#'
#' Uses ragg when available, which is the only reliable way to get a named
#' font family onto a PNG on Windows.
#'
#' @param variant "wide" (11.8in, the full-bleed figure width),
#'   "half" (5.78in, side-by-side), "square" (social), "story" (vertical social)
hwc_save <- function(plot, path, variant = c("wide", "half", "square", "story"),
                     dpi = 200, bg = hwc_colors$plane) {
  variant <- match.arg(variant)
  dims <- switch(variant,
    wide   = c(11.8, 6.25),
    half   = c(5.78, 4.51),
    square = c(12.0, 12.0),
    story  = c(10.8, 13.5)
  )
  args <- list(filename = path, plot = plot, width = dims[1], height = dims[2],
               dpi = dpi, bg = bg, units = "in")
  if (requireNamespace("ragg", quietly = TRUE)) args$device <- ragg::agg_png
  do.call(ggplot2::ggsave, args)
  invisible(path)
}

#' Standard source and interpretation-boundary caption. Every figure gets one.
hwc_caption <- function(source = c("imdb", "billboard"), extra = NULL) {
  source <- match.arg(source)
  base <- switch(source,
    imdb = paste(
      "Source: IMDb non-commercial datasets, U.S.-market titles, release years 2000 to the",
      "latest complete year.\n\"Women-coded\" and \"men-coded\" are predominant IMDb",
      "credit-metadata classes, not self-identified gender. Public credits measure observed",
      "opportunity, not who was available, auditioned, declined, or retired."),
    billboard = paste(
      "Source: Billboard Hot 100, 1995-2025, matched to MusicBrainz solo artists with",
      "birth-year and gender metadata\n(49.8% of chart rows classified). Groups and",
      "ambiguous names are excluded rather than assigned a gender.")
  )
  if (is.null(extra)) base else paste0(extra, "\n", base)
}

# ---- vocabulary -----------------------------------------------------------

#' The two parity ages, named. NOTES.md flagged that "parity age" was being
#' used for both; these are the agreed names.
#'
#' @param share_by_age named numeric vector, ages as names
#' @return list(last_at_parity, crossing, share_at_crossing)
hwc_parity_ages <- function(share_by_age) {
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
}
