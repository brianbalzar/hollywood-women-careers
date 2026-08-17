find_project_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    markers <- c(
      file.path(current, "hollywood-women-careers.Rproj"),
      file.path(current, "DESCRIPTION")
    )
    if (any(file.exists(markers))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not locate the project root from: ", start, call. = FALSE)
    }
    current <- parent
  }
}

project_path <- function(...) file.path(find_project_root(), ...)

imdb_cache_dir <- function(create = TRUE) {
  configured <- Sys.getenv("HOLLYWOOD_CAREERS_CACHE", unset = "")
  if (nzchar(configured)) {
    path <- configured
  } else if (nzchar(Sys.getenv("LOCALAPPDATA", unset = ""))) {
    path <- file.path(
      Sys.getenv("LOCALAPPDATA"),
      "hollywood-women-careers",
      "imdb"
    )
  } else {
    path <- project_path("data", "raw")
  }
  if (create && !dir.exists(path)) {
    created <- dir.create(path, recursive = TRUE, showWarnings = FALSE)
    if (!created && !dir.exists(path)) {
      warning(
        "Could not create configured cache; using project data/raw instead: ",
        path,
        call. = FALSE
      )
      path <- project_path("data", "raw")
      dir.create(path, recursive = TRUE, showWarnings = FALSE)
    }
  }
  normalizePath(path, winslash = "/", mustWork = create)
}

billboard_cache_dir <- function(create = TRUE) {
  path <- file.path(dirname(imdb_cache_dir(create = create)), "billboard")
  if (create && !dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = create)
}

ensure_project_dirs <- function() {
  dirs <- c(
    project_path("data", "raw"),
    project_path("data", "processed"),
    project_path("outputs", "figures"),
    project_path("outputs", "tables")
  )
  invisible(vapply(dirs, dir.create, logical(1), recursive = TRUE, showWarnings = FALSE))
}
