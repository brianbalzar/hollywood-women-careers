source("R/paths.R")

required_packages <- c("DBI", "duckdb", "data.table")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Missing required packages: ", paste(missing_packages, collapse = ", "))
}

analysis_root <- dirname(imdb_cache_dir())
database_path <- file.path(analysis_root, "hollywood.duckdb")
if (!file.exists(database_path)) stop("Analytic database is missing.")

checks <- list()
add_check <- function(name, passed, detail) {
  checks[[length(checks) + 1L]] <<- data.table::data.table(
    check = name,
    passed = isTRUE(passed),
    detail = as.character(detail)
  )
}

manifest_path <- project_path("data", "raw", "imdb_manifest.csv")
manifest <- data.table::fread(manifest_path)
add_check(
  "six source datasets recorded",
  nrow(manifest) == 6L && all(manifest$bytes > 0),
  paste(nrow(manifest), "files;", format(sum(manifest$bytes), big.mark = ","), "compressed bytes")
)

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = database_path)
on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

required_tables <- c(
  "credits_base", "annual_opportunity", "opportunity_panel",
  "career_spells", "career_hazard_panel", "career_taper_panel",
  "career_taper_by_age"
)
tables <- DBI::dbListTables(con)
add_check(
  "required analytic tables present",
  all(required_tables %in% tables),
  paste(intersect(required_tables, tables), collapse = ", ")
)

credit_summary <- DBI::dbGetQuery(con, paste0(
  "SELECT COUNT(*) AS n, MIN(age) AS min_age, MAX(age) AS max_age, ",
  "SUM(CASE WHEN birth_year IS NULL THEN 1 ELSE 0 END) AS missing_birth ",
  "FROM credits_base"
))
add_check(
  "credit table has valid age and birth fields",
  credit_summary$n > 1000000 && credit_summary$min_age >= 0 &&
    credit_summary$max_age <= 100 && credit_summary$missing_birth == 0,
  paste(format(credit_summary$n, big.mark = ","), "credits; ages", credit_summary$min_age, "to", credit_summary$max_age)
)

panel_summary <- DBI::dbGetQuery(con, paste0(
  "SELECT COUNT(*) AS n, MIN(age) AS min_age, MAX(age) AS max_age, ",
  "MIN(any_role) AS min_outcome, MAX(any_role) AS max_outcome ",
  "FROM opportunity_panel"
))
add_check(
  "opportunity panel outcomes and ages valid",
  panel_summary$n > 1000000 && panel_summary$min_age >= 18 &&
    panel_summary$max_age <= 80 && panel_summary$min_outcome == 0 &&
    panel_summary$max_outcome == 1,
  paste(format(panel_summary$n, big.mark = ","), "performer-years; ages", panel_summary$min_age, "to", panel_summary$max_age)
)

spell_audit <- DBI::dbGetQuery(con, paste0(
  "SELECT COUNT(*) AS n, ",
  "SUM(CASE WHEN exit_year < entry_year THEN 1 ELSE 0 END) AS reversed, ",
  "SUM(CASE WHEN death_year IS NOT NULL AND death_year < entry_year THEN 1 ELSE 0 END) AS death_before_entry, ",
  "SUM(CASE WHEN event NOT IN (0,1) THEN 1 ELSE 0 END) AS invalid_event ",
  "FROM career_spells"
))
add_check(
  "career spell chronology valid",
  spell_audit$n > 10000 && spell_audit$reversed == 0 &&
    spell_audit$death_before_entry == 0 && spell_audit$invalid_event == 0,
  paste(format(spell_audit$n, big.mark = ","), "spells;", spell_audit$reversed, "reversed")
)

taper_audit <- DBI::dbGetQuery(con, paste0(
  "SELECT COUNT(*) AS n, MIN(taper_ratio) AS min_ratio, ",
  "MAX(taper_ratio) AS max_ratio, MIN(peak_5y_roles) AS min_peak, ",
  "SUM(CASE WHEN release_year <= peak_window_end THEN 1 ELSE 0 END) AS pre_peak, ",
  "SUM(CASE WHEN current_year_roles <= 0 THEN 1 ELSE 0 END) AS uncredited ",
  "FROM career_taper_panel"
))
add_check(
  "career taper panel has valid post-peak ratios",
  taper_audit$n > 10000 && taper_audit$min_ratio > 0 &&
    taper_audit$max_ratio <= 1 && taper_audit$min_peak >= 4 &&
    taper_audit$pre_peak == 0 && taper_audit$uncredited == 0,
  paste(format(taper_audit$n, big.mark = ","), "credited post-peak performer-years; ratios",
        round(taper_audit$min_ratio, 3), "to", round(taper_audit$max_ratio, 3))
)

required_outputs <- c(
  "opportunity_curve.csv", "retention_ratio.csv", "forward_continuity.csv",
  "women_role_share.csv", "adjusted_exit_hazard_ratio.csv",
  "role_share_change_points.csv", "two_change_point_summary.csv",
  "gap_definition_sensitivity.csv", "explicit_character_family_labels.csv",
  "career_taper_by_age.csv", "helen_slater_taper.csv",
  "billboard_match_coverage.csv", "billboard_analysis_coverage.csv",
  "billboard_age_summary.csv", "billboard_women_share_by_age.csv",
  "billboard_return_by_age.csv", "billboard_weighting_sensitivity.csv"
)
output_paths <- project_path("outputs", "tables", required_outputs)
add_check(
  "required result tables written",
  all(file.exists(output_paths)) && all(file.info(output_paths)$size > 0),
  paste(sum(file.exists(output_paths)), "of", length(output_paths), "present")
)

change_points <- data.table::fread(
  project_path("outputs", "tables", "role_share_change_points.csv")
)
add_check(
  "bootstrap intervals and estimates valid",
  all(change_points$bootstrap_conf_low <= change_points$estimated_change_age) &&
    all(change_points$estimated_change_age <= change_points$bootstrap_conf_high) &&
    all(change_points$release_year_bootstrap_reps >= 500),
  paste(change_points$scope, change_points$estimated_change_age, collapse = "; ")
)

billboard_match <- data.table::fread(
  project_path("outputs", "tables", "billboard_match_coverage.csv")
)
binary_chart_share <- billboard_match[
  credit_group %in% c("women-coded", "men-coded"),
  sum(chart_row_share)
]
add_check(
  "Billboard solo-artist classification coverage reported",
  binary_chart_share > 0.45 && binary_chart_share < 0.80,
  paste0(round(100 * binary_chart_share, 1), "% of chart rows classified to binary-coded solo artists")
)

billboard_age <- data.table::fread(
  project_path("outputs", "tables", "billboard_age_summary.csv")
)
add_check(
  "Billboard age summaries valid",
  nrow(billboard_age) == 6L &&
    all(billboard_age$median_age >= 15 & billboard_age$median_age <= 80) &&
    all(billboard_age$share_35_plus >= 0 & billboard_age$share_35_plus <= 1),
  paste(sum(billboard_age$artist_years), "classified solo artist-years")
)

billboard_return <- data.table::fread(
  project_path("outputs", "tables", "billboard_return_by_age.csv")
)
add_check(
  "Billboard five-year returns valid",
  all(billboard_return$return_rate >= 0 & billboard_return$return_rate <= 1) &&
    all(billboard_return$conf_low >= 0) && all(billboard_return$conf_high <= 1),
  paste(nrow(billboard_return), "classification-by-age-band estimates")
)

validation <- data.table::rbindlist(checks)
ensure_project_dirs()
data.table::fwrite(
  validation,
  project_path("outputs", "tables", "validation_checks.csv")
)
print(validation)

if (any(!validation$passed)) {
  stop("One or more validation checks failed.", call. = FALSE)
}
cat("All analysis validation checks passed.\n")
