source("R/paths.R")
source("R/imdb_helpers.R")

base_url <- "https://datasets.imdbws.com"
cache <- imdb_cache_dir()
files <- required_imdb_files()

download_one <- function(filename) {
  destination <- file.path(cache, filename)
  if (file.exists(destination) && file.info(destination)$size > 0) {
    message("Already present: ", destination)
    return(destination)
  }
  url <- paste(base_url, filename, sep = "/")
  temporary <- paste0(destination, ".partial")
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  message("Downloading ", url)
  utils::download.file(url, temporary, mode = "wb", quiet = FALSE)
  if (!file.exists(temporary) || file.info(temporary)$size == 0) {
    stop("Download failed or was empty: ", url, call. = FALSE)
  }
  if (!file.rename(temporary, destination)) {
    stop("Could not finalize download: ", destination, call. = FALSE)
  }
  destination
}

downloaded <- vapply(files, download_one, character(1))
manifest <- data.frame(
  dataset = names(downloaded),
  path = unname(downloaded),
  bytes = unname(file.info(downloaded)$size),
  downloaded_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  stringsAsFactors = FALSE
)
write.csv(manifest, project_path("data", "raw", "imdb_manifest.csv"), row.names = FALSE)
print(manifest, row.names = FALSE)

