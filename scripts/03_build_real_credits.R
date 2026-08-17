source("R/paths.R")
source("R/imdb_helpers.R")

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

cache <- imdb_cache_dir()
imdb_files <- required_imdb_files()
source_files <- stats::setNames(file.path(cache, imdb_files), names(imdb_files))
missing_files <- source_files[!file.exists(source_files)]
if (length(missing_files)) {
  stop(
    "Missing IMDb files. Run scripts/01_download_imdb.R first:\n",
    paste(missing_files, collapse = "\n"),
    call. = FALSE
  )
}

analysis_root <- dirname(cache)
processed_dir <- file.path(analysis_root, "processed")
temp_dir <- file.path(analysis_root, "duckdb_tmp")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

database_path <- file.path(analysis_root, "hollywood.duckdb")
credits_parquet <- file.path(processed_dir, "credits_base.parquet")

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = database_path)
on.exit({
  try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
}, add = TRUE)

DBI::dbExecute(con, "SET memory_limit = '4GB'")
DBI::dbExecute(con, "SET threads = 4")
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", sql_path(temp_dir)))
DBI::dbExecute(con, "SET preserve_insertion_order = false")

read_csv_sql <- function(path, columns) {
  column_sql <- paste(
    sprintf("'%s': 'VARCHAR'", names(columns)),
    collapse = ", "
  )
  sprintf(
    paste0(
      "read_csv('%s', delim='\\t', header=true, nullstr='\\\\N', ",
      "quote='', columns={%s}, compression='gzip')"
    ),
    sql_path(path),
    column_sql
  )
}

schemas <- list(
  names = c(
    nconst = "VARCHAR", primaryName = "VARCHAR", birthYear = "VARCHAR",
    deathYear = "VARCHAR", primaryProfession = "VARCHAR",
    knownForTitles = "VARCHAR"
  ),
  titles = c(
    tconst = "VARCHAR", titleType = "VARCHAR", primaryTitle = "VARCHAR",
    originalTitle = "VARCHAR", isAdult = "VARCHAR", startYear = "VARCHAR",
    endYear = "VARCHAR", runtimeMinutes = "VARCHAR", genres = "VARCHAR"
  ),
  principals = c(
    tconst = "VARCHAR", ordering = "VARCHAR", nconst = "VARCHAR",
    category = "VARCHAR", job = "VARCHAR", characters = "VARCHAR"
  ),
  akas = c(
    titleId = "VARCHAR", ordering = "VARCHAR", title = "VARCHAR",
    region = "VARCHAR", language = "VARCHAR", types = "VARCHAR",
    attributes = "VARCHAR", isOriginalTitle = "VARCHAR"
  ),
  episodes = c(
    tconst = "VARCHAR", parentTconst = "VARCHAR", seasonNumber = "VARCHAR",
    episodeNumber = "VARCHAR"
  ),
  ratings = c(
    tconst = "VARCHAR", averageRating = "VARCHAR", numVotes = "VARCHAR"
  )
)

message("Reading and filtering title metadata...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS basics_work")
DBI::dbExecute(con, sprintf(
  paste0(
    "CREATE TABLE basics_work AS ",
    "SELECT tconst, titleType, primaryTitle, originalTitle, ",
    "TRY_CAST(isAdult AS INTEGER) AS is_adult, ",
    "TRY_CAST(startYear AS INTEGER) AS release_year, genres ",
    "FROM %s ",
    "WHERE titleType IN ('movie','tvMovie','tvEpisode','tvSeries','tvMiniSeries')"
  ),
  read_csv_sql(source_files[["titles"]], schemas$titles)
))

DBI::dbExecute(con, "DROP TABLE IF EXISTS episodes_work")
DBI::dbExecute(con, sprintf(
  paste0(
    "CREATE TABLE episodes_work AS ",
    "SELECT tconst, parentTconst, TRY_CAST(seasonNumber AS INTEGER) AS season_number, ",
    "TRY_CAST(episodeNumber AS INTEGER) AS episode_number FROM %s"
  ),
  read_csv_sql(source_files[["episodes"]], schemas$episodes)
))

DBI::dbExecute(con, "DROP TABLE IF EXISTS us_titles")
DBI::dbExecute(con, sprintf(
  "CREATE TABLE us_titles AS SELECT DISTINCT titleId AS tconst FROM %s WHERE region = 'US'",
  read_csv_sql(source_files[["akas"]], schemas$akas)
))

DBI::dbExecute(con, "DROP TABLE IF EXISTS titles_scope")
DBI::dbExecute(con, paste0(
  "CREATE TABLE titles_scope AS ",
  "SELECT b.tconst, b.titleType, b.primaryTitle, b.originalTitle, b.release_year, ",
  "e.parentTconst, e.season_number, e.episode_number, ",
  "COALESCE(b.genres, parent.genres) AS effective_genres, ",
  "CASE WHEN b.titleType IN ('movie','tvMovie') THEN 'film' ELSE 'television' END AS medium ",
  "FROM basics_work b ",
  "LEFT JOIN episodes_work e ON b.tconst = e.tconst ",
  "LEFT JOIN basics_work parent ON e.parentTconst = parent.tconst ",
  "LEFT JOIN us_titles self_us ON b.tconst = self_us.tconst ",
  "LEFT JOIN us_titles parent_us ON e.parentTconst = parent_us.tconst ",
  "WHERE b.titleType IN ('movie','tvMovie','tvEpisode') ",
  "AND b.release_year BETWEEN 1995 AND 2025 ",
  "AND COALESCE(b.is_adult, 0) = 0 ",
  "AND (self_us.tconst IS NOT NULL OR parent_us.tconst IS NOT NULL) ",
  "AND NOT regexp_matches(",
  "COALESCE(b.genres, parent.genres, ''), ",
  "'(^|,)(Documentary|News|Reality-TV|Talk-Show|Game-Show|Adult)(,|$)')"
))

message("Reading principal cast and assigning within-title cast rank...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS cast_scope")
DBI::dbExecute(con, sprintf(
  paste0(
    "CREATE TABLE cast_scope AS ",
    "SELECT p.tconst, TRY_CAST(p.ordering AS INTEGER) AS ordering, p.nconst, ",
    "p.category, p.characters, ",
    "ROW_NUMBER() OVER (PARTITION BY p.tconst ORDER BY TRY_CAST(p.ordering AS INTEGER)) AS cast_rank ",
    "FROM %s p INNER JOIN titles_scope t ON p.tconst = t.tconst ",
    "WHERE p.category IN ('actor','actress')"
  ),
  read_csv_sql(source_files[["principals"]], schemas$principals)
))

message("Reading performer birth/death years and title ratings...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS people_scope")
DBI::dbExecute(con, sprintf(
  paste0(
    "CREATE TABLE people_scope AS ",
    "SELECT n.nconst, n.primaryName, TRY_CAST(n.birthYear AS INTEGER) AS birth_year, ",
    "TRY_CAST(n.deathYear AS INTEGER) AS death_year ",
    "FROM %s n INNER JOIN (SELECT DISTINCT nconst FROM cast_scope) c ON n.nconst = c.nconst"
  ),
  read_csv_sql(source_files[["names"]], schemas$names)
))

DBI::dbExecute(con, "DROP TABLE IF EXISTS ratings_scope")
DBI::dbExecute(con, sprintf(
  paste0(
    "CREATE TABLE ratings_scope AS ",
    "SELECT r.tconst, TRY_CAST(r.averageRating AS DOUBLE) AS average_rating, ",
    "TRY_CAST(r.numVotes AS BIGINT) AS num_votes ",
    "FROM %s r INNER JOIN titles_scope t ON r.tconst = t.tconst"
  ),
  read_csv_sql(source_files[["ratings"]], schemas$ratings)
))

message("Building performer classification and analytic credit table...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS performer_groups")
DBI::dbExecute(con, paste0(
  "CREATE TABLE performer_groups AS ",
  "SELECT nconst, COUNT(*) AS classified_credits, ",
  "AVG(CASE WHEN category = 'actress' THEN 1.0 ELSE 0.0 END) AS actress_share, ",
  "CASE ",
  "WHEN AVG(CASE WHEN category = 'actress' THEN 1.0 ELSE 0.0 END) >= 0.90 THEN 'women-coded' ",
  "WHEN AVG(CASE WHEN category = 'actress' THEN 1.0 ELSE 0.0 END) <= 0.10 THEN 'men-coded' ",
  "ELSE 'ambiguous' END AS credit_group ",
  "FROM cast_scope GROUP BY nconst"
))

DBI::dbExecute(con, "DROP TABLE IF EXISTS credits_base")
DBI::dbExecute(con, paste0(
  "CREATE TABLE credits_base AS ",
  "SELECT c.tconst, c.nconst, p.primaryName, c.category, c.cast_rank, c.characters, ",
  "t.titleType, t.primaryTitle, t.originalTitle, t.release_year, t.parentTconst, ",
  "t.season_number, t.episode_number, t.effective_genres, t.medium, ",
  "p.birth_year, p.death_year, t.release_year - p.birth_year AS age, ",
  "g.credit_group, g.actress_share, g.classified_credits, ",
  "r.average_rating, r.num_votes ",
  "FROM cast_scope c ",
  "INNER JOIN titles_scope t ON c.tconst = t.tconst ",
  "INNER JOIN people_scope p ON c.nconst = p.nconst ",
  "INNER JOIN performer_groups g ON c.nconst = g.nconst ",
  "LEFT JOIN ratings_scope r ON c.tconst = r.tconst ",
  "WHERE p.birth_year IS NOT NULL ",
  "AND t.release_year - p.birth_year BETWEEN 0 AND 100"
))

if (file.exists(credits_parquet)) unlink(credits_parquet)
DBI::dbExecute(con, sprintf(
  "COPY credits_base TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  sql_path(credits_parquet)
))

diagnostics <- DBI::dbGetQuery(con, paste0(
  "SELECT release_year, medium, credit_group, ",
  "COUNT(*) AS principal_credits, COUNT(DISTINCT nconst) AS performers, ",
  "COUNT(DISTINCT tconst) AS titles, ",
  "SUM(CASE WHEN birth_year IS NULL THEN 1 ELSE 0 END) AS missing_birth_year ",
  "FROM credits_base GROUP BY release_year, medium, credit_group ",
  "ORDER BY release_year, medium, credit_group"
))
data.table::fwrite(
  diagnostics,
  project_path("outputs", "tables", "real_data_coverage.csv")
)

summary <- DBI::dbGetQuery(con, paste0(
  "SELECT COUNT(*) AS credits, COUNT(DISTINCT nconst) AS performers, ",
  "COUNT(DISTINCT tconst) AS titles, MIN(release_year) AS first_year, ",
  "MAX(release_year) AS last_year FROM credits_base"
))
summary$parquet_path <- normalizePath(credits_parquet, winslash = "/")
summary$database_path <- normalizePath(database_path, winslash = "/")
data.table::fwrite(
  summary,
  project_path("outputs", "tables", "real_data_build_summary.csv")
)

print(summary)
cat("Real-data credit build completed.\n")
