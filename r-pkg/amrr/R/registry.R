# Registry root resolution + provenance (the reproducibility pin).

# Resolve the registry root (the directory that contains metadata/). Precedence:
#   registry argument > option("amrr.registry") > Sys.getenv("AMRR_REGISTRY").
# Accepts either the repo root or the metadata/ directory itself.
amrr_registry_root <- function(registry = NULL) {
  root <- registry %||% getOption("amrr.registry") %||% Sys.getenv("AMRR_REGISTRY", unset = "")
  if (is.null(root) || !nzchar(root)) {
    stop(
      "No registry root. Pass registry=, set options(amrr.registry=), or the ",
      "AMRR_REGISTRY environment variable to a checkout of the ",
      "assessment-metadata-registry.",
      call. = FALSE
    )
  }
  if (dir.exists(file.path(root, "metadata"))) {
    return(normalizePath(root, mustWork = TRUE))
  }
  if (basename(root) == "metadata" && dir.exists(root)) {
    return(normalizePath(dirname(root), mustWork = TRUE))
  }
  stop("No 'metadata/' directory under registry root: ", root, call. = FALSE)
}

# The commit SHA of the registry checkout -- the reproducibility pin recorded by
# consumers. NA when the root is not a git checkout.
amrr_git_sha_of <- function(root) {
  out <- tryCatch(
    suppressWarnings(system2(
      "git", c("-C", shQuote(root), "rev-parse", "HEAD"),
      stdout = TRUE, stderr = FALSE
    )),
    error = function(e) character(0)
  )
  if (length(out) >= 1L && nzchar(out[[1]])) out[[1]] else NA_character_
}

# Read every sidecar for one jurisdiction as parsed lists (structure preserved).
read_jurisdiction_records <- function(root, jurisdiction) {
  dir <- file.path(root, "metadata", jurisdiction)
  if (!dir.exists(dir)) {
    stop("Jurisdiction not found in registry: ", jurisdiction, call. = FALSE)
  }
  files <- list.files(dir, pattern = "\\.json$", recursive = TRUE, full.names = TRUE)
  if (length(files) == 0L) {
    stop("No sidecars under ", dir, call. = FALSE)
  }
  lapply(files, function(f) {
    rec <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    attr(rec, "source_path") <- f
    rec
  })
}

#' Registry ref (commit SHA) recorded on a metadata object
#'
#' Returns the registry commit SHA that [get_metadata()] resolved against -- the
#' value a consumer should record in its analysis output for reproducibility.
#'
#' @param x An object returned by [get_metadata()].
#' @return A single character SHA, or `NA_character_` if the registry was not a
#'   git checkout.
#' @export
amrr_registry_ref <- function(x) {
  attr(x, "registry_ref", exact = TRUE) %||% NA_character_
}
