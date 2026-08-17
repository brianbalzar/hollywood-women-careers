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
if (!file.exists(database_path)) stop("Run scripts/03 and 04 first.")

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = database_path)
on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
DBI::dbExecute(con, "SET memory_limit = '4GB'")
DBI::dbExecute(con, "SET threads = 4")
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", sql_path(temp_dir)))
DBI::dbExecute(con, "SET preserve_insertion_order = false")

if (!"annual_opportunity" %in% DBI::dbListTables(con)) {
  stop("Run scripts/04_build_opportunity_panel.R first.")
}

message("Identifying established entry cohorts...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS career_entrants")
DBI::dbExecute(con, paste0(
  "CREATE TABLE career_entrants AS ",
  "WITH overall AS (",
  "SELECT * FROM annual_opportunity WHERE scope = 'overall'",
  "), first_credit AS (",
  "SELECT nconst, MIN(release_year) AS entry_year ",
  "FROM overall GROUP BY nconst",
  "), candidate AS (",
  "SELECT o.nconst, o.birth_year, o.death_year, o.credit_group, f.entry_year, ",
  "f.entry_year - o.birth_year AS entry_age, ",
  "COUNT(DISTINCT CASE WHEN o.release_year BETWEEN f.entry_year AND f.entry_year + 4 ",
  "THEN o.release_year END) AS early_credit_years, ",
  "SUM(CASE WHEN o.release_year BETWEEN f.entry_year AND f.entry_year + 4 ",
  "THEN o.role_count ELSE 0 END) AS early_roles ",
  "FROM overall o INNER JOIN first_credit f ON o.nconst = f.nconst ",
  "GROUP BY o.nconst, o.birth_year, o.death_year, o.credit_group, f.entry_year",
  ") ",
  "SELECT * FROM candidate ",
  "WHERE entry_year BETWEEN 2000 AND 2010 ",
  "AND entry_age BETWEEN 18 AND 35 ",
  "AND (death_year IS NULL OR death_year >= entry_year) ",
  "AND early_credit_years >= 2"
))

message("Locating the first five-year interruption in each established career...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS career_spells")
DBI::dbExecute(con, paste0(
  "CREATE TABLE career_spells AS ",
  "WITH ordered AS (",
  "SELECT a.nconst, a.release_year, ",
  "LEAD(a.release_year) OVER (PARTITION BY a.nconst ORDER BY a.release_year) AS next_credit_year ",
  "FROM annual_opportunity a INNER JOIN career_entrants e ON a.nconst = e.nconst ",
  "WHERE a.scope = 'overall'",
  "), qualifying_exit AS (",
  "SELECT o.nconst, MIN(o.release_year) AS event_year ",
  "FROM ordered o INNER JOIN career_entrants e ON o.nconst = e.nconst ",
  "WHERE (o.next_credit_year IS NULL OR o.next_credit_year - o.release_year > 5) ",
  "AND o.release_year + 5 <= 2025 ",
  "AND (e.death_year IS NULL OR e.death_year > o.release_year + 5) ",
  "GROUP BY o.nconst",
  "), assembled AS (",
  "SELECT e.*, q.event_year, ",
  "LEAST(COALESCE(e.death_year, 2025), 2025) AS censor_year ",
  "FROM career_entrants e LEFT JOIN qualifying_exit q ON e.nconst = q.nconst",
  ") ",
  "SELECT *, CASE WHEN event_year IS NOT NULL AND event_year <= censor_year THEN 1 ELSE 0 END AS event, ",
  "CASE WHEN event_year IS NOT NULL AND event_year <= censor_year ",
  "THEN event_year ELSE censor_year END AS exit_year, ",
  "CASE WHEN event_year IS NOT NULL AND event_year <= censor_year ",
  "THEN event_year ELSE censor_year END - birth_year AS exit_age ",
  "FROM assembled"
))

message("Expanding spells into a discrete-time age-hazard panel...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS career_hazard_panel")
DBI::dbExecute(con, paste0(
  "CREATE TABLE career_hazard_panel AS ",
  "SELECT s.nconst, s.credit_group, s.entry_year, s.entry_age, ",
  "s.early_credit_years, s.early_roles, s.event, s.exit_year, s.exit_age, ",
  "risk.year AS year, risk.year - s.birth_year AS age, ",
  "risk.year - s.entry_year AS years_since_entry, ",
  "CASE WHEN s.event = 1 AND risk.year = s.exit_year THEN 1 ELSE 0 END AS exit_event ",
  "FROM career_spells s, ",
  "LATERAL generate_series(s.entry_year, s.exit_year) AS risk(year) ",
  "WHERE risk.year - s.birth_year BETWEEN 18 AND 80"
))

spells_path <- file.path(processed_dir, "career_spells.parquet")
panel_path <- file.path(processed_dir, "career_hazard_panel.parquet")
for (path in c(spells_path, panel_path)) if (file.exists(path)) unlink(path)
DBI::dbExecute(con, sprintf(
  "COPY career_spells TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  sql_path(spells_path)
))
DBI::dbExecute(con, sprintf(
  "COPY career_hazard_panel TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  sql_path(panel_path)
))

summary <- DBI::dbGetQuery(con, paste0(
  "SELECT credit_group, COUNT(*) AS performers, SUM(event) AS observed_exits, ",
  "AVG(entry_age) AS mean_entry_age, AVG(early_roles) AS mean_early_roles, ",
  "AVG(exit_age) AS mean_exit_or_censor_age ",
  "FROM career_spells GROUP BY credit_group ORDER BY credit_group"
))
age_events <- DBI::dbGetQuery(con, paste0(
  "SELECT credit_group, age, COUNT(*) AS performer_years, SUM(exit_event) AS exits, ",
  "AVG(exit_event) AS exit_hazard ",
  "FROM career_hazard_panel GROUP BY credit_group, age ",
  "ORDER BY credit_group, age"
))

ensure_project_dirs()
data.table::fwrite(summary, project_path("outputs", "tables", "career_spell_summary.csv"))
data.table::fwrite(age_events, project_path("outputs", "tables", "career_exit_by_age.csv"))
print(summary)
cat("Career spells and discrete-time hazard panel completed.\n")
