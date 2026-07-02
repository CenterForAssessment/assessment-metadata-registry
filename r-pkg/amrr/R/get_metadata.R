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
#' @param registry Optional path to a registry checkout (the directory containing
#'   `metadata/`, or that directory itself). Defaults to `option("amrr.registry")`
#'   then the `AMRR_REGISTRY` environment variable.
#' @param ref Optional commit SHA to pin to. If the checkout's `HEAD` differs, a
#'   warning is issued and the working tree is read as-is (checkout the ref
#'   yourself to guarantee bytes).
#' @param attach_targets Merge resolved accountability targets onto each
#'   assessment record? Defaults to `TRUE`.
#'
#' @return An object of class `amrr_metadata`: a list of assessment-metadata
#'   records, with attributes `registry_ref`, `registry_root`, and `jurisdiction`.
#' @examples
#' \dontrun{
#' md <- get_metadata("IN", system = "wida-access", year = 2024,
#'                    registry = "~/GitHub/CenterForAssessment/assessment-metadata-registry")
#' amrr_registry_ref(md)
#' amrr_targets(md[[1]], "ELP_COMPOSITE")
#' }
#' @export
get_metadata <- function(jurisdiction, system = NULL, year = NULL,
                         registry = NULL, ref = NULL, attach_targets = TRUE) {
  if (missing(jurisdiction) || !is.character(jurisdiction) || length(jurisdiction) != 1L) {
    stop("jurisdiction must be a single string", call. = FALSE)
  }
  root <- amrr_registry_root(registry)
  sha <- amrr_git_sha_of(root)
  if (!is.null(ref) && !is.na(sha) && !identical(ref, sha)) {
    warning(sprintf(
      "registry HEAD (%s) != requested ref (%s); reading working tree as-is.",
      substr(sha, 1L, 8L), substr(ref, 1L, 8L)
    ), call. = FALSE)
  }

  records <- read_jurisdiction_records(root, jurisdiction)
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
