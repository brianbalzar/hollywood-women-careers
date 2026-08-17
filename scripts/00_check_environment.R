source("R/paths.R")

required <- c("data.table", "arrow", "DBI", "duckdb", "ggplot2", "survival", "testthat")
installed <- rownames(installed.packages())
status <- data.frame(
  package = required,
  installed = required %in% installed,
  stringsAsFactors = FALSE
)

ensure_project_dirs()
cat("Project:", find_project_root(), "\n")
cat("IMDb cache:", imdb_cache_dir(), "\n")
print(status, row.names = FALSE)

if (any(!status$installed)) {
  stop(
    "Missing required packages: ",
    paste(status$package[!status$installed], collapse = ", "),
    call. = FALSE
  )
}

cat("Environment check passed.\n")
