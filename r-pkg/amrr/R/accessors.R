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
#' @return A named list of achievement-level blocks (labels + proficient mask), or
#'   just the requested content area's block, or `NULL` if absent.
#' @export
amrr_achievement_levels <- function(x, content_area = NULL) {
  levels <- as_record(x)$achievement_levels
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
