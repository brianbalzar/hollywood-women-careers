source("R/paths.R")

required_packages <- c("data.table", "ggplot2", "scales")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Missing required packages: ", paste(missing_packages, collapse = ", "))
}

source_path <- file.path(
  billboard_cache_dir(),
  "billboard_hot100_1995_2025.csv"
)
if (!file.exists(source_path)) {
  stop("Matched Billboard data missing. Run scripts/12_match_billboard_artists.R first.")
}

hot100 <- data.table::fread(source_path)
hot100[, chart_date := data.table::as.IDate(chart_date)]
hot100[, chart_year := as.integer(format(chart_date, "%Y"))]
hot100[, age := chart_year - birth_year]
hot100 <- hot100[
  credit_group %in% c("women-coded", "men-coded") &
    age >= 15 & age <= 80
]

# An artist counts once per chart week even if several songs chart simultaneously.
artist_week <- unique(
  hot100[, .(person_id, artist, credit_group, birth_year, chart_date, chart_year, age)],
  by = c("person_id", "chart_date")
)

# Primary unit: one observation per identifiable solo artist in each chart year.
artist_year <- unique(
  artist_week[, .(person_id, artist, credit_group, birth_year, chart_year, age)],
  by = c("person_id", "chart_year")
)
artist_year[, period := data.table::fcase(
  chart_year <= 2004, "1995-2004",
  chart_year <= 2014, "2005-2014",
  default = "2015-2025"
)]
artist_year[, period := factor(
  period,
  levels = c("1995-2004", "2005-2014", "2015-2025")
)]

age_summary <- artist_year[, .(
  artist_years = .N,
  artists = data.table::uniqueN(person_id),
  mean_age = mean(age),
  median_age = as.numeric(stats::median(age)),
  age_q1 = as.numeric(stats::quantile(age, 0.25)),
  age_q3 = as.numeric(stats::quantile(age, 0.75)),
  share_35_plus = mean(age >= 35),
  share_40_plus = mean(age >= 40),
  share_50_plus = mean(age >= 50)
), by = .(period, credit_group)][order(period, credit_group)]

age_counts <- artist_year[, .(artist_years = .N), by = .(credit_group, age)]
age_counts[, within_group_share := artist_years / sum(artist_years), by = credit_group]

women_share <- artist_year[, .(artist_years = .N), by = .(age, credit_group)]
women_share <- data.table::dcast(
  women_share,
  age ~ credit_group,
  value.var = "artist_years",
  fill = 0
)
women_share[, total_artist_years := `women-coded` + `men-coded`]
women_share[, women_share := `women-coded` / total_artist_years]
data.table::setorder(women_share, age)

data.table::setorder(artist_year, person_id, chart_year)
artist_year[, next_chart_year := data.table::shift(chart_year, type = "lead"), by = person_id]
artist_year[, returned_within_5y := as.integer(
  !is.na(next_chart_year) & next_chart_year <= chart_year + 5L
)]
artist_year[, age_band_start := 5L * (age %/% 5L)]
artist_year[, age_band := paste0(age_band_start, "-", age_band_start + 4L)]
return_by_age <- artist_year[chart_year <= 2020, .(
  artist_years = .N,
  returned_artist_years = sum(returned_within_5y),
  return_rate = mean(returned_within_5y)
), by = .(credit_group, age_band_start, age_band)][order(credit_group, age_band_start)]
return_by_age[, return_se := sqrt(return_rate * (1 - return_rate) / artist_years)]
return_by_age[, `:=`(
  conf_low = pmax(0, return_rate - 1.96 * return_se),
  conf_high = pmin(1, return_rate + 1.96 * return_se)
)]

summarize_weighting <- function(data, weighting) {
  data[, .(
    observations = .N,
    artists = data.table::uniqueN(person_id),
    mean_age = mean(age),
    median_age = as.numeric(stats::median(age)),
    share_35_plus = mean(age >= 35),
    share_40_plus = mean(age >= 40),
    share_50_plus = mean(age >= 50)
  ), by = credit_group][, weighting := weighting][]
}

weighting_sensitivity <- data.table::rbindlist(list(
  summarize_weighting(artist_year, "unique artist-year"),
  summarize_weighting(artist_week, "unique artist-week")
))
data.table::setcolorder(weighting_sensitivity, c("weighting", "credit_group"))

coverage <- data.table::data.table(
  chart_start = min(artist_week$chart_date),
  chart_end = max(artist_week$chart_date),
  chart_weeks = data.table::uniqueN(hot100$chart_date),
  classified_solo_artists = data.table::uniqueN(artist_year$person_id),
  artist_years = nrow(artist_year),
  artist_weeks = nrow(artist_week)
)

ensure_project_dirs()
data.table::fwrite(age_summary, project_path("outputs", "tables", "billboard_age_summary.csv"))
data.table::fwrite(age_counts, project_path("outputs", "tables", "billboard_age_distribution.csv"))
data.table::fwrite(women_share, project_path("outputs", "tables", "billboard_women_share_by_age.csv"))
data.table::fwrite(return_by_age, project_path("outputs", "tables", "billboard_return_by_age.csv"))
data.table::fwrite(
  weighting_sensitivity,
  project_path("outputs", "tables", "billboard_weighting_sensitivity.csv")
)
data.table::fwrite(coverage, project_path("outputs", "tables", "billboard_analysis_coverage.csv"))

colors <- c("women-coded" = "#B23A6F", "men-coded" = "#315A8A")
group_labels <- c("women-coded" = "Women", "men-coded" = "Men")

p_box <- ggplot2::ggplot(
  artist_year,
  ggplot2::aes(credit_group, age, fill = credit_group)
) +
  ggplot2::geom_boxplot(width = 0.58, outlier.alpha = 0.12, outlier.size = 0.8) +
  ggplot2::facet_wrap(~period, nrow = 1) +
  ggplot2::scale_fill_manual(values = colors, labels = group_labels) +
  ggplot2::scale_x_discrete(labels = group_labels) +
  ggplot2::labs(
    title = "Age distribution of identifiable solo artists on the Hot 100",
    subtitle = "Each artist counts once in each calendar year in which they charted",
    x = NULL,
    y = "Artist age"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(legend.position = "none")

p_share <- ggplot2::ggplot(
  women_share[total_artist_years >= 20 & age <= 65],
  ggplot2::aes(age, women_share)
) +
  ggplot2::geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey60") +
  ggplot2::geom_line(linewidth = 1, color = colors[["women-coded"]]) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::labs(
    title = "Women's share of classified solo-artist chart participation",
    subtitle = "Unique artist-years; ages with at least 20 classified observations",
    x = "Artist age",
    y = "Women's share"
  ) +
  ggplot2::theme_minimal(base_size = 12)

p_return <- ggplot2::ggplot(
  return_by_age[artist_years >= 20 & age_band_start >= 15 & age_band_start <= 55],
  ggplot2::aes(age_band_start + 2, return_rate, color = credit_group)
) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = conf_low, ymax = conf_high),
    width = 0.55,
    alpha = 0.55
  ) +
  ggplot2::geom_point(size = 2) +
  ggplot2::scale_color_manual(values = colors, labels = group_labels) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::labs(
    title = "Probability of charting again within five years",
    subtitle = "Following a chart-active artist-year through 2020",
    x = "Artist age band midpoint",
    y = "Five-year chart return rate",
    color = "Artist classification"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(legend.position = "bottom")

ggplot2::ggsave(
  project_path("outputs", "figures", "billboard_age_boxplot.png"),
  p_box,
  width = 10,
  height = 5.5,
  dpi = 180
)
ggplot2::ggsave(
  project_path("outputs", "figures", "billboard_women_share_by_age.png"),
  p_share,
  width = 9,
  height = 5.5,
  dpi = 180
)
ggplot2::ggsave(
  project_path("outputs", "figures", "billboard_return_by_age.png"),
  p_return,
  width = 9,
  height = 5.5,
  dpi = 180
)

print(age_summary)
print(weighting_sensitivity)
cat("Billboard age and continuity analysis completed.\n")
