source("R/paths.R")

required_packages <- c("data.table")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Missing required packages: ", paste(missing_packages, collapse = ", "))
}

source_url <- paste0(
  "https://raw.githubusercontent.com/mhollingshead/",
  "billboard-hot-100/main/all.json"
)
destination <- file.path(billboard_cache_dir(), "billboard_hot_100_all.json")
refresh <- identical(Sys.getenv("REFRESH_BILLBOARD", unset = "0"), "1")

if (!file.exists(destination) || refresh) {
  message("Downloading the historical Billboard Hot 100 archive...")
  utils::download.file(source_url, destination, mode = "wb", quiet = FALSE)
} else {
  message("Using the cached Billboard Hot 100 archive.")
}

info <- file.info(destination)
manifest <- data.table::data.table(
  source = "mhollingshead/billboard-hot-100",
  source_url = source_url,
  downloaded_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  bytes = info$size,
  local_path = normalizePath(destination, winslash = "/")
)

data.table::fwrite(
  manifest,
  project_path("data", "raw", "billboard_manifest.csv")
)
print(manifest)
