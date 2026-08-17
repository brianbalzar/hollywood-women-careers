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

marginal_hazard <- function(model, vcov_cluster, entrants, age, group) {
  nd <- entrants[entry_age <= age]
  nd[, `:=`(
    age = age,
    credit_group = factor(group, levels = c("men-coded", "women-coded"))
  )]
  x <- stats::model.matrix(
    stats::delete.response(stats::terms(model)),
    nd,
    contrasts.arg = model$contrasts
  )
  eta <- drop(x %*% stats::coef(model))
  probability <- stats::plogis(eta)
  estimate <- mean(probability)
  gradient <- colMeans(x * (probability * (1 - probability)))
  se <- sqrt(drop(t(gradient) %*% vcov_cluster %*% gradient))
  data.table::data.table(
    age = age,
    credit_group = group,
    estimate = estimate,
    std_error = se,
    conf_low = pmax(0, estimate - 1.96 * se),
    conf_high = pmin(1, estimate + 1.96 * se),
    gradient = list(gradient)
  )
}

fit_knot <- function(age_counts, candidates = 25:50) {
  totals <- age_counts[, .(roles = sum(roles)), by = .(age, credit_group)]
  wide <- data.table::dcast(
    totals,
    age ~ credit_group,
    value.var = "roles",
    fill = 0
  )
  fits <- lapply(candidates, function(knot) {
    wide[, hinge := pmax(age - knot, 0)]
    model <- stats::glm(
      cbind(`women-coded`, `men-coded`) ~ age + hinge,
      data = wide,
      family = stats::binomial()
    )
    list(knot = knot, bic = stats::BIC(model), model = model)
  })
  best <- fits[[which.min(vapply(fits, `[[`, numeric(1), "bic"))]]
  linear <- stats::glm(
    cbind(`women-coded`, `men-coded`) ~ age,
    data = wide,
    family = stats::binomial()
  )
  list(best = best, linear = linear, data = wide)
}

analysis_root <- dirname(imdb_cache_dir())
database_path <- file.path(analysis_root, "hollywood.duckdb")
temp_dir <- file.path(analysis_root, "duckdb_tmp")
if (!file.exists(database_path)) stop("Run scripts/03 through 06 first.")

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = database_path)
on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
DBI::dbExecute(con, "SET memory_limit = '4GB'")
DBI::dbExecute(con, "SET threads = 4")
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", sql_path(temp_dir)))

if (!all(c("career_hazard_panel", "annual_opportunity") %in% DBI::dbListTables(con))) {
  stop("Required model tables are missing. Run scripts/04 and 06 first.")
}

message("Fitting adjusted discrete-time five-year-interruption model...")
panel <- data.table::as.data.table(DBI::dbGetQuery(con, paste0(
  "SELECT * FROM career_hazard_panel WHERE age BETWEEN 18 AND 60"
)))
panel[, credit_group := factor(
  credit_group,
  levels = c("men-coded", "women-coded")
)]

exit_model <- stats::glm(
  exit_event ~ credit_group * splines::ns(age, df = 4) +
    splines::ns(entry_year, df = 3) + entry_age + log1p(early_roles),
  family = stats::binomial(),
  data = panel,
  control = stats::glm.control(maxit = 50)
)
vcov_cluster <- cluster_vcov_glm(exit_model, panel$nconst)

interaction_terms <- grep(
  "credit_groupwomen-coded:splines::ns\\(age",
  names(stats::coef(exit_model))
)
interaction_beta <- stats::coef(exit_model)[interaction_terms]
interaction_vcov <- vcov_cluster[interaction_terms, interaction_terms, drop = FALSE]
wald_chisq <- drop(t(interaction_beta) %*% solve(interaction_vcov) %*% interaction_beta)
wald_df <- length(interaction_terms)
wald_p <- stats::pchisq(wald_chisq, df = wald_df, lower.tail = FALSE)

entrants <- unique(panel[, .(nconst, entry_year, entry_age, early_roles)])
ages <- 20:55
hazard <- data.table::rbindlist(lapply(ages, function(age) {
  data.table::rbindlist(lapply(c("men-coded", "women-coded"), function(group) {
    marginal_hazard(exit_model, vcov_cluster, entrants, age, group)
  }))
}))

hazard_wide <- data.table::dcast(
  hazard,
  age ~ credit_group,
  value.var = "estimate"
)
ratio_rows <- lapply(ages, function(target_age) {
  w <- hazard[age == target_age & credit_group == "women-coded"]
  m <- hazard[age == target_age & credit_group == "men-coded"]
  log_gradient <- w$gradient[[1]] / w$estimate - m$gradient[[1]] / m$estimate
  log_se <- sqrt(drop(t(log_gradient) %*% vcov_cluster %*% log_gradient))
  ratio <- w$estimate / m$estimate
  data.table::data.table(
    age = target_age,
    women_exit_hazard = w$estimate,
    men_exit_hazard = m$estimate,
    exit_hazard_ratio = ratio,
    ratio_conf_low = exp(log(ratio) - 1.96 * log_se),
    ratio_conf_high = exp(log(ratio) + 1.96 * log_se)
  )
})
hazard_ratio <- data.table::rbindlist(ratio_rows)

model_summary <- data.table::data.table(
  model = "discrete-time five-year career interruption",
  performer_years = nrow(panel),
  performers = data.table::uniqueN(panel$nconst),
  observed_exits = sum(panel$exit_event),
  interaction_wald_chisq = wald_chisq,
  interaction_df = wald_df,
  interaction_p_value = wald_p
)

message("Estimating role-share change points with release-year bootstrap...")
age_year_counts <- data.table::as.data.table(DBI::dbGetQuery(con, paste0(
  "SELECT scope, release_year, release_year - birth_year AS age, credit_group, ",
  "SUM(role_count) AS roles ",
  "FROM annual_opportunity ",
  "WHERE release_year BETWEEN 2000 AND 2025 ",
  "AND release_year - birth_year BETWEEN 20 AND 65 ",
  "GROUP BY scope, release_year, age, credit_group"
)))

set.seed(20260817)
bootstrap_reps <- 500L
change_summaries <- list()
change_curves <- list()

for (scope_name in c("overall", "film", "television")) {
  scope_data <- age_year_counts[scope == scope_name]
  fit <- fit_knot(scope_data)
  best_model <- fit$best$model
  best_knot <- fit$best$knot
  coefficients <- stats::coef(best_model)
  years <- sort(unique(scope_data$release_year))

  boot_knots <- replicate(bootstrap_reps, {
    sampled <- sample(years, length(years), replace = TRUE)
    frequencies <- data.table::data.table(release_year = sampled)[,
      .(frequency = .N),
      by = release_year
    ]
    boot <- merge(scope_data, frequencies, by = "release_year")
    boot[, roles := roles * frequency]
    fit_knot(boot)$best$knot
  })

  change_summaries[[scope_name]] <- data.table::data.table(
    scope = scope_name,
    estimated_change_age = best_knot,
    bootstrap_conf_low = as.numeric(stats::quantile(boot_knots, 0.025)),
    bootstrap_conf_high = as.numeric(stats::quantile(boot_knots, 0.975)),
    pre_change_logodds_slope = unname(coefficients[["age"]]),
    post_change_logodds_slope = unname(coefficients[["age"]] + coefficients[["hinge"]]),
    bic_piecewise = stats::BIC(best_model),
    bic_linear = stats::BIC(fit$linear),
    release_year_bootstrap_reps = bootstrap_reps
  )

  prediction <- data.table::data.table(age = 20:65)
  prediction[, hinge := pmax(age - best_knot, 0)]
  prediction[, predicted_women_share := stats::predict(
    best_model,
    newdata = prediction,
    type = "response"
  )]
  prediction[, `:=`(scope = scope_name, estimated_change_age = best_knot)]
  change_curves[[scope_name]] <- prediction
}

change_summary <- data.table::rbindlist(change_summaries)
change_curve <- data.table::rbindlist(change_curves)

ensure_project_dirs()
dir.create(project_path("outputs", "models"), recursive = TRUE, showWarnings = FALSE)
saveRDS(exit_model, project_path("outputs", "models", "career_exit_model.rds"))
saveRDS(vcov_cluster, project_path("outputs", "models", "career_exit_cluster_vcov.rds"))
data.table::fwrite(hazard, project_path("outputs", "tables", "adjusted_exit_hazard.csv"))
data.table::fwrite(hazard_ratio, project_path("outputs", "tables", "adjusted_exit_hazard_ratio.csv"))
data.table::fwrite(model_summary, project_path("outputs", "tables", "career_exit_model_summary.csv"))
data.table::fwrite(change_summary, project_path("outputs", "tables", "role_share_change_points.csv"))
data.table::fwrite(change_curve, project_path("outputs", "tables", "role_share_piecewise_fit.csv"))

colors <- c("women-coded" = "#B23A6F", "men-coded" = "#315A8A")
p_hazard <- ggplot2::ggplot(
  hazard,
  ggplot2::aes(age, estimate, color = credit_group, fill = credit_group)
) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = conf_low, ymax = conf_high),
    alpha = 0.15,
    color = NA
  ) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::scale_color_manual(values = colors) +
  ggplot2::scale_fill_manual(values = colors) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::labs(
    title = "Adjusted hazard of a first confirmed five-year interruption",
    subtitle = "Established entrants, 2000-2010; performer-clustered 95% CIs",
    x = "Performer age", y = "Interruption hazard", color = "IMDb credit class", fill = "IMDb credit class"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(legend.position = "bottom")

p_change <- ggplot2::ggplot(
  change_curve,
  ggplot2::aes(age, predicted_women_share, color = scope)
) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::geom_vline(
    data = change_summary,
    ggplot2::aes(xintercept = estimated_change_age, color = scope),
    linetype = "dashed",
    show.legend = FALSE
  ) +
  ggplot2::scale_y_continuous(labels = scales::label_percent()) +
  ggplot2::labs(
    title = "Piecewise estimates of women-coded opportunity share",
    subtitle = "Dashed lines mark BIC-selected change ages; uncertainty uses 500 release-year bootstraps",
    x = "Performer age", y = "Predicted women-coded share", color = "Scope"
  ) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave(
  project_path("outputs", "figures", "adjusted_career_exit_hazard.png"),
  p_hazard, width = 9, height = 5.5, dpi = 180
)
ggplot2::ggsave(
  project_path("outputs", "figures", "role_share_change_points.png"),
  p_change, width = 9, height = 5.5, dpi = 180
)

print(model_summary)
print(change_summary)
cat("Adjusted career-interruption and change-point models completed.\n")
