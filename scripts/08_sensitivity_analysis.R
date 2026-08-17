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

cluster_vcov_glm <- function(model, cluster) {
  x <- stats::model.matrix(model)
  mu <- stats::fitted(model)
  residual <- stats::model.response(stats::model.frame(model)) - mu
  weights <- pmax(mu * (1 - mu), 1e-10)
  bread <- solve(crossprod(x, x * weights))
  scores <- rowsum(x * residual, cluster, reorder = FALSE)
  meat <- crossprod(scores)
  n <- nrow(x)
  p <- ncol(x)
  g <- nrow(scores)
  correction <- (g / (g - 1)) * ((n - 1) / (n - p))
  bread %*% meat %*% bread * correction
}

marginal_prediction <- function(model, vcov_cluster, entrants, target_age, group) {
  nd <- entrants[entry_age <= target_age]
  nd[, `:=`(
    age = target_age,
    credit_group = factor(group, levels = c("men-coded", "women-coded"))
  )]
  x <- stats::model.matrix(
    stats::delete.response(stats::terms(model)),
    nd,
    contrasts.arg = model$contrasts
  )
  probability <- stats::plogis(drop(x %*% stats::coef(model)))
  estimate <- mean(probability)
  gradient <- colMeans(x * (probability * (1 - probability)))
  list(estimate = estimate, gradient = gradient)
}

fit_two_knots <- function(age_counts, first_knots = 25:35, second_knots = 38:48) {
  totals <- age_counts[, .(roles = sum(roles)), by = .(age, credit_group)]
  wide <- data.table::dcast(
    totals,
    age ~ credit_group,
    value.var = "roles",
    fill = 0
  )
  candidates <- data.table::CJ(knot_1 = first_knots, knot_2 = second_knots)[
    knot_2 - knot_1 >= 5
  ]
  best_bic <- Inf
  best <- NULL
  for (i in seq_len(nrow(candidates))) {
    knot_1 <- candidates$knot_1[i]
    knot_2 <- candidates$knot_2[i]
    wide[, `:=`(
      hinge_1 = pmax(age - knot_1, 0),
      hinge_2 = pmax(age - knot_2, 0)
    )]
    model <- stats::glm(
      cbind(`women-coded`, `men-coded`) ~ age + hinge_1 + hinge_2,
      data = wide,
      family = stats::binomial()
    )
    model_bic <- stats::BIC(model)
    if (model_bic < best_bic) {
      best_bic <- model_bic
      best <- list(knot_1 = knot_1, knot_2 = knot_2, model = model, bic = model_bic)
    }
  }
  best
}

analysis_root <- dirname(imdb_cache_dir())
database_path <- file.path(analysis_root, "hollywood.duckdb")
temp_dir <- file.path(analysis_root, "duckdb_tmp")
if (!file.exists(database_path)) stop("Run scripts/03 through 07 first.")

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = database_path)
on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
DBI::dbExecute(con, "SET memory_limit = '4GB'")
DBI::dbExecute(con, "SET threads = 4")
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", sql_path(temp_dir)))

message("Estimating two-breakpoint role-share curves...")
age_year_counts <- data.table::as.data.table(DBI::dbGetQuery(con, paste0(
  "SELECT scope, release_year, release_year - birth_year AS age, credit_group, ",
  "SUM(role_count) AS roles FROM annual_opportunity ",
  "WHERE release_year BETWEEN 2000 AND 2025 ",
  "AND release_year - birth_year BETWEEN 20 AND 65 ",
  "GROUP BY scope, release_year, age, credit_group"
)))

one_knot <- data.table::fread(
  project_path("outputs", "tables", "role_share_change_points.csv")
)
set.seed(20260818)
bootstrap_reps <- 300L
two_knot_results <- list()

for (scope_name in c("overall", "film", "television")) {
  scope_data <- age_year_counts[scope == scope_name]
  best <- fit_two_knots(scope_data)
  years <- sort(unique(scope_data$release_year))
  boot <- replicate(bootstrap_reps, {
    sampled <- sample(years, length(years), replace = TRUE)
    frequencies <- data.table::data.table(release_year = sampled)[,
      .(frequency = .N), by = release_year
    ]
    sample_data <- merge(scope_data, frequencies, by = "release_year")
    sample_data[, roles := roles * frequency]
    fitted <- fit_two_knots(sample_data)
    c(fitted$knot_1, fitted$knot_2)
  })
  coefficients <- stats::coef(best$model)
  one_bic <- one_knot[scope == scope_name, bic_piecewise]
  two_knot_results[[scope_name]] <- data.table::data.table(
    scope = scope_name,
    early_change_age = best$knot_1,
    early_bootstrap_low = as.numeric(stats::quantile(boot[1, ], 0.025)),
    early_bootstrap_high = as.numeric(stats::quantile(boot[1, ], 0.975)),
    later_change_age = best$knot_2,
    later_bootstrap_low = as.numeric(stats::quantile(boot[2, ], 0.025)),
    later_bootstrap_high = as.numeric(stats::quantile(boot[2, ], 0.975)),
    early_logodds_slope = unname(coefficients[["age"]]),
    middle_logodds_slope = unname(coefficients[["age"]] + coefficients[["hinge_1"]]),
    later_logodds_slope = unname(
      coefficients[["age"]] + coefficients[["hinge_1"]] + coefficients[["hinge_2"]]
    ),
    bic_two_knot = best$bic,
    bic_one_knot = one_bic,
    bootstrap_reps = bootstrap_reps
  )
}
two_knot_summary <- data.table::rbindlist(two_knot_results)

message("Checking credit-class threshold, billing prominence, and period sensitivity...")
DBI::dbExecute(con, "DROP TABLE IF EXISTS sensitivity_units")
DBI::dbExecute(con, paste0(
  "CREATE TABLE sensitivity_units AS ",
  "SELECT nconst, release_year, birth_year, release_year - birth_year AS age, medium, ",
  "CASE WHEN medium = 'television' THEN 'tv:' || COALESCE(parentTconst, tconst) ",
  "ELSE 'film:' || tconst END AS opportunity_id, ",
  "MIN(cast_rank) AS best_cast_rank, MAX(actress_share) AS actress_share ",
  "FROM credits_base ",
  "WHERE release_year BETWEEN 2000 AND 2025 ",
  "AND release_year - birth_year BETWEEN 20 AND 70 ",
  "GROUP BY nconst, release_year, birth_year, age, medium, opportunity_id"
))

sensitivity_rows <- list()
index <- 1L
for (threshold in c(0.80, 0.90, 0.95)) {
  for (rank_cutoff in c(3L, 5L, 99L)) {
    cutoff_label <- if (rank_cutoff == 99L) "all-principal" else paste0("top-", rank_cutoff)
    query <- sprintf(paste0(
      "WITH classified AS (",
      "SELECT *, CASE WHEN actress_share >= %.2f THEN 'women-coded' ",
      "WHEN actress_share <= %.2f THEN 'men-coded' ELSE 'ambiguous' END AS credit_group ",
      "FROM sensitivity_units WHERE best_cast_rank <= %d",
      "), scoped AS (",
      "SELECT age, medium AS scope, credit_group FROM classified ",
      "UNION ALL SELECT age, 'overall' AS scope, credit_group FROM classified",
      ") ",
      "SELECT scope, age, SUM(CASE WHEN credit_group = 'women-coded' THEN 1 ELSE 0 END) AS women_roles, ",
      "SUM(CASE WHEN credit_group = 'men-coded' THEN 1 ELSE 0 END) AS men_roles ",
      "FROM scoped WHERE credit_group != 'ambiguous' GROUP BY scope, age"
    ), threshold, 1 - threshold, rank_cutoff)
    result <- data.table::as.data.table(DBI::dbGetQuery(con, query))
    result[, `:=`(
      women_share = women_roles / (women_roles + men_roles),
      classification_threshold = threshold,
      prominence = cutoff_label
    )]
    sensitivity_rows[[index]] <- result
    index <- index + 1L
  }
}
classification_prominence <- data.table::rbindlist(sensitivity_rows)

period_sensitivity <- data.table::as.data.table(DBI::dbGetQuery(con, paste0(
  "WITH classified AS (",
  "SELECT *, CASE WHEN actress_share >= 0.90 THEN 'women-coded' ",
  "WHEN actress_share <= 0.10 THEN 'men-coded' ELSE 'ambiguous' END AS credit_group, ",
  "CASE WHEN release_year <= 2012 THEN '2000-2012' ELSE '2013-2025' END AS period ",
  "FROM sensitivity_units",
  "), scoped AS (",
  "SELECT period, age, medium AS scope, credit_group FROM classified ",
  "UNION ALL SELECT period, age, 'overall' AS scope, credit_group FROM classified",
  ") ",
  "SELECT period, scope, age, ",
  "SUM(CASE WHEN credit_group = 'women-coded' THEN 1 ELSE 0 END) AS women_roles, ",
  "SUM(CASE WHEN credit_group = 'men-coded' THEN 1 ELSE 0 END) AS men_roles ",
  "FROM scoped WHERE credit_group != 'ambiguous' ",
  "GROUP BY period, scope, age ORDER BY period, scope, age"
)))
period_sensitivity[, women_share := women_roles / (women_roles + men_roles)]

message("Refitting career-exit hazards with three-, five-, and seven-year gap definitions...")
gap_results <- list()
for (gap_years in c(3L, 5L, 7L)) {
  query <- sprintf(paste0(
    "WITH ordered AS (",
    "SELECT a.nconst, a.release_year, ",
    "LEAD(a.release_year) OVER (PARTITION BY a.nconst ORDER BY a.release_year) AS next_credit_year ",
    "FROM annual_opportunity a INNER JOIN career_entrants e ON a.nconst = e.nconst ",
    "WHERE a.scope = 'overall'",
    "), qualifying_exit AS (",
    "SELECT o.nconst, MIN(o.release_year) AS event_year ",
    "FROM ordered o INNER JOIN career_entrants e ON o.nconst = e.nconst ",
    "WHERE (o.next_credit_year IS NULL OR o.next_credit_year - o.release_year > %d) ",
    "AND o.release_year + %d <= 2025 ",
    "AND (e.death_year IS NULL OR e.death_year > o.release_year + %d) ",
    "GROUP BY o.nconst",
    "), spells AS (",
    "SELECT e.*, q.event_year, LEAST(COALESCE(e.death_year, 2025), 2025) AS censor_year ",
    "FROM career_entrants e LEFT JOIN qualifying_exit q ON e.nconst = q.nconst",
    "), finalized AS (",
    "SELECT *, CASE WHEN event_year IS NOT NULL AND event_year <= censor_year THEN 1 ELSE 0 END AS event, ",
    "CASE WHEN event_year IS NOT NULL AND event_year <= censor_year THEN event_year ELSE censor_year END AS exit_year ",
    "FROM spells",
    ") ",
    "SELECT s.nconst, s.credit_group, s.entry_year, s.entry_age, s.early_roles, ",
    "risk.year - s.birth_year AS age, ",
    "CASE WHEN s.event = 1 AND risk.year = s.exit_year THEN 1 ELSE 0 END AS exit_event ",
    "FROM finalized s, LATERAL generate_series(s.entry_year, s.exit_year) AS risk(year) ",
    "WHERE risk.year - s.birth_year BETWEEN 18 AND 60"
  ), gap_years, gap_years, gap_years)
  gap_panel <- data.table::as.data.table(DBI::dbGetQuery(con, query))
  gap_panel[, credit_group := factor(
    credit_group,
    levels = c("men-coded", "women-coded")
  )]
  model <- stats::glm(
    exit_event ~ credit_group * splines::ns(age, df = 4) +
      splines::ns(entry_year, df = 3) + entry_age + log1p(early_roles),
    family = stats::binomial(),
    data = gap_panel
  )
  vcov_cluster <- cluster_vcov_glm(model, gap_panel$nconst)
  entrants <- unique(gap_panel[, .(nconst, entry_year, entry_age, early_roles)])
  rows <- lapply(c(30L, 35L, 40L), function(target_age) {
    women <- marginal_prediction(model, vcov_cluster, entrants, target_age, "women-coded")
    men <- marginal_prediction(model, vcov_cluster, entrants, target_age, "men-coded")
    log_gradient <- women$gradient / women$estimate - men$gradient / men$estimate
    log_se <- sqrt(drop(t(log_gradient) %*% vcov_cluster %*% log_gradient))
    ratio <- women$estimate / men$estimate
    data.table::data.table(
      gap_years = gap_years,
      age = target_age,
      women_exit_hazard = women$estimate,
      men_exit_hazard = men$estimate,
      exit_hazard_ratio = ratio,
      ratio_conf_low = exp(log(ratio) - 1.96 * log_se),
      ratio_conf_high = exp(log(ratio) + 1.96 * log_se),
      performers = data.table::uniqueN(gap_panel$nconst),
      observed_exits = sum(gap_panel$exit_event)
    )
  })
  gap_results[[as.character(gap_years)]] <- data.table::rbindlist(rows)
  rm(gap_panel, model, vcov_cluster)
  gc(verbose = FALSE)
}
gap_sensitivity <- data.table::rbindlist(gap_results)

ensure_project_dirs()
data.table::fwrite(
  two_knot_summary,
  project_path("outputs", "tables", "two_change_point_summary.csv")
)
data.table::fwrite(
  classification_prominence,
  project_path("outputs", "tables", "classification_prominence_sensitivity.csv")
)
data.table::fwrite(
  period_sensitivity,
  project_path("outputs", "tables", "period_sensitivity.csv")
)
data.table::fwrite(
  gap_sensitivity,
  project_path("outputs", "tables", "gap_definition_sensitivity.csv")
)

print(two_knot_summary)
print(gap_sensitivity)
cat("Sensitivity analyses completed.\n")

