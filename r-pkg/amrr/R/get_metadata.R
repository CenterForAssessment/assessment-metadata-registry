# A URL registry (remote derived layer) vs a local checkout path.
.is_url_registry <- function(x) {
  is.character(x) && length(x) == 1L && grepl("^(https?|file)://", x)
}

# Fetch a jurisdiction's derived bundle (<base>/dist/<jur>.json) over HTTP/file
# and return its records + the build's git_sha. The bundle already carries every
# record for the jurisdiction (assessment + accountability), so the caller's
# filter/attach_targets logic is identical to the local path.
.fetch_jurisdiction_bundle <- function(base, jurisdiction) {
  url <- sprintf("%s/dist/%s.json", base, jurisdiction)
  # jsonlite fetches http(s) URLs but not file:// — strip that scheme to a path.
  src <- sub("^file://", "", url)
  bundle <- tryCatch(
    jsonlite::fromJSON(src, simplifyVector = FALSE),
    error = function(e) stop(sprintf(
      "Could not fetch registry bundle for jurisdiction '%s' from %s: %s",
      jurisdiction, url, conditionMessage(e)), call. = FALSE)
  )
  list(records = bundle$records %||% list(),
       sha = (bundle[["_registry"]] %||% list())$git_sha %||% NA_character_)
}

#' Get assessment metadata for a jurisdiction
#'
#' Reads the registry for one `jurisdiction`, optionally filtered to a `system`
#' and/or `year`, and returns the matching assessment-system records. When
#' `attach_targets = TRUE` (the default), accountability achievement targets are
#' resolved and merged onto each assessment record under `achievement_targets`
#' (keyed by content area) -- the shape downstream consumers such as SGPc expect
#' -- even though targets are authored separately in accountability records
#' (ADR-002).
#'
#' The returned object carries the registry commit SHA in its `"registry_ref"`
#' attribute (see [amrr_registry_ref()]); record it in analysis output to make
#' the run reproducible.
#'
#' @param jurisdiction Jurisdiction id (e.g. `"IN"`).
#' @param system Optional assessment-system id (e.g. `"ilearn"`, `"wida-access"`).
#' @param year Optional four-digit administration year (character or numeric).
#' @param registry Either a local registry checkout (the directory containing
#'   `metadata/`) **or** a base URL serving the derived layer (e.g. the published
#'   GitHub Pages root). A URL registry fetches the jurisdiction bundle
#'   `<registry>/dist/<jurisdiction>.json` over HTTP (via \pkg{jsonlite}) instead
#'   of reading local files; `http://`, `https://`, and `file://` are recognized.
#'   The bundle's `_registry.git_sha` becomes the pin. Note a URL registry serves
#'   the *latest* published build (the derived layer is not retained per SHA); for
#'   byte-reproducible pinning read the canonical sidecars from a checkout at a
#'   commit SHA. Defaults to `option("amrr.registry")` then `AMRR_REGISTRY`.
#' @param ref Optional commit SHA to pin to. If the resolved registry SHA (git
#'   `HEAD` for a checkout, or the bundle's stamp for a URL) differs, a warning is
#'   issued and the data is read as-is.
#' @param attach_targets Merge resolved accountability targets onto each
#'   assessment record? Defaults to `TRUE`.
#'
#' @return An object of class `amrr_metadata`: a list of assessment-metadata
#'   records, with attributes `registry_ref`, `registry_root`, and `jurisdiction`.
#' @examples
#' \dontrun{
#' # From a local checkout (byte-reproducible when pinned to a commit SHA):
#' md <- get_metadata("IN", system = "wida-access", year = 2024,
#'                    registry = "~/GitHub/CenterForAssessment/assessment-metadata-registry")
#' amrr_registry_ref(md)
#' amrr_targets(md[[1]], "ELP_COMPOSITE")
#'
#' # From the published derived layer over HTTP (no checkout needed):
#' pages <- "https://centerforassessment.github.io/assessment-metadata-registry"
#' md <- get_metadata("IN", system = "ilearn", year = 2024, registry = pages)
#' }
#' @export
get_metadata <- function(jurisdiction, system = NULL, year = NULL,
                         registry = NULL, ref = NULL, attach_targets = TRUE) {
  if (missing(jurisdiction) || !is.character(jurisdiction) || length(jurisdiction) != 1L) {
    stop("jurisdiction must be a single string", call. = FALSE)
  }
  if (.is_url_registry(registry)) {
    root <- sub("/+$", "", registry)
    b <- .fetch_jurisdiction_bundle(root, jurisdiction)
    records <- b$records
    sha <- b$sha
  } else {
    root <- amrr_registry_root(registry)
    sha <- amrr_git_sha_of(root)
    records <- read_jurisdiction_records(root, jurisdiction)
  }
  if (!is.null(ref) && !is.na(sha) && !identical(ref, sha)) {
    warning(sprintf(
      "registry SHA (%s) != requested ref (%s); reading as-is.",
      substr(sha, 1L, 8L), substr(ref, 1L, 8L)
    ), call. = FALSE)
  }

  assessments <- Filter(is_assessment_record, records)
  accountability <- Filter(is_accountability_record, records)

  if (!is.null(system)) {
    assessments <- Filter(
      function(r) identical(r$assessment_system$id, system), assessments
    )
  }
  if (!is.null(year)) {
    yr <- as.character(year)
    assessments <- Filter(
      function(r) identical(as.character(r$administration$year), yr), assessments
    )
  }
  if (isTRUE(attach_targets)) {
    assessments <- lapply(
      assessments, function(r) attach_targets_to_record(r, accountability)
    )
  }

  structure(
    assessments,
    class = "amrr_metadata",
    registry_ref = sha,
    registry_root = root,
    jurisdiction = jurisdiction
  )
}

#' @export
print.amrr_metadata <- function(x, ...) {
  ref <- amrr_registry_ref(x)
  cat(sprintf(
    "<amrr_metadata> %s: %d assessment record(s) @ registry %s\n",
    attr(x, "jurisdiction", exact = TRUE) %||% "?",
    length(x),
    if (is.na(ref)) "<no-git>" else substr(ref, 1L, 8L)
  ))
  for (r in x) {
    cat(sprintf(
      "  - %s %s (%s)\n",
      r$assessment_system$id %||% "?",
      r$administration$year %||% "?",
      r$status %||% "?"
    ))
  }
  invisible(x)
}
