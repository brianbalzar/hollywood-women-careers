required_imdb_files <- function() {
  c(
    names = "name.basics.tsv.gz",
    titles = "title.basics.tsv.gz",
    principals = "title.principals.tsv.gz",
    akas = "title.akas.tsv.gz",
    episodes = "title.episode.tsv.gz",
    ratings = "title.ratings.tsv.gz"
  )
}

validate_columns <- function(x, required, object_name = deparse(substitute(x))) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(
      object_name, " is missing required columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

read_imdb_tsv <- function(path, select = NULL, nrows = Inf) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("Package 'data.table' is required.", call. = FALSE)
  }
  if (!file.exists(path)) stop("File does not exist: ", path, call. = FALSE)
  data.table::fread(
    path,
    sep = "\t",
    header = TRUE,
    na.strings = "\\N",
    quote = "",
    select = select,
    nrows = nrows,
    showProgress = interactive()
  )
}

classify_credit_group <- function(principals, threshold = 0.90) {
  validate_columns(principals, c("nconst", "category"), "principals")
  x <- data.table::as.data.table(principals)[category %in% c("actor", "actress")]
  counts <- x[, .(
    actor_credits = sum(category == "actor"),
    actress_credits = sum(category == "actress")
  ), by = nconst]
  counts[, classified_credits := actor_credits + actress_credits]
  counts[, actress_share := actress_credits / classified_credits]
  counts[, credit_group := data.table::fcase(
    actress_share >= threshold, "women-coded",
    actress_share <= (1 - threshold), "men-coded",
    default = "ambiguous"
  )]
  counts[]
}

build_age_credits <- function(names_data, titles, principals,
                              start_year = 2000L,
                              end_year = as.integer(format(Sys.Date(), "%Y")) - 1L,
                              min_age = 18L,
                              max_age = 80L,
                              classification_threshold = 0.90) {
  validate_columns(names_data, c("nconst", "birthYear", "deathYear"), "names_data")
  validate_columns(titles, c("tconst", "titleType", "startYear"), "titles")
  validate_columns(principals, c("tconst", "ordering", "nconst", "category"), "principals")

  cast <- data.table::as.data.table(principals)[category %in% c("actor", "actress")]
  cast[, ordering := as.integer(ordering)]
  data.table::setorder(cast, tconst, ordering)
  cast[, cast_rank := seq_len(.N), by = tconst]

  title_keep <- data.table::as.data.table(titles)[, .(
    tconst,
    titleType,
    release_year = as.integer(startYear)
  )]
  person_keep <- data.table::as.data.table(names_data)[, .(
    nconst,
    birth_year = as.integer(birthYear),
    death_year = as.integer(deathYear)
  )]
  groups <- classify_credit_group(cast, classification_threshold)[,
    .(nconst, credit_group, actress_share, classified_credits)
  ]

  result <- merge(cast, title_keep, by = "tconst", all.x = TRUE)
  result <- merge(result, person_keep, by = "nconst", all.x = TRUE)
  result <- merge(result, groups, by = "nconst", all.x = TRUE)
  result[, age := release_year - birth_year]
  result <- result[
    !is.na(release_year) & !is.na(birth_year) &
      release_year >= start_year & release_year <= end_year &
      age >= min_age & age <= max_age
  ]
  data.table::setorder(result, nconst, release_year, tconst)
  result[]
}

build_recent_activity_panel <- function(credits, lookback = 5L,
                                        end_year = max(credits$release_year, na.rm = TRUE)) {
  validate_columns(
    credits,
    c("nconst", "release_year", "birth_year", "credit_group"),
    "credits"
  )
  x <- unique(data.table::as.data.table(credits)[,
    .(nconst, release_year, birth_year, credit_group, tconst)
  ])
  annual <- x[, .(role_count = data.table::uniqueN(tconst)),
              by = .(nconst, release_year, birth_year, credit_group)]

  panel <- annual[, {
    credit_years <- release_year
    years <- seq.int(min(credit_years) + 1L,
                     min(end_year, max(credit_years) + lookback))
    if (!length(years)) return(NULL)
    counts <- tabulate(match(credit_years, years), nbins = length(years))
    recent <- vapply(
      years,
      function(y) any(credit_years >= y - lookback & credit_years < y),
      logical(1)
    )
    data.table::data.table(
      year = years,
      age = years - birth_year[1L],
      recently_active = recent,
      role_count = counts,
      any_role = counts > 0L
    )
  }, by = .(nconst, birth_year, credit_group)]
  panel[]
}
