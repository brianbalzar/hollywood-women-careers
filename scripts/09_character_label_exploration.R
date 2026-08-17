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
if (!file.exists(database_path)) stop("Run scripts/03 through 08 first.")

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = database_path)
on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
DBI::dbExecute(con, "SET memory_limit = '4GB'")
DBI::dbExecute(con, "SET threads = 4")
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", sql_path(temp_dir)))

message("Scanning explicit familial terms in credited character names...")
labels <- data.table::as.data.table(DBI::dbGetQuery(con, paste0(
  "WITH labeled AS (",
  "SELECT credit_group, medium, age, cast_rank, characters, ",
  "CASE WHEN regexp_matches(COALESCE(characters, ''), ",
  "'(?i)(grandmother|grandma|grandmom|granny|nana|abuela|oma|grandfather|grandpa|granddad|grampa|abuelo|opa)') ",
  "THEN 1 ELSE 0 END AS grandparent_label, ",
  "CASE WHEN regexp_matches(COALESCE(characters, ''), ",
  "'(?i)(mother|mom|mommy|mama|mum|father|dad|daddy|papa)') ",
  "THEN 1 ELSE 0 END AS parent_label, ",
  "CASE WHEN regexp_matches(COALESCE(characters, ''), ",
  "'(?i)(wife|widow|husband|widower)') ",
  "THEN 1 ELSE 0 END AS spouse_label ",
  "FROM credits_base ",
  "WHERE release_year BETWEEN 2000 AND 2025 ",
  "AND age BETWEEN 20 AND 80 ",
  "AND credit_group IN ('women-coded','men-coded') ",
  "AND cast_rank <= 5",
  "), binned AS (",
  "SELECT *, CASE ",
  "WHEN age BETWEEN 20 AND 29 THEN '20-29' ",
  "WHEN age BETWEEN 30 AND 34 THEN '30-34' ",
  "WHEN age BETWEEN 35 AND 39 THEN '35-39' ",
  "WHEN age BETWEEN 40 AND 49 THEN '40-49' ",
  "WHEN age BETWEEN 50 AND 59 THEN '50-59' ",
  "WHEN age BETWEEN 60 AND 69 THEN '60-69' ",
  "ELSE '70-80' END AS age_band ",
  "FROM labeled",
  ") ",
  "SELECT credit_group, medium, age_band, COUNT(*) AS credited_roles, ",
  "SUM(grandparent_label) AS explicit_grandparent_roles, ",
  "AVG(grandparent_label) AS grandparent_label_rate, ",
  "SUM(parent_label) AS explicit_parent_roles, AVG(parent_label) AS parent_label_rate, ",
  "SUM(spouse_label) AS explicit_spouse_roles, AVG(spouse_label) AS spouse_label_rate ",
  "FROM binned GROUP BY credit_group, medium, age_band ",
  "ORDER BY medium, credit_group, age_band"
)))

labels[, age_band := factor(
  age_band,
  levels = c("20-29", "30-34", "35-39", "40-49", "50-59", "60-69", "70-80")
)]

ensure_project_dirs()
data.table::fwrite(
  labels,
  project_path("outputs", "tables", "explicit_character_family_labels.csv")
)

colors <- c("women-coded" = "#B23A6F", "men-coded" = "#315A8A")
plot <- ggplot2::ggplot(
  labels,
  ggplot2::aes(age_band, grandparent_label_rate, color = credit_group, group = credit_group)
) +
  ggplot2::geom_line(linewidth = 0.9) +
  ggplot2::geom_point(size = 2) +
  ggplot2::facet_wrap(~medium) +
  ggplot2::scale_color_manual(values = colors) +
  ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 0.1)) +
  ggplot2::labs(
    title = "Exploratory lower bound: explicit grandparent labels in character credits",
    subtitle = "Top-five principal cast; labels such as Grandmother, Grandma, Nana, Grandfather, and Grandpa",
    x = "Performer age band", y = "Share of credited character names", color = "IMDb credit class"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 30, hjust = 1))

ggplot2::ggsave(
  project_path("outputs", "figures", "explicit_grandparent_labels.png"),
  plot, width = 10, height = 5.5, dpi = 180
)

print(labels[age_band %in% c("40-49", "50-59", "60-69", "70-80")])
cat("Exploratory character-label analysis completed.\n")

