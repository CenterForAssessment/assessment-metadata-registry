#' amrr: Assessment Metadata Registry client
#'
#' Reads the Assessment Metadata Registry (annual JSON sidecars for
#' assessment-system and accountability-system metadata) into R objects, one
#' jurisdiction/system/year at a time. The canonical source is a local registry
#' checkout, pinnable by commit SHA; a published static bundle is the remote
#' fallback. Accountability achievement targets can be re-merged onto the
#' assessment record for consumers that expect them together (see
#' [get_metadata()]).
#'
#' @keywords internal
"_PACKAGE"

# Internal null-coalescing helper (kept ASCII; not exported).
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

ASSESSMENT_SCHEMAS <- c("amr.assessment_system.v1", "sgpc.assessment_metadata.v0.1")
ACCOUNTABILITY_SCHEMA <- "amr.accountability_system.v1"

is_assessment_record <- function(r) {
  is.list(r) && !is.null(r$schema_version) && r$schema_version %in% ASSESSMENT_SCHEMAS
}

is_accountability_record <- function(r) {
  is.list(r) && identical(r$schema_version, ACCOUNTABILITY_SCHEMA)
}
