source("R/paths.R")

required_packages <- c("data.table", "jsonlite", "httr2")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Missing required packages: ", paste(missing_packages, collapse = ", "))
}

cache_dir <- billboard_cache_dir()
source_path <- file.path(cache_dir, "billboard_hot_100_all.json")
batch_dir <- file.path(cache_dir, "wikidata_batches")
dir.create(batch_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(source_path)) {
  stop("Billboard archive missing. Run scripts/11_download_billboard.R first.")
}

escape_sparql <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x)
  gsub('"', '\\\\"', x)
}

empty_match_table <- function() {
  data.table::data.table(
    artist = character(),
    person_uri = character(),
    birth = character(),
    gender = character(),
    gender_uri = character(),
    mbid = character()
  )
}

query_artist_batch <- function(artist_names) {
  label_values <- paste0(
    rep(paste0('"', escape_sparql(artist_names), '"'), each = 2),
    rep(c("@en", "@mul"), times = length(artist_names)),
    collapse = " "
  )
  query <- paste0(
    "SELECT DISTINCT ?artist ?person ?birth ?gender ?genderLabel ?mbid WHERE { ",
    "VALUES ?matchedName { ", label_values, " } ",
    "?person (rdfs:label|skos:altLabel) ?matchedName. ",
    "BIND(STR(?matchedName) AS ?artist) ",
    "?person wdt:P31 wd:Q5; wdt:P569 ?birth; wdt:P21 ?gender; wdt:P434 ?mbid. ",
    "SERVICE wikibase:label { bd:serviceParam wikibase:language 'en'. ",
    "?gender rdfs:label ?genderLabel. } }"
  )

  response <- httr2::request("https://query.wikidata.org/sparql") |>
    httr2::req_url_query(query = query, format = "json") |>
    httr2::req_user_agent(
      "hollywood-women-careers/0.1 (non-commercial research; local analysis)"
    ) |>
    httr2::req_timeout(90) |>
    httr2::req_retry(max_tries = 4, backoff = ~ 2^.x) |>
    httr2::req_perform()

  payload <- httr2::resp_body_json(response, simplifyVector = FALSE)
  bindings <- payload$results$bindings
  if (!length(bindings)) return(empty_match_table())

  data.table::rbindlist(lapply(bindings, function(row) {
    data.table::data.table(
      artist = row$artist$value,
      person_uri = row$person$value,
      birth = row$birth$value,
      gender = row$genderLabel$value,
      gender_uri = row$gender$value,
      mbid = row$mbid$value
    )
  }), fill = TRUE)
}

query_sitelink_batch <- function(person_ids) {
  values <- paste0("wd:", person_ids, collapse = " ")
  query <- paste0(
    "SELECT ?person ?sitelinks WHERE { VALUES ?person { ", values, " } ",
    "?person wikibase:sitelinks ?sitelinks. }"
  )
  response <- httr2::request("https://query.wikidata.org/sparql") |>
    httr2::req_url_query(query = query, format = "json") |>
    httr2::req_user_agent(
      "hollywood-women-careers/0.1 (non-commercial research; local analysis)"
    ) |>
    httr2::req_timeout(90) |>
    httr2::req_retry(max_tries = 4, backoff = ~ 2^.x) |>
    httr2::req_perform()
  payload <- httr2::resp_body_json(response, simplifyVector = FALSE)
  bindings <- payload$results$bindings
  if (!length(bindings)) {
    return(data.table::data.table(person_id = character(), sitelinks = integer()))
  }
  data.table::rbindlist(lapply(bindings, function(row) {
    data.table::data.table(
      person_id = sub(".*/", "", row$person$value),
      sitelinks = as.integer(row$sitelinks$value)
    )
  }))
}

query_person_batch <- function(person_ids) {
  values <- paste0("wd:", person_ids, collapse = " ")
  query <- paste0(
    "SELECT ?person ?birth ?gender ?genderLabel ?mbid WHERE { ",
    "VALUES ?person { ", values, " } ",
    "?person wdt:P31 wd:Q5; wdt:P569 ?birth; wdt:P21 ?gender; wdt:P434 ?mbid. ",
    "SERVICE wikibase:label { bd:serviceParam wikibase:language 'en'. ",
    "?gender rdfs:label ?genderLabel. } }"
  )
  response <- httr2::request("https://query.wikidata.org/sparql") |>
    httr2::req_url_query(query = query, format = "json") |>
    httr2::req_user_agent(
      "hollywood-women-careers/0.1 (non-commercial research; local analysis)"
    ) |>
    httr2::req_timeout(90) |>
    httr2::req_retry(max_tries = 4, backoff = ~ 2^.x) |>
    httr2::req_perform()
  payload <- httr2::resp_body_json(response, simplifyVector = FALSE)
  bindings <- payload$results$bindings
  if (!length(bindings)) return(empty_match_table())
  data.table::rbindlist(lapply(bindings, function(row) {
    data.table::data.table(
      person_id = sub(".*/", "", row$person$value),
      person_uri = row$person$value,
      birth = row$birth$value,
      gender = row$genderLabel$value,
      gender_uri = row$gender$value,
      mbid = row$mbid$value
    )
  }), fill = TRUE)
}

message("Reading and flattening Billboard chart history...")
charts <- jsonlite::fromJSON(source_path, simplifyDataFrame = FALSE)
hot100 <- data.table::rbindlist(lapply(charts, function(chart) {
  rows <- data.table::rbindlist(chart$data, fill = TRUE)
  rows[, chart_date := data.table::as.IDate(chart$date)]
  rows
}), fill = TRUE)
data.table::setcolorder(
  hot100,
  c("chart_date", "this_week", "song", "artist", "last_week", "peak_position", "weeks_on_chart")
)
hot100 <- hot100[
  chart_date >= data.table::as.IDate("1995-01-01") &
    chart_date <= data.table::as.IDate("2025-12-31")
]

artist_summary <- hot100[, .(
  chart_rows = .N,
  chart_years = data.table::uniqueN(format(chart_date, "%Y")),
  songs = data.table::uniqueN(song),
  first_chart_date = min(chart_date),
  last_chart_date = max(chart_date),
  best_rank = min(this_week)
), by = artist][order(artist)]

message("Matching ", nrow(artist_summary), " Billboard artist strings to solo artists...")
batch_size <- 50L
batch_ids <- split(
  seq_len(nrow(artist_summary)),
  ceiling(seq_len(nrow(artist_summary)) / batch_size)
)

for (batch_number in seq_along(batch_ids)) {
  output_path <- file.path(batch_dir, sprintf("batch_%03d.csv", batch_number))
  if (file.exists(output_path)) next
  artist_names <- artist_summary$artist[batch_ids[[batch_number]]]
  message("Wikidata batch ", batch_number, " of ", length(batch_ids))
  result <- query_artist_batch(artist_names)
  data.table::fwrite(result, output_path)
  Sys.sleep(1)
}

batch_paths <- list.files(batch_dir, pattern = "^batch_[0-9]+\\.csv$", full.names = TRUE)
matches <- data.table::rbindlist(
  lapply(batch_paths, data.table::fread),
  fill = TRUE
)
matches <- unique(matches)

alias_path <- project_path("data", "manual", "billboard_artist_aliases.csv")
alias_cache_path <- file.path(cache_dir, "wikidata_artist_alias_matches.csv")
if (file.exists(alias_path)) {
  aliases <- data.table::fread(alias_path)
  if (!file.exists(alias_cache_path)) {
    alias_matches <- query_artist_batch(unique(aliases$query_name))
    data.table::fwrite(alias_matches, alias_cache_path)
  } else {
    alias_matches <- data.table::fread(alias_cache_path)
  }
  alias_lookup <- aliases[, .(
    artist = query_name,
    billboard_artist = artist
  )]
  alias_matches <- merge(
    alias_matches,
    alias_lookup,
    by = "artist",
    allow.cartesian = TRUE
  )
  alias_matches[, artist := billboard_artist]
  alias_matches[, billboard_artist := NULL]
  matches <- unique(data.table::rbindlist(list(matches, alias_matches), fill = TRUE))
}

override_path <- project_path("data", "manual", "billboard_artist_overrides.csv")
override_cache_path <- file.path(cache_dir, "wikidata_artist_override_matches.csv")
if (file.exists(override_path)) {
  overrides <- data.table::fread(override_path)
  if (!file.exists(override_cache_path)) {
    override_matches <- query_person_batch(unique(overrides$person_id))
    data.table::fwrite(override_matches, override_cache_path)
  } else {
    override_matches <- data.table::fread(override_cache_path)
  }
  override_matches <- merge(
    override_matches,
    overrides[, .(person_id, artist)],
    by = "person_id"
  )
  matches <- unique(data.table::rbindlist(list(matches, override_matches), fill = TRUE))
}

matches[, birth_year := suppressWarnings(as.integer(substr(birth, 1, 4)))]
matches[, person_id := sub(".*/", "", person_uri)]

sitelink_path <- file.path(cache_dir, "wikidata_artist_sitelinks.csv")
person_ids <- sort(unique(matches$person_id))
if (file.exists(sitelink_path)) {
  sitelinks <- data.table::fread(sitelink_path)
} else {
  sitelinks <- data.table::data.table(person_id = character(), sitelinks = integer())
}
missing_person_ids <- setdiff(person_ids, sitelinks$person_id)
if (length(missing_person_ids)) {
  sitelink_batches <- split(
    seq_along(missing_person_ids),
    ceiling(seq_along(missing_person_ids) / 200L)
  )
  new_sitelinks <- data.table::rbindlist(lapply(seq_along(sitelink_batches), function(i) {
    message("Wikidata sitelink batch ", i, " of ", length(sitelink_batches))
    result <- query_sitelink_batch(missing_person_ids[sitelink_batches[[i]]])
    Sys.sleep(1)
    result
  }))
  sitelinks <- unique(data.table::rbindlist(list(sitelinks, new_sitelinks), fill = TRUE))
  data.table::fwrite(sitelinks, sitelink_path)
}
matches <- merge(matches, sitelinks, by = "person_id", all.x = TRUE)
matches[is.na(sitelinks), sitelinks := 0L]

candidate <- merge(matches, artist_summary, by = "artist", all.x = TRUE)
candidate[, first_chart_age := as.integer(format(first_chart_date, "%Y")) - birth_year]
candidate[, plausible_age := first_chart_age >= 10 & first_chart_age <= 90]
candidate[, plausible_people := data.table::uniqueN(
  person_id[plausible_age %in% TRUE]
), by = artist]
candidate[, max_plausible_sitelinks := {
  values <- sitelinks[plausible_age %in% TRUE]
  if (length(values)) max(values) else NA_integer_
}, by = artist]
candidate[, top_plausible_people := data.table::uniqueN(
  person_id[plausible_age %in% TRUE & sitelinks == max_plausible_sitelinks]
), by = artist]
candidate[, match_status := data.table::fcase(
  plausible_age %in% TRUE & sitelinks == max_plausible_sitelinks &
    top_plausible_people == 1L, "matched",
  plausible_age %in% TRUE & plausible_people > 1L, "ambiguous",
  default = "implausible"
)]

resolved <- candidate[match_status == "matched"]
resolved <- unique(resolved, by = c("artist", "person_id"))
resolved[, credit_group := data.table::fcase(
  gender == "female", "women-coded",
  gender == "male", "men-coded",
  default = "other-coded"
)]

all_artists <- merge(
  artist_summary,
  resolved[, .(
    artist, person_id, person_uri, mbid, birth, birth_year,
    gender, gender_uri, credit_group, match_status
  )],
  by = "artist",
  all.x = TRUE
)
all_artists[is.na(match_status), match_status := "unmatched"]

hot100_enriched <- merge(
  hot100,
  resolved[, .(artist, person_id, mbid, birth_year, gender, credit_group)],
  by = "artist",
  all.x = TRUE
)

coverage <- all_artists[, .(
  artist_strings = .N,
  chart_rows = sum(chart_rows),
  songs = sum(songs),
  chart_years = sum(chart_years)
), by = .(match_status, credit_group)][order(match_status, credit_group)]
coverage[, chart_row_share := chart_rows / sum(chart_rows)]

data.table::fwrite(
  hot100_enriched,
  file.path(cache_dir, "billboard_hot100_1995_2025.csv")
)
data.table::fwrite(
  all_artists,
  file.path(cache_dir, "billboard_artist_demographics.csv")
)
data.table::fwrite(
  candidate,
  file.path(cache_dir, "billboard_artist_match_candidates.csv")
)
ensure_project_dirs()
data.table::fwrite(
  coverage,
  project_path("outputs", "tables", "billboard_match_coverage.csv")
)

print(coverage)
cat("Billboard artist matching completed.\n")
