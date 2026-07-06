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
  if (is_v2_record(rec)) errs <- c(errs, .v2_assessment_invariants(rec))
  errs
}

# v2-only invariants (ADR-009): the enrollment axis rule and the scale envelope.
# Grade keys on cutscores / scale_bounds / cutscores_source are enrolled grades
# and must be within each content area's enrolled_grades_tested; where both a
# scale envelope and cuts exist: loss <= min(cuts) <= max(cuts) <= hoss.
.v2_assessment_invariants <- function(rec) {
  errs <- character(0)
  cutscores <- rec$cutscores %||% list()
  bounds <- rec$scale_bounds %||% list()
  cut_src <- rec$cutscores_source %||% list()

  enrolled <- list()
  for (ca in rec$content_areas %||% list()) {
    enrolled[[ca$id]] <- as.character(unlist((ca$enrollment %||% list())$enrolled_grades_tested))
  }

  check_keys <- function(block, block_name) {
    out <- character(0)
    for (ca in names(block)) {
      if (is.null(enrolled[[ca]])) {
        out <- c(out, sprintf("%s[%s] has no matching content_areas entry", block_name, ca))
        next
      }
      extra <- setdiff(names(block[[ca]] %||% list()), enrolled[[ca]])
      if (length(extra)) {
        out <- c(out, sprintf(
          "%s[%s] grade key(s) not in enrollment.enrolled_grades_tested: %s (axis rule: keys are enrolled grades)",
          block_name, ca, paste(sort(extra), collapse = ", ")))
      }
    }
    out
  }
  errs <- c(errs, check_keys(cutscores, "cutscores"),
            check_keys(bounds, "scale_bounds"),
            check_keys(cut_src, "cutscores_source"))

  for (ca in names(cut_src)) {
    extra <- setdiff(names(cut_src[[ca]] %||% list()), names(cutscores[[ca]] %||% list()))
    if (length(extra)) {
      errs <- c(errs, sprintf("cutscores_source[%s] has grade(s) with no cutscores: %s",
                              ca, paste(sort(extra), collapse = ", ")))
    }
  }

  for (ca in names(bounds)) {
    for (grade in names(bounds[[ca]] %||% list())) {
      b <- bounds[[ca]][[grade]]
      loss <- as.numeric(b$loss %||% NA)
      hoss <- as.numeric(b$hoss %||% NA)
      if (!is.na(loss) && !is.na(hoss) && loss > hoss) {
        errs <- c(errs, sprintf("scale_bounds[%s][%s] loss %s > hoss %s", ca, grade, loss, hoss))
      }
      cuts <- as.numeric(unlist((cutscores[[ca]] %||% list())[[grade]]))
      if (length(cuts)) {
        if (!is.na(loss) && loss > min(cuts)) {
          errs <- c(errs, sprintf("scale_bounds[%s][%s] loss %s > min(cutscores) %s",
                                  ca, grade, loss, min(cuts)))
        }
        if (!is.na(hoss) && max(cuts) > hoss) {
          errs <- c(errs, sprintf("scale_bounds[%s][%s] hoss %s < max(cutscores) %s",
                                  ca, grade, hoss, max(cuts)))
        }
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
#' non-draft records. v1 and v2 records are routed to their respective schemas
#' (dual-version window, ADR-009); v2 records additionally get the enrollment
#' axis rule (cutscore/scale-bound grade keys must be enrolled grades) and the
#' scale-envelope invariant (`loss <= min(cuts) <= max(cuts) <= hoss`). Once any
#' v2 record exists, remaining v1 records raise a migration warning.
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

  assess_v1 <- .load_validator(file.path(schema_dir, "amr.assessment_system.v1.schema.json"))
  acct_v1 <- .load_validator(file.path(schema_dir, "amr.accountability_system.v1.schema.json"))
  # v2 schemas (ADR-009). Optional so pre-v2 fixture registries keep validating.
  assess_v2_path <- file.path(schema_dir, "amr.assessment.v2.schema.json")
  acct_v2_path <- file.path(schema_dir, "amr.accountability.v2.schema.json")
  assess_v2 <- if (file.exists(assess_v2_path)) .load_validator(assess_v2_path) else NULL
  acct_v2 <- if (file.exists(acct_v2_path)) .load_validator(acct_v2_path) else NULL

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
      sval <- if (is_v2_record(rec)) assess_v2 else assess_v1
      errs <- if (is.null(sval)) {
        sprintf("schema_version %s but amr.assessment.v2.schema.json not found in %s",
                sQuote(sv), schema_dir)
      } else {
        c(.schema_errors(sval, raw), .assessment_invariants(sp, rec))
      }
    } else if (is_accountability_record(rec)) {
      sval <- if (is_v2_record(rec)) acct_v2 else acct_v1
      errs <- if (is.null(sval)) {
        sprintf("schema_version %s but amr.accountability.v2.schema.json not found in %s",
                sQuote(sv), schema_dir)
      } else {
        c(.schema_errors(sval, raw), .accountability_invariants(sp, rec, assessment_index))
      }
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
  # Dual-version window nudge (ADR-009 D6): once the corpus has begun the v2
  # migration, any remaining v1 record is a warning (never an error) so the
  # window closes instead of drifting.
  n_v1 <- sum(vapply(records, function(r) !is_v2_record(r), logical(1)))
  n_v2 <- length(records) - n_v1
  if (n_v1 > 0L && n_v2 > 0L) {
    warning(sprintf(
      "dual-version window: %d record(s) still v1 alongside %d v2 record(s); migrate with amrr::migrate_registry().",
      n_v1, n_v2), call. = FALSE)
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
