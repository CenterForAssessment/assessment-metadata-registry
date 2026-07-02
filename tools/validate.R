#!/usr/bin/env Rscript
# Validate every registry sidecar (assessment + accountability).
#
# Routing is by `schema_version`:
#   amr.assessment_system.v1     -> assessment schema  + assessment invariants
#   sgpc.assessment_metadata.v0.1 (legacy alias)       -> assessment schema
#   amr.accountability_system.v1 -> accountability schema + accountability invariants
#
# Two layers of checks per file:
#   1. JSON Schema (shape + governance), via jsonvalidate (ajv). The schemas declare
#      Draft 2020-12 but use only draft-07-compatible vocabulary, so we normalize the
#      `$schema` line to draft-07 at load (ajv covers <= draft-07).
#   2. Registry invariants a schema cannot express:
#      Assessment:  filename == administration.id; path == metadata/<jur>/<system>/;
#                   cutscore count per grade == (labels - 1); cutscores monotonic.
#      Accountability: filename/path identity; every target (assessment_system_id,
#                   content_area) cross-links to an assessment record for the same
#                   jurisdiction + year that declares the content_area.
#      Both:        non-draft records carry provenance.source_citation.
#
# Exit non-zero on any failure. Deterministic; no network.

suppressWarnings(suppressMessages(library(jsonvalidate)))

.script_dir <- (function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(f[1]) else "tools"
})()
source(file.path(.script_dir, "_shared.R"))

# --- schema validators (ajv) -------------------------------------------------------
load_validator <- function(schema_path) {
  schema <- jsonlite::fromJSON(schema_path, simplifyVector = FALSE)
  schema[["$schema"]] <- "http://json-schema.org/draft-07/schema#"
  schema_str <- jsonlite::toJSON(schema, auto_unbox = TRUE, null = "null")
  jsonvalidate::json_validator(schema_str, engine = "ajv")
}

schema_errors <- function(validator, raw_json) {
  ok <- validator(raw_json, verbose = TRUE, greedy = TRUE)
  if (isTRUE(ok)) return(character(0))
  errs <- attr(ok, "errors")
  if (is.null(errs) || nrow(errs) == 0) return("schema: validation failed")
  loc_col <- intersect(c("instancePath", "dataPath", "schemaPath"), names(errs))[1]
  locs <- if (!is.na(loc_col)) errs[[loc_col]] else rep("", nrow(errs))
  msgs <- if ("message" %in% names(errs)) errs$message else rep("invalid", nrow(errs))
  vapply(seq_len(nrow(errs)), function(i) {
    at <- locs[i]
    at <- if (is.na(at) || !nzchar(at)) "<root>" else sub("^/", "", gsub("/", "/", at))
    sprintf("schema: %s (at %s)", msgs[i], at)
  }, character(1))
}

# --- registry invariants -----------------------------------------------------------
build_assessment_index <- function(records) {
  idx <- list()
  for (rec in records) {
    if (is_assessment(rec)) {
      key <- paste(rec$jurisdiction$id, rec$assessment_system$id,
                   rec$administration$year, sep = "")
      idx[[key]] <- unlist(lapply(rec$content_areas, function(ca) ca$id))
    }
  }
  idx
}

common_invariants <- function(path, rec, metadata_root, system_key) {
  errs <- character(0)
  admin <- rec$administration %||% list()
  jid <- rec$jurisdiction$id
  sysseg <- rec[[system_key]]$id
  admin_id <- admin$id
  stem <- tools::file_path_sans_ext(basename(path))
  if (!is.null(admin_id) && !identical(stem, admin_id)) {
    errs <- c(errs, sprintf("filename '%s' != administration.id '%s'", stem, admin_id))
  }
  expected <- file.path(metadata_root, jid, sysseg)
  if (!identical(normalizePath(dirname(path), mustWork = FALSE),
                 normalizePath(expected, mustWork = FALSE))) {
    errs <- c(errs, sprintf("path %s != identity path %s", dirname(path), expected))
  }
  year <- admin$year
  if (!is.null(year) && !is.null(admin_id) &&
      !endsWith(admin_id, as.character(year))) {
    errs <- c(errs, sprintf("administration.id '%s' does not end with year '%s'",
                            admin_id, year))
  }
  if (isTRUE(rec$status %in% c("reviewed", "verified", "deprecated"))) {
    if (is.null((rec$provenance %||% list())$source_citation)) {
      errs <- c(errs, sprintf("status '%s' requires provenance.source_citation", rec$status))
    }
  }
  errs
}

assessment_invariants <- function(path, rec, metadata_root) {
  errs <- common_invariants(path, rec, metadata_root, "assessment_system")
  levels <- rec$achievement_levels %||% list()
  cutscores <- rec$cutscores %||% list()
  for (ca in names(cutscores)) {
    labels <- (levels[[ca]] %||% list())$labels %||% list()
    n_labels <- length(labels)
    expected_cuts <- if (n_labels) n_labels - 1L else NA_integer_
    grades <- cutscores[[ca]] %||% list()
    for (grade in names(grades)) {
      cuts <- as.numeric(unlist(grades[[grade]]))
      if (!is.na(expected_cuts) && length(cuts) != expected_cuts) {
        errs <- c(errs, sprintf("cutscores[%s][%s] has %d cut(s); achievement_levels implies %d",
                                ca, grade, length(cuts), expected_cuts))
      }
      if (length(cuts) > 1 && any(cuts[-length(cuts)] > cuts[-1])) {
        errs <- c(errs, sprintf("cutscores[%s][%s] not monotonic: %s",
                                ca, grade, paste(cuts, collapse = ", ")))
      }
    }
  }
  errs
}

accountability_invariants <- function(path, rec, metadata_root, assessment_index) {
  errs <- common_invariants(path, rec, metadata_root, "accountability_system")
  jid <- rec$jurisdiction$id
  year <- (rec$administration %||% list())$year
  targets <- rec$targets %||% list()
  for (i in seq_along(targets)) {
    tgt <- targets[[i]]
    sid <- tgt$assessment_system_id
    ca <- tgt$content_area
    key <- paste(jid, sid, year, sep = "")
    if (is.null(assessment_index[[key]])) {
      errs <- c(errs, sprintf("targets[%d] cross-link (%s, %s) has no assessment record",
                              i - 1L, sid, year))
    } else if (!(ca %in% assessment_index[[key]])) {
      errs <- c(errs, sprintf("targets[%d] content_area '%s' not in assessment %s %s (has: %s)",
                              i - 1L, ca, sid, year,
                              paste(sort(assessment_index[[key]]), collapse = ", ")))
    }
  }
  errs
}

# --- main --------------------------------------------------------------------------
main <- function(argv) {
  opts <- parse_args(argv, list(metadata = "metadata", `schema-dir` = "schemas"))
  schema_dir <- opts[["schema-dir"]]
  metadata_root <- opts[["metadata"]]

  assess_validator <- load_validator(file.path(schema_dir, "amr.assessment_system.v1.schema.json"))
  acct_validator <- load_validator(file.path(schema_dir, "amr.accountability_system.v1.schema.json"))

  files <- sort(list.files(metadata_root, pattern = "\\.json$",
                           recursive = TRUE, full.names = TRUE), method = "radix")
  if (!length(files)) {
    message(sprintf("No sidecars under %s", metadata_root))
    return(1L)
  }

  raws <- lapply(files, function(f) paste(readLines(f, warn = FALSE), collapse = "\n"))
  parsed <- lapply(raws, function(r) tryCatch(jsonlite::fromJSON(r, simplifyVector = FALSE),
                                              error = function(e) e))
  bad <- which(vapply(parsed, function(x) inherits(x, "error"), logical(1)))
  if (length(bad)) {
    cat(sprintf("FAIL %s: invalid JSON: %s\n", files[bad[1]], conditionMessage(parsed[[bad[1]]])))
    return(1L)
  }

  assessment_index <- build_assessment_index(parsed)
  total_errors <- 0L

  for (i in seq_along(files)) {
    path <- files[i]; rec <- parsed[[i]]
    sv <- rec$schema_version
    if (isTRUE(sv %in% ASSESSMENT_SCHEMAS)) {
      errs <- c(schema_errors(assess_validator, raws[[i]]),
                assessment_invariants(path, rec, metadata_root))
    } else if (identical(sv, ACCT_SCHEMA)) {
      errs <- c(schema_errors(acct_validator, raws[[i]]),
                accountability_invariants(path, rec, metadata_root, assessment_index))
    } else {
      errs <- sprintf("unknown schema_version: %s", if (is.null(sv)) "NULL" else shQuote(sv))
    }

    if (length(errs)) {
      cat(sprintf("FAIL %s\n", path))
      for (e in errs) cat(sprintf("     - %s\n", e))
      total_errors <- total_errors + length(errs)
    } else {
      cat(sprintf("ok   %s\n", path))
    }
  }

  cat(sprintf("\n%d file(s) checked, %d error(s).\n", length(files), total_errors))
  if (total_errors) 1L else 0L
}

quit(status = main(commandArgs(trailingOnly = TRUE)), save = "no")
