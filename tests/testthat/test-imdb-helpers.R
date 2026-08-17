test_that("credit groups preserve ambiguous classifications", {
  principals <- data.table::data.table(
    nconst = c(rep("nm1", 10), rep("nm2", 10), rep("nm3", 10)),
    category = c(rep("actress", 10), rep("actor", 10), rep("actor", 5), rep("actress", 5))
  )
  result <- classify_credit_group(principals, threshold = 0.9)
  expect_equal(result[nconst == "nm1", credit_group], "women-coded")
  expect_equal(result[nconst == "nm2", credit_group], "men-coded")
  expect_equal(result[nconst == "nm3", credit_group], "ambiguous")
})

test_that("recent activity excludes the current year from its lookback", {
  credits <- data.table::data.table(
    nconst = "nm1",
    release_year = c(2000L, 2002L),
    birth_year = 1970L,
    credit_group = "women-coded",
    tconst = c("tt1", "tt2")
  )
  panel <- build_recent_activity_panel(credits, lookback = 2L, end_year = 2004L)
  expect_true(panel[year == 2001L, recently_active])
  expect_equal(panel[year == 2002L, role_count], 1L)
  expect_true(panel[year == 2004L, recently_active])
})

test_that("retention ratio is one for identical normalized curves", {
  curve <- data.table::data.table(
    credit_group = rep(c("women-coded", "men-coded"), each = 3),
    age = rep(30:32, 2),
    performer_years = 100L,
    role_years = rep(c(50L, 40L, 30L), 2),
    opportunity_rate = rep(c(0.5, 0.4, 0.3), 2)
  )
  result <- retention_ratio(normalized_retention(curve, baseline_ages = 30:32))
  expect_equal(result$retention_ratio, rep(1, 3))
})
