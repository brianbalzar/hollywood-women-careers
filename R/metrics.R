opportunity_curve <- function(panel, min_age = 18L, max_age = 80L) {
  validate_columns(
    panel,
    c("nconst", "age", "credit_group", "recently_active", "any_role", "role_count"),
    "panel"
  )
  data.table::as.data.table(panel)[
    recently_active & age >= min_age & age <= max_age &
      credit_group %in% c("women-coded", "men-coded"),
    .(
      performers_at_risk = data.table::uniqueN(nconst),
      performer_years = .N,
      role_years = sum(any_role),
      roles = sum(role_count),
      opportunity_rate = mean(any_role),
      mean_roles = mean(role_count)
    ),
    by = .(credit_group, age)
  ][order(credit_group, age)]
}

normalized_retention <- function(curve, baseline_ages = 30:34) {
  validate_columns(
    curve,
    c("credit_group", "age", "performer_years", "role_years", "opportunity_rate"),
    "curve"
  )
  x <- data.table::copy(data.table::as.data.table(curve))
  baseline <- x[age %in% baseline_ages,
                .(baseline_rate = sum(role_years) / sum(performer_years)),
                by = credit_group]
  x <- merge(x, baseline, by = "credit_group", all.x = TRUE)
  x[, normalized_retention := opportunity_rate / baseline_rate]
  x[]
}

retention_ratio <- function(normalized_curve) {
  validate_columns(
    normalized_curve,
    c("credit_group", "age", "normalized_retention"),
    "normalized_curve"
  )
  wide <- data.table::dcast(
    data.table::as.data.table(normalized_curve),
    age ~ credit_group,
    value.var = "normalized_retention"
  )
  if (!all(c("women-coded", "men-coded") %in% names(wide))) {
    stop("Both women-coded and men-coded groups are required.", call. = FALSE)
  }
  wide[, retention_ratio := `women-coded` / `men-coded`]
  wide[]
}
