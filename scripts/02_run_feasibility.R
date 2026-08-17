source("R/paths.R")
source("R/imdb_helpers.R")
source("R/metrics.R")

if (!requireNamespace("data.table", quietly = TRUE)) stop("Install data.table first.")
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Install ggplot2 first.")

# Synthetic records validate mechanics only. They are not substantive evidence.
set.seed(20260817)
people <- data.table::data.table(
  nconst = sprintf("nm%07d", 1:240),
  birth_year = rep(1965:2004, each = 6),
  credit_group = rep(c("women-coded", "men-coded"), 120)
)

synthetic <- people[, {
  ages <- 25:60
  base <- if (credit_group == "women-coded") {
    stats::plogis(1.2 - 0.13 * pmax(ages - 37, 0))
  } else {
    stats::plogis(1.2 - 0.06 * pmax(ages - 45, 0))
  }
  has_role <- stats::rbinom(length(ages), 1, base)
  data.table::data.table(
    release_year = birth_year + ages,
    age = ages,
    has_role = has_role
  )
}, by = .(nconst, birth_year, credit_group)]

synthetic <- synthetic[has_role == 1L]
synthetic[, tconst := sprintf("tt%09d", .I)]
synthetic[, `:=`(titleType = "movie", cast_rank = 1L)]

panel <- build_recent_activity_panel(synthetic, lookback = 5L)
curve <- opportunity_curve(panel, min_age = 26L, max_age = 60L)
normalized <- normalized_retention(curve)
ratio <- retention_ratio(normalized)

ensure_project_dirs()
data.table::fwrite(curve, project_path("outputs", "tables", "feasibility_opportunity_curve.csv"))
data.table::fwrite(normalized, project_path("outputs", "tables", "feasibility_normalized_retention.csv"))
data.table::fwrite(ratio, project_path("outputs", "tables", "feasibility_retention_ratio.csv"))

plot <- ggplot2::ggplot(
  curve,
  ggplot2::aes(age, opportunity_rate, color = credit_group)
) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::labs(
    title = "Feasibility check: synthetic opportunity curves",
    subtitle = "Synthetic data validate the pipeline; they are not evidence about Hollywood",
    x = "Performer age",
    y = "Annual probability of a principal credit",
    color = "IMDb credit class"
  ) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave(
  project_path("outputs", "figures", "feasibility_opportunity_curve.png"),
  plot,
  width = 9,
  height = 5.5,
  dpi = 160
)

cat("Feasibility pipeline completed. Synthetic outputs are in outputs/.\n")

