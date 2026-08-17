source("R/paths.R")

required_packages <- c("DBI", "duckdb", "data.table", "ggplot2", "scales")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Missing required packages: ", paste(missing_packages, collapse = ", "))
}

sql_path <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  gsub("'", "''", path, fixed = TRUE)
}

analysis_root <- dirname(imdb_cache_dir())
database_path <- file.path(analysis_root, "hollywood.duckdb")
temp_dir <- file.path(analysis_root, "duckdb_tmp")
if (!file.exists(database_path)) {
  stop("Analytic database is missing. Run scripts/03 and 04 first.")
}

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = database_path)
on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
DBI::dbExecute(con, "SET memory_limit = '4GB'")
DBI::dbExecute(con, "SET threads = 4")
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", sql_path(temp_dir)))

needed <- c("annual_opportunity", "normalized_retention")
if (!all(needed %in% DBI::dbListTables(con))) {
  stop("Opportunity tables are missing. Run scripts/04_build_opportunity_panel.R first.")
}

message("Calculating five-year forward career continuity...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS forward_continuity")
DBI::dbExecute(con, paste0(
  "CREATE TABLE forward_continuity AS ",
  "WITH eligible AS (",
  "SELECT a.*, a.release_year - a.birth_year AS age ",
  "FROM annual_opportunity a ",
  "WHERE a.release_year BETWEEN 2000 AND 2020 ",
  "AND a.release_year - a.birth_year BETWEEN 18 AND 75 ",
  "AND (a.death_year IS NULL OR a.death_year > a.release_year + 5)",
  "), person_year AS (",
  "SELECT e.nconst, e.credit_group, e.scope, e.release_year, e.age, ",
  "CASE WHEN COUNT(f.release_year) > 0 THEN 1 ELSE 0 END AS retained_within_5y ",
  "FROM eligible e LEFT JOIN annual_opportunity f ",
  "ON e.nconst = f.nconst AND e.scope = f.scope ",
  "AND f.release_year BETWEEN e.release_year + 1 AND e.release_year + 5 ",
  "GROUP BY e.nconst, e.credit_group, e.scope, e.release_year, e.age",
  ") ",
  "SELECT credit_group, scope, age, COUNT(*) AS credited_performer_years, ",
  "SUM(retained_within_5y) AS retained_performer_years, ",
  "AVG(retained_within_5y) AS forward_continuity_rate ",
  "FROM person_year GROUP BY credit_group, scope, age"
))

forward <- DBI::dbGetQuery(con, paste0(
  "WITH baseline AS (",
  "SELECT credit_group, scope, ",
  "SUM(retained_performer_years) * 1.0 / SUM(credited_performer_years) AS baseline_rate ",
  "FROM forward_continuity WHERE age BETWEEN 30 AND 34 ",
  "GROUP BY credit_group, scope",
  ") ",
  "SELECT f.*, b.baseline_rate, ",
  "f.forward_continuity_rate / b.baseline_rate AS normalized_continuity ",
  "FROM forward_continuity f INNER JOIN baseline b ",
  "ON f.credit_group = b.credit_group AND f.scope = b.scope ",
  "ORDER BY f.scope, f.credit_group, f.age"
))
forward <- data.table::as.data.table(forward)

forward_ratio <- data.table::dcast(
  data.table::as.data.table(forward),
  scope + age ~ credit_group,
  value.var = "normalized_continuity"
)
forward_ratio[, continuity_ratio := `women-coded` / `men-coded`]

message("Calculating women-coded share of observed opportunity units...")
role_share <- DBI::dbGetQuery(con, paste0(
  "WITH age_roles AS (",
  "SELECT scope, release_year - birth_year AS age, credit_group, ",
  "SUM(role_count) AS roles ",
  "FROM annual_opportunity ",
  "WHERE release_year BETWEEN 2000 AND 2025 ",
  "AND release_year - birth_year BETWEEN 18 AND 80 ",
  "GROUP BY scope, age, credit_group",
  "), totals AS (",
  "SELECT scope, age, SUM(roles) AS total_roles FROM age_roles GROUP BY scope, age",
  ") ",
  "SELECT a.scope, a.age, a.roles AS women_coded_roles, t.total_roles, ",
  "a.roles * 1.0 / t.total_roles AS women_coded_share ",
  "FROM age_roles a INNER JOIN totals t USING (scope, age) ",
  "WHERE a.credit_group = 'women-coded' ORDER BY a.scope, a.age"
))
role_share <- data.table::as.data.table(role_share)

message("Calculating post-peak career tapering among still-credited performers...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS career_taper_panel")
DBI::dbExecute(con, paste0(
  "CREATE TABLE career_taper_panel AS ",
  "WITH overall AS (",
  "SELECT nconst, birth_year, credit_group, release_year, role_count ",
  "FROM annual_opportunity WHERE scope = 'overall'",
  "), bounds AS (",
  "SELECT nconst, MIN(birth_year) AS birth_year, MIN(credit_group) AS credit_group, ",
  "MIN(release_year) AS first_year, MAX(release_year) AS last_year ",
  "FROM overall GROUP BY nconst",
  "), calendar AS (",
  "SELECT b.nconst, b.birth_year, b.credit_group, years.year AS release_year ",
  "FROM bounds b, LATERAL generate_series(b.first_year, b.last_year) AS years(year)",
  "), filled AS (",
  "SELECT c.*, COALESCE(o.role_count, 0) AS role_count ",
  "FROM calendar c LEFT JOIN overall o ",
  "ON c.nconst = o.nconst AND c.release_year = o.release_year",
  "), rolling AS (",
  "SELECT *, SUM(role_count) OVER (",
  "PARTITION BY nconst ORDER BY release_year ROWS BETWEEN 4 PRECEDING AND CURRENT ROW",
  ") AS rolling_5y_roles FROM filled",
  "), peaks AS (",
  "SELECT nconst, MAX(rolling_5y_roles) AS peak_5y_roles ",
  "FROM rolling GROUP BY nconst",
  "), peak_timing AS (",
  "SELECT r.nconst, p.peak_5y_roles, MIN(r.release_year) AS peak_window_end ",
  "FROM rolling r INNER JOIN peaks p ON r.nconst = p.nconst ",
  "AND r.rolling_5y_roles = p.peak_5y_roles ",
  "GROUP BY r.nconst, p.peak_5y_roles",
  ") ",
  "SELECT r.nconst, r.credit_group, r.birth_year, r.release_year, ",
  "r.release_year - r.birth_year AS age, r.role_count AS current_year_roles, ",
  "r.rolling_5y_roles AS current_5y_roles, p.peak_5y_roles, p.peak_window_end, ",
  "r.rolling_5y_roles * 1.0 / p.peak_5y_roles AS taper_ratio, ",
  "CASE WHEN r.rolling_5y_roles * 1.0 / p.peak_5y_roles <= 0.25 THEN 1 ELSE 0 END ",
  "AS severe_taper ",
  "FROM rolling r INNER JOIN peak_timing p ON r.nconst = p.nconst ",
  "WHERE r.role_count > 0 AND p.peak_5y_roles >= 4 ",
  "AND r.release_year > p.peak_window_end ",
  "AND r.release_year BETWEEN 2000 AND 2025 ",
  "AND r.release_year - r.birth_year BETWEEN 18 AND 80"
))

DBI::dbExecute(con, "DROP TABLE IF EXISTS career_taper_by_age")
DBI::dbExecute(con, paste0(
  "CREATE TABLE career_taper_by_age AS ",
  "SELECT credit_group, age, COUNT(*) AS credited_performer_years, ",
  "COUNT(DISTINCT nconst) AS credited_performers, ",
  "MEDIAN(taper_ratio) AS median_taper_ratio, ",
  "AVG(severe_taper) AS severe_taper_share ",
  "FROM career_taper_panel GROUP BY credit_group, age"
))

taper <- data.table::as.data.table(DBI::dbGetQuery(con, paste0(
  "SELECT * FROM career_taper_by_age ORDER BY credit_group, age"
)))

helen_taper <- data.table::as.data.table(DBI::dbGetQuery(con, paste0(
  "SELECT p.*, n.primaryName ",
  "FROM career_taper_panel p INNER JOIN (",
  "SELECT DISTINCT nconst, primaryName FROM credits_base",
  ") n ON p.nconst = n.nconst ",
  "WHERE lower(n.primaryName) = 'helen slater' ",
  "ORDER BY p.release_year"
)))

opportunity <- data.table::fread(
  project_path("outputs", "tables", "opportunity_curve.csv")
)
retention_ratio <- data.table::fread(
  project_path("outputs", "tables", "retention_ratio.csv")
)

ensure_project_dirs()
data.table::fwrite(forward, project_path("outputs", "tables", "forward_continuity.csv"))
data.table::fwrite(
  forward_ratio,
  project_path("outputs", "tables", "forward_continuity_ratio.csv")
)
data.table::fwrite(role_share, project_path("outputs", "tables", "women_role_share.csv"))
data.table::fwrite(taper, project_path("outputs", "tables", "career_taper_by_age.csv"))
data.table::fwrite(
  helen_taper,
  project_path("outputs", "tables", "helen_slater_taper.csv")
)

colors <- c("women-coded" = "#B23A6F", "men-coded" = "#315A8A")

p1 <- ggplot2::ggplot(
  opportunity[scope == "overall"],
  ggplot2::aes(age, opportunity_rate, color = credit_group)
) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::scale_color_manual(values = colors) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::coord_cartesian(xlim = c(20, 75)) +
  ggplot2::labs(
    title = "Annual screen opportunity among recently active performers",
    subtitle = "Principal film credit or television series participation; five-year lookback",
    x = "Performer age", y = "Probability of a credit that year", color = "IMDb credit class"
  ) +
  ggplot2::theme_minimal(base_size = 12)

p2 <- ggplot2::ggplot(
  forward[scope != "overall"],
  ggplot2::aes(age, forward_continuity_rate, color = credit_group)
) +
  ggplot2::geom_line(linewidth = 0.9) +
  ggplot2::facet_wrap(~scope) +
  ggplot2::scale_color_manual(values = colors) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::coord_cartesian(xlim = c(20, 70)) +
  ggplot2::labs(
    title = "Probability of another credit within five years",
    subtitle = "Following a credited performer-year, with complete five-year follow-up",
    x = "Age at current credit", y = "Five-year continuity", color = "IMDb credit class"
  ) +
  ggplot2::theme_minimal(base_size = 12)

p3 <- ggplot2::ggplot(
  role_share,
  ggplot2::aes(age, women_coded_share, color = scope)
) +
  ggplot2::geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey60") +
  ggplot2::geom_line(linewidth = 0.95) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::coord_cartesian(xlim = c(18, 80), ylim = c(0, 0.65)) +
  ggplot2::labs(
    title = "Share of principal opportunities credited to women-coded performers",
    subtitle = "Denominator: opportunities credited to women-coded plus men-coded performers",
    x = "Performer age", y = "Women-coded opportunity share", color = "Scope"
  ) +
  ggplot2::theme_minimal(base_size = 12)

p4 <- ggplot2::ggplot(
  taper[age >= 25 & age <= 75],
  ggplot2::aes(age, severe_taper_share, color = credit_group)
) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::scale_color_manual(values = colors) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::labs(
    title = "Still working, but at no more than one quarter of peak volume",
    subtitle = "Credited post-peak performer-years; trailing five-year volume versus personal observed peak",
    x = "Performer age", y = "Share experiencing severe tapering", color = "IMDb credit class"
  ) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave(
  project_path("outputs", "figures", "annual_opportunity_by_age.png"),
  p1, width = 9, height = 5.5, dpi = 180
)
ggplot2::ggsave(
  project_path("outputs", "figures", "forward_continuity_by_age.png"),
  p2, width = 10, height = 5.5, dpi = 180
)
ggplot2::ggsave(
  project_path("outputs", "figures", "women_role_share_by_age.png"),
  p3, width = 9, height = 5.5, dpi = 180
)
ggplot2::ggsave(
  project_path("outputs", "figures", "career_taper_by_age.png"),
  p4, width = 9, height = 5.5, dpi = 180
)

cat("Descriptive tables and figures completed.\n")
