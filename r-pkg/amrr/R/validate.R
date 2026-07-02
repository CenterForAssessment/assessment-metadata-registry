# Validate every registry sidecar: JSON Schema (via jsonvalidate/ajv) + the
# registry invariants a schema cannot express. Ported from the former Python
# tools/validate.py (ADR-004).

# jsonvalidate's ajv engine covers <= draft-07; the schemas declare Draft 2020-12
# but use only draft-07-compatible vocabulary, so normalize $schema at load.
.load_validator <- function(schema_path) {
  schema <- jsonlite::fromJSON(schema_path, simplifyVector = FALSE)
  schema[["$schema"]] <- "http://json-schema.org/draft-07/schema#"
  schema_str <- jsonlite::toJSON(schema, auto_unbox = TRUE, null = "null")
  jsonvalidate::json_validator(schema_str, engine = "ajv")
}

.schema_errors <- function(validator, raw_json) {
  ok <- validator(raw_json, verbose = TRUE, greedy = TRUE)
  if (isTRUE(ok)) return(character(0))
  errs <- attr(ok, "errors")
  if (is.null(errs) || nrow(errs) == 0L) return("schema: validation failed")
  loc_col <- intersect(c("instancePath", "dataPath", "schemaPath"), names(errs))[1]
  locs <- if (!is.na(loc_col)) errs[[loc_col]] else rep("", nrow(errs))
  msgs <- if ("message" %in% names(errs)) errs$message else rep("invalid", nrow(errs))
  vapply(seq_len(nrow(errs)), function(i) {
    at <- locs[i]
    at <- if (is.na(at) || !nzchar(at)) "<root>" else sub("^/", "", at)
    sprintf("schema: %s (at %s)", msgs[i], at)
  }, character(1))
}

.build_assessment_index <- function(records) {
  idx <- list()
  for (rec in records) if (is_assessment_record(rec)) {
    key <- paste(rec$jurisdiction$id, rec$assessment_system$id,
                 rec$administration$year, sep = .amrr_sep)
    idx[[key]] <- unlist(lapply(rec$content_areas, function(ca) ca$id))
  }
  idx
}

.common_invariants <- function(sp, rec, system_key) {
  errs <- character(0)
  admin <- rec$administration %||% list()
  jid <- rec$jurisdiction$id
  sysseg <- rec[[system_key]]$id
  admin_id <- admin$id
  stem <- tools::file_path_sans_ext(basename(sp))
  if (!is.null(admin_id) && !identical(stem, admin_id)) {
    errs <- c(errs, sprintf("filename '%s' != administration.id '%s'", stem, admin_id))
  }
  expected <- file.path("metadata", jid, sysseg)
  if (!identical(dirname(sp), expected)) {
    errs <- c(errs, sprintf("path %s != identity path %s", dirname(sp), expected))
  }
  year <- admin$year
  if (!is.null(year) && !is.null(admin_id) && !endsWith(admin_id, as.character(year))) {
    errs <- c(errs, sprintf("administration.id '%s' does not end with year '%s'", admin_id, year))
  }
  if (isTRUE(rec$status %in% c("reviewed", "verified", "deprecated"))) {
    if (is.null((rec$provenance %||% list())$source_citation)) {
      errs <- c(errs, sprintf("status '%s' requires provenance.source_citation", rec$status))
    }
  }
  errs
}

.assessment_invariants <- function(sp, rec) {
  errs <- .common_invariants(sp, rec, "assessment_system")
  levels <- rec$achievement_levels %||% list()
  cutscores <- rec$cutscores %||% list()
  for (ca in names(cutscores)) {
    labels <- (levels[[ca]] %||% list())$labels %||% list()
    n_labels <- length(labels)
    expected_cuts <- if (n_labels) n_labels - 1L else NA_integer_
    for (grade in names(cutscores[[ca]] %||% list())) {
      cuts <- as.numeric(unlist(cutscores[[ca]][[grade]]))
      if (!is.na(expected_cuts) && length(cuts) != expected_cuts) {
        errs <- c(errs, sprintf("cutscores[%s][%s] has %d cut(s); achievement_levels implies %d",
                                ca, grade, length(cuts), expected_cuts))
      }
      if (length(cuts) > 1L && any(cuts[-length(cuts)] > cuts[-1])) {
        errs <- c(errs, sprintf("cutscores[%s][%s] not monotonic: %s",
                                ca, grade, paste(cuts, collapse = ", ")))
      }
    }
  }
  errs
}

.accountability_invariants <- function(sp, rec, assessment_index) {
  errs <- .common_invariants(sp, rec, "accountability_system")
  jid <- rec$jurisdiction$id
  year <- (rec$administration %||% list())$year
  targets <- rec$targets %||% list()
  for (i in seq_along(targets)) {
    tgt <- targets[[i]]
    key <- paste(jid, tgt$assessment_system_id, year, sep = .amrr_sep)
    if (is.null(assessment_index[[key]])) {
      errs <- c(errs, sprintf("targets[%d] cross-link (%s, %s) has no assessment record",
                              i - 1L, tgt$assessment_system_id, year))
    } else if (!(tgt$content_area %in% assessment_index[[key]])) {
      errs <- c(errs, sprintf("targets[%d] content_area '%s' not in assessment %s %s (has: %s)",
                              i - 1L, tgt$content_area, tgt$assessment_system_id, year,
                              paste(sort(assessment_index[[key]]), collapse = ", ")))
    }
  }
  errs
}

#' Validate every registry sidecar (Tier A gate)
#'
#' Checks each authored sidecar under `<registry>/metadata/` against its JSON
#' Schema (via \pkg{jsonvalidate}) plus the registry invariants a schema cannot
#' express: filename/path identity, cutscore count vs. achievement levels,
#' monotonic cutscores, accountability cross-links, and a `source_citation` on
#' non-draft records.
#'
#' @param registry Path to a registry checkout (the directory containing
#'   `metadata/` and `schemas/`). Defaults to `option("amrr.registry")` then the
#'   `AMRR_REGISTRY` environment variable (see [get_metadata()]).
#' @param schema_dir Directory of JSON Schemas. Defaults to `<registry>/schemas`.
#' @param quiet Suppress the per-file `ok`/`FAIL` output.
#' @param error If `TRUE` (default), stop with an error when any file fails, so a
#'   CLI call (`Rscript -e 'amrr::validate_registry(".")'`) exits non-zero. Set
#'   `FALSE` to return the report instead.
#' @return Invisibly, a list with `n_files`, `n_errors`, and `results` (a named
#'   list mapping each failing file to its error messages).
#' @examples
#' \dontrun{
#' amrr::validate_registry(".")
#' }
#' @export
validate_registry <- function(registry = NULL, schema_dir = NULL,
                              quiet = FALSE, error = TRUE) {
  need_pkgs("jsonvalidate")
  root <- amrr_registry_root(registry)
  schema_dir <- schema_dir %||% file.path(root, "schemas")

  assess_v <- .load_validator(file.path(schema_dir, "amr.assessment_system.v1.schema.json"))
  acct_v <- .load_validator(file.path(schema_dir, "amr.accountability_system.v1.schema.json"))

  records <- read_all_records(root)
  if (!length(records)) stop("No sidecars under ", file.path(root, "metadata"), call. = FALSE)
  assessment_index <- .build_assessment_index(records)

  results <- list()
  total_errors <- 0L
  for (rec in records) {
    sp <- rec[["_source_path"]]
    raw <- paste(readLines(file.path(root, sp), warn = FALSE), collapse = "\n")
    sv <- rec$schema_version
    if (is_assessment_record(rec)) {
      errs <- c(.schema_errors(assess_v, raw), .assessment_invariants(sp, rec))
    } else if (is_accountability_record(rec)) {
      errs <- c(.schema_errors(acct_v, raw), .accountability_invariants(sp, rec, assessment_index))
    } else {
      errs <- sprintf("unknown schema_version: %s", if (is.null(sv)) "NULL" else sQuote(sv))
    }
    if (length(errs)) {
      results[[sp]] <- errs
      total_errors <- total_errors + length(errs)
      if (!quiet) {
        cat(sprintf("FAIL %s\n", sp))
        for (e in errs) cat(sprintf("     - %s\n", e))
      }
    } else if (!quiet) {
      cat(sprintf("ok   %s\n", sp))
    }
  }
  if (!quiet) {
    cat(sprintf("\n%d file(s) checked, %d error(s).\n", length(records), total_errors))
  }
  if (error && total_errors > 0L) {
    stop(sprintf("%d validation error(s) across %d file(s).", total_errors, length(results)),
         call. = FALSE)
  }
  invisible(list(n_files = length(records), n_errors = total_errors, results = results))
}
