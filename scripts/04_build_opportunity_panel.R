source("R/paths.R")

required_packages <- c("DBI", "duckdb", "data.table")
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
processed_dir <- file.path(analysis_root, "processed")
temp_dir <- file.path(analysis_root, "duckdb_tmp")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(database_path)) {
  stop("Analytic database is missing. Run scripts/03_build_real_credits.R first.")
}

con <- DBI::dbConnect(
  duckdb::duckdb(shared_home = FALSE),
  dbdir = database_path
)
on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

DBI::dbExecute(con, "SET memory_limit = '4GB'")
DBI::dbExecute(con, "SET threads = 4")
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", sql_path(temp_dir)))
DBI::dbExecute(con, "SET preserve_insertion_order = false")

tables <- DBI::dbListTables(con)
if (!"credits_base" %in% tables) {
  stop("credits_base is missing. Run scripts/03_build_real_credits.R first.")
}

message("Collapsing credits to performer-year opportunity units...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS annual_opportunity")
DBI::dbExecute(con, paste0(
  "CREATE TABLE annual_opportunity AS ",
  "WITH credit_units AS (",
  "SELECT DISTINCT nconst, birth_year, death_year, credit_group, release_year, ",
  "medium, cast_rank, ",
  "CASE WHEN medium = 'television' ",
  "THEN 'tv:' || COALESCE(parentTconst, tconst) ",
  "ELSE 'film:' || tconst END AS opportunity_id ",
  "FROM credits_base ",
  "WHERE credit_group IN ('women-coded','men-coded') ",
  "AND release_year BETWEEN 1995 AND 2025 ",
  "AND release_year - birth_year BETWEEN 18 AND 80",
  "), scoped AS (",
  "SELECT nconst, birth_year, death_year, credit_group, release_year, ",
  "'overall' AS scope, opportunity_id, cast_rank FROM credit_units ",
  "UNION ALL ",
  "SELECT nconst, birth_year, death_year, credit_group, release_year, ",
  "medium AS scope, opportunity_id, cast_rank FROM credit_units",
  ") ",
  "SELECT nconst, birth_year, death_year, credit_group, release_year, scope, ",
  "COUNT(DISTINCT opportunity_id) AS role_count, ",
  "MIN(cast_rank) AS best_cast_rank ",
  "FROM scoped GROUP BY nconst, birth_year, death_year, credit_group, release_year, scope"
))

message("Constructing recently-active performer-year risk sets...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS opportunity_panel")
DBI::dbExecute(con, paste0(
  "CREATE TABLE opportunity_panel AS ",
  "WITH risk_years AS (",
  "SELECT DISTINCT a.nconst, a.birth_year, a.death_year, a.credit_group, a.scope, ",
  "risk.year AS year ",
  "FROM annual_opportunity a, ",
  "LATERAL generate_series(",
  "GREATEST(a.release_year + 1, 2000), ",
  "LEAST(a.release_year + 5, 2025)) AS risk(year) ",
  "WHERE a.release_year < 2025",
  ") ",
  "SELECT r.nconst, r.credit_group, r.scope, r.year, ",
  "r.year - r.birth_year AS age, ",
  "COALESCE(a.role_count, 0) AS role_count, ",
  "CASE WHEN a.role_count IS NULL THEN 0 ELSE 1 END AS any_role, ",
  "a.best_cast_rank ",
  "FROM risk_years r ",
  "LEFT JOIN annual_opportunity a ",
  "ON r.nconst = a.nconst AND r.scope = a.scope AND r.year = a.release_year ",
  "WHERE r.year - r.birth_year BETWEEN 18 AND 80 ",
  "AND (r.death_year IS NULL OR r.year <= r.death_year)"
))

message("Summarizing age-specific opportunity and normalized retention...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS opportunity_curve")
DBI::dbExecute(con, paste0(
  "CREATE TABLE opportunity_curve AS ",
  "SELECT credit_group, scope, age, COUNT(*) AS performer_years, ",
  "COUNT(DISTINCT nconst) AS performers_at_risk, ",
  "SUM(any_role) AS role_years, SUM(role_count) AS roles, ",
  "AVG(any_role) AS opportunity_rate, AVG(role_count) AS mean_roles ",
  "FROM opportunity_panel ",
  "GROUP BY credit_group, scope, age"
))

DBI::dbExecute(con, "DROP TABLE IF EXISTS normalized_retention")
DBI::dbExecute(con, paste0(
  "CREATE TABLE normalized_retention AS ",
  "WITH baseline AS (",
  "SELECT credit_group, scope, SUM(role_years) * 1.0 / SUM(performer_years) AS baseline_rate ",
  "FROM opportunity_curve WHERE age BETWEEN 30 AND 34 ",
  "GROUP BY credit_group, scope",
  ") ",
  "SELECT c.*, b.baseline_rate, c.opportunity_rate / b.baseline_rate AS normalized_retention ",
  "FROM opportunity_curve c INNER JOIN baseline b ",
  "ON c.credit_group = b.credit_group AND c.scope = b.scope"
))

panel_parquet <- file.path(processed_dir, "opportunity_panel.parquet")
curve_parquet <- file.path(processed_dir, "opportunity_curve.parquet")
for (path in c(panel_parquet, curve_parquet)) {
  if (file.exists(path)) unlink(path)
}
DBI::dbExecute(con, sprintf(
  "COPY opportunity_panel TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  sql_path(panel_parquet)
))
DBI::dbExecute(con, sprintf(
  "COPY normalized_retention TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  sql_path(curve_parquet)
))

curve <- DBI::dbGetQuery(con, paste0(
  "SELECT * FROM normalized_retention ",
  "ORDER BY scope, credit_group, age"
))
ratio <- DBI::dbGetQuery(con, paste0(
  "SELECT w.scope, w.age, w.normalized_retention AS women_retention, ",
  "m.normalized_retention AS men_retention, ",
  "w.normalized_retention / m.normalized_retention AS retention_ratio ",
  "FROM normalized_retention w INNER JOIN normalized_retention m ",
  "ON w.scope = m.scope AND w.age = m.age ",
  "WHERE w.credit_group = 'women-coded' AND m.credit_group = 'men-coded' ",
  "ORDER BY w.scope, w.age"
))
panel_summary <- DBI::dbGetQuery(con, paste0(
  "SELECT scope, credit_group, COUNT(*) AS performer_years, ",
  "COUNT(DISTINCT nconst) AS performers, SUM(any_role) AS role_years, ",
  "AVG(any_role) AS opportunity_rate ",
  "FROM opportunity_panel GROUP BY scope, credit_group ",
  "ORDER BY scope, credit_group"
))

ensure_project_dirs()
data.table::fwrite(curve, project_path("outputs", "tables", "opportunity_curve.csv"))
data.table::fwrite(ratio, project_path("outputs", "tables", "retention_ratio.csv"))
data.table::fwrite(panel_summary, project_path("outputs", "tables", "opportunity_panel_summary.csv"))

print(panel_summary)
cat("Opportunity panel and descriptive retention curves completed.\n")

