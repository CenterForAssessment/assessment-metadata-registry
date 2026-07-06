# Thin accessors over a single resolved metadata record.

# Accept either a single record (a list with schema_version) or an amrr_metadata
# set of length 1, and return the single record.
as_record <- function(x) {
  if (is_assessment_record(x) || is_accountability_record(x)) return(x)
  if (inherits(x, "amrr_metadata")) {
    if (length(x) == 1L) return(x[[1]])
    stop("Expected a single record; the amrr_metadata set has ", length(x),
         " records. Index it first, e.g. x[[1]].", call. = FALSE)
  }
  stop("Not a metadata record or amrr_metadata object.", call. = FALSE)
}

#' Cutscores for a record
#'
#' @param x A metadata record or a length-1 [get_metadata()] result.
#' @param content_area Optional content-area id; if given, returns just that
#'   content area's cutscores (grade -> numeric vector of level lower bounds).
#' @return A named list of cutscores, or `NULL` if absent.
#' @export
amrr_cutscores <- function(x, content_area = NULL) {
  cuts <- as_record(x)$cutscores
  if (is.null(content_area)) cuts else cuts[[content_area]]
}

#' Achievement levels for a record
#'
#' @inheritParams amrr_cutscores
#' @return A named list of achievement-level blocks (`labels`, the canonical
#'   `proficient_from` label, and a derived boolean `proficient` mask), just the
#'   requested content area's block, or `NULL` if absent.
#' @details Canonical records carry `proficient_from` (ADR-010); for consumer
#'   backward compatibility this accessor also attaches the derived boolean
#'   `proficient` mask when only `proficient_from` is present.
#' @export
amrr_achievement_levels <- function(x, content_area = NULL) {
  levels <- as_record(x)$achievement_levels
  if (is.null(levels)) return(NULL)
  levels <- lapply(levels, function(block) {
    if (is.null(block[["proficient"]]) && !is.null(block[["proficient_from"]])) {
      block[["proficient"]] <- as.list(.proficient_mask(block))
    }
    block
  })
  if (is.null(content_area)) levels else levels[[content_area]]
}

#' Achievement targets for a record
#'
#' Requires the record to have been resolved with `attach_targets = TRUE` (the
#' [get_metadata()] default), since targets are authored in accountability
#' records and merged on at read time.
#'
#' @inheritParams amrr_cutscores
#' @return A named list of resolved target blocks (per content area), or the
#'   requested content area's target, or `NULL` if none.
#' @export
amrr_targets <- function(x, content_area = NULL) {
  targets <- as_record(x)$achievement_targets
  if (is.null(content_area)) targets else targets[[content_area]]
}

#' Comparability block for a record
#'
#' Year-resolved comparability to the prior administered year (scale breaks,
#' vendor changes, administration gaps).
#'
#' @param x A metadata record or a length-1 [get_metadata()] result.
#' @return The comparability list, or `NULL` if absent.
#' @export
amrr_comparability <- function(x) {
  as_record(x)$comparability
}

#' Operational vendor for a record's administration year
#'
#' @param x A metadata record or a length-1 [get_metadata()] result.
#' @return The vendor string, or `NA_character_` if absent.
#' @export
amrr_vendor <- function(x) {
  as_record(x)$administration$vendor %||% NA_character_
}

#' Enrollment-grade model for a record's content areas (v2)
#'
#' The ADR-009 enrollment block distinguishes the instrument's target
#' (`intended_enrollment_grade`: `"fixed"` or `"variable"`) from the enrolled
#' grades of students who sit it (`enrolled_grades_tested`). `NULL` on v1
#' records (the block is v2-only).
#'
#' @param x A metadata record or a length-1 [get_metadata()] result.
#' @param content_area Optional content-area id; if given, returns just that
#'   content area's enrollment block.
#' @return A named list (content area -> enrollment block), a single enrollment
#'   block, or `NULL` if absent.
#' @export
amrr_enrollment <- function(x, content_area = NULL) {
  rec <- as_record(x)
  out <- list()
  for (ca in rec$content_areas %||% list()) {
    if (!is.null(ca$enrollment)) out[[ca$id]] <- ca$enrollment
  }
  if (!length(out)) return(NULL)
  if (is.null(content_area)) out else out[[content_area]]
}

#' Scale bounds (loss/hoss) for a record (v2)
#'
#' `scale_bounds` mirrors `cutscores` keying exactly: content area -> enrolled
#' grade -> `{loss, hoss, source}` (ADR-009 D2).
#'
#' @inheritParams amrr_enrollment
#' @return A named list of scale-bound blocks, the requested content area's
#'   block (grade -> `{loss, hoss, source}`), or `NULL` if absent.
#' @export
amrr_scale_bounds <- function(x, content_area = NULL) {
  bounds <- as_record(x)$scale_bounds
  if (is.null(content_area)) bounds else bounds[[content_area]]
}

#' ELP measurement extension block (v2)
#'
#' Vendor/psychometric ELP facts (instrument, domains, composites + weights,
#' grade clusters, band scheme). Policy facts (exit criteria, growth targets,
#' timelines) are NOT here -- they live in the accountability record; see
#' [amrr_targets()], [amrr_growth_targets()], [amrr_timelines()].
#'
#' @param x A metadata record or a length-1 [get_metadata()] result.
#' @return The `measurement.elp` list, or `NULL` if absent.
#' @export
amrr_elp <- function(x) {
  (as_record(x)$measurement %||% list())$elp
}

#' Alternate-assessment measurement extension block (v2)
#'
#' Vendor/psychometric alternate facts (instrument, achievement standard,
#' scoring model, linkage levels). Participation criteria and the federal cap
#' are policy facts in the accountability record; see [amrr_participation()].
#'
#' @param x A metadata record or a length-1 [get_metadata()] result.
#' @return The `measurement.alternate` list, or `NULL` if absent.
#' @export
amrr_alternate <- function(x) {
  (as_record(x)$measurement %||% list())$alternate
}

#' Source documents for a record (v2)
#'
#' The evidence list beyond the primary `provenance.source_citation`.
#'
#' @param x A metadata record or a length-1 [get_metadata()] result.
#' @return A list of `{title, url}` entries, or `NULL` if absent.
#' @export
amrr_source_documents <- function(x) {
  as_record(x)$source_documents
}

#' Growth targets from an accountability record (v2)
#'
#' @param x An accountability metadata record.
#' @return A list of growth-target blocks, or `NULL` if absent.
#' @export
amrr_growth_targets <- function(x) {
  as_record(x)$growth_targets
}

#' Policy timelines from an accountability record (v2)
#'
#' Exit/on-time policy timelines (max years to exit, on-time rule, LTEL
#' definition).
#'
#' @param x An accountability metadata record.
#' @return The timelines list, or `NULL` if absent.
#' @export
amrr_timelines <- function(x) {
  as_record(x)$timelines
}

#' Participation policy from an accountability record (v2)
#'
#' Alternate-assessment participation criteria and the federal cap.
#'
#' @param x An accountability metadata record.
#' @return The participation list, or `NULL` if absent.
#' @export
amrr_participation <- function(x) {
  as_record(x)$participation
}
