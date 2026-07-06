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

# Accepted schema_version strings. v1 (and the legacy SGPc alias) remain valid
# during the ADR-009 D6 dual-version migration window; v2 is canonical.
ASSESSMENT_SCHEMAS <- c("amr.assessment.v2",
                        "amr.assessment_system.v1", "sgpc.assessment_metadata.v0.1")
ACCOUNTABILITY_SCHEMAS <- c("amr.accountability.v2", "amr.accountability_system.v1")

# Sentinel cut key for end-of-course assessments (ADR-010): an EOC standard is
# instrument-level, not grade-specific, so its cutscores/scale_bounds may be keyed
# once under this key instead of copied across every enrolled grade. The validator
# permits it only when assessment_type = "end-of-course".
INSTRUMENT_LEVEL_KEY <- "eoc"

is_assessment_record <- function(r) {
  is.list(r) && !is.null(r$schema_version) && r$schema_version %in% ASSESSMENT_SCHEMAS
}

is_accountability_record <- function(r) {
  is.list(r) && !is.null(r$schema_version) && r$schema_version %in% ACCOUNTABILITY_SCHEMAS
}

# TRUE when a record carries a v2 schema_version (either record type).
is_v2_record <- function(r) {
  is.list(r) && !is.null(r$schema_version) && grepl("\\.v2$", r$schema_version)
}
