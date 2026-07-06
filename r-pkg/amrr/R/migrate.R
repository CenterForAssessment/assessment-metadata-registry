# Mechanical v1 -> v2 migration of Tier A sidecars (ADR-009 D6). Restamps
# schema_version, normalizes the assessment_type enum, and seeds the required
# enrollment block from cutscore keys. Never invents facts: optional v2 fields
# the v1 record lacks (scale_bounds, measurement.*, source_documents) are left
# absent for authoring to fill.

# Canonical assessment_type from v1 free strings / colleague vocabulary.
.migrate_assessment_type <- function(x) {
  map <- c(
    "state-summative" = "summative",
    "general" = "summative",
    "summative" = "summative",
    "english-language-proficiency" = "elp",
    "elp" = "elp",
    "alternate" = "alternate",
    "science" = "science",
    "end-of-course" = "end-of-course"
  )
  out <- unname(map[x])
  if (is.na(out)) {
    stop(sprintf("Cannot normalize assessment_type '%s' to the v2 enum; extend the map or fix the record.", x),
         call. = FALSE)
  }
  out
}

# Sort enrolled-grade strings in enrollment order: PK, K, then numeric.
.grade_order <- function(grades) {
  rank <- vapply(grades, function(g) {
    if (identical(g, "PK")) -2 else if (identical(g, "K")) -1 else suppressWarnings(as.numeric(g))
  }, numeric(1))
  grades[order(rank)]
}

# Normalize achievement levels to the canonical proficient_from label (ADR-010),
# replacing the legacy positional proficient[] mask. Deterministic and lossless
# for a monotonic mask (falses then trues); errors on a non-monotonic mask rather
# than guessing. A block already using proficient_from, or with no proficiency
# info, is left untouched.
.fold_proficient_from <- function(rec) {
  levels <- rec$achievement_levels
  if (is.null(levels)) return(rec)
  rec$achievement_levels <- lapply(levels, function(block) {
    if (!is.null(block[["proficient_from"]]) || is.null(block[["proficient"]])) return(block)
    labels <- unlist(block[["labels"]] %||% list())
    mask <- vapply(block[["proficient"]], as_logical_flag, logical(1))
    length(mask) <- length(labels)
    k <- which(mask)
    if (length(k)) {
      first <- k[[1]]
      tail_all <- all(mask[first:length(mask)], na.rm = TRUE)
      head_none <- !any(mask[seq_len(first - 1L)], na.rm = TRUE)
      if (!tail_all || !head_none) {
        stop("non-monotonic proficient[] mask; cannot fold to proficient_from (author manually).",
             call. = FALSE)
      }
      block[["proficient_from"]] <- labels[[first]]
    }
    block[["proficient"]] <- NULL
    block
  })
  rec
}

.migrate_assessment_record <- function(rec) {
  rec$schema_version <- "amr.assessment.v2"
  rec$assessment_system$assessment_type <-
    .migrate_assessment_type(rec$assessment_system$assessment_type)
  rec <- .fold_proficient_from(rec)  # emit canonical proficient_from (ADR-010)
  is_variable <- identical(rec$assessment_system$assessment_type, "elp")

  cutscores <- rec$cutscores %||% list()
  rec$content_areas <- lapply(rec$content_areas %||% list(), function(ca) {
    grades <- .grade_order(names(cutscores[[ca$id]] %||% list()))
    ca$enrollment <- list(
      intended_enrollment_grade = if (is_variable) "variable" else "fixed",
      enrolled_grades_tested = as.list(grades),
      note = if (length(grades)) {
        "Seeded by migrate_registry() from cutscore grade keys; review during authoring."
      } else {
        "No per-grade facts in the v1 record; populate enrolled_grades_tested during authoring."
      }
    )
    ca
  })
  rec
}

.migrate_accountability_record <- function(rec) {
  rec$schema_version <- "amr.accountability.v2"
  rec
}

.migrate_write <- function(path, rec) {
  rec[["_source_path"]] <- NULL
  txt <- jsonlite::toJSON(rec, pretty = 2, auto_unbox = TRUE, null = "null",
                          na = "null", digits = NA)
  writeLines(txt, path, useBytes = TRUE)
}

#' Migrate Tier A sidecars from v1 to v2 (ADR-009)
#'
#' Mechanically restamps every v1 sidecar under `<registry>/metadata/` to the v2
#' schemas: `schema_version` -> `amr.assessment.v2` / `amr.accountability.v2`,
#' `assessment_type` normalized to the canonical enum, and each content area's
#' required `enrollment` block seeded from its cutscore grade keys
#' (`intended_enrollment_grade` = `"variable"` for `elp` systems, `"fixed"`
#' otherwise -- review the seeded values during authoring). Optional v2 fields a
#' v1 record cannot supply (`scale_bounds`, `measurement.*`, `source_documents`)
#' are left absent: migration never invents facts.
#'
#' Intended use: run once, review the diff, commit the whole corpus in one
#' reviewed commit, then run [validate_registry()] (ADR-009 D6).
#'
#' @param registry Path to a registry checkout (the directory containing
#'   `metadata/`). Defaults to `option("amrr.registry")` then `AMRR_REGISTRY`.
#' @param to Target schema generation; only `"v2"` is supported.
#' @param write If `TRUE` (default), rewrite the sidecar files in place. Set
#'   `FALSE` for a dry run (report what would change without touching files).
#' @param quiet Suppress the per-file output.
#' @return Invisibly, a list with `n_migrated`, `n_skipped` (already v2), and
#'   `files` (relative paths rewritten or, dry-run, that would be).
#' @examples
#' \dontrun{
#' amrr::migrate_registry(".", write = FALSE)  # dry run
#' amrr::migrate_registry(".")                 # migrate, then review the diff
#' }
#' @export
migrate_registry <- function(registry = NULL, to = "v2", write = TRUE, quiet = FALSE) {
  if (!identical(to, "v2")) stop("Only to = 'v2' is supported.", call. = FALSE)
  root <- amrr_registry_root(registry)
  records <- read_all_records(root)
  if (!length(records)) stop("No sidecars under ", file.path(root, "metadata"), call. = FALSE)

  migrated <- character(0)
  skipped <- 0L
  for (rec in records) {
    sp <- rec[["_source_path"]]
    if (is_v2_record(rec)) {
      skipped <- skipped + 1L
      next
    }
    new_rec <- if (is_assessment_record(rec)) {
      .migrate_assessment_record(rec)
    } else if (is_accountability_record(rec)) {
      .migrate_accountability_record(rec)
    } else {
      stop(sprintf("%s: unknown schema_version %s", sp, sQuote(rec$schema_version %||% "NULL")),
           call. = FALSE)
    }
    if (isTRUE(write)) .migrate_write(file.path(root, sp), new_rec)
    migrated <- c(migrated, sp)
    if (!quiet) cat(sprintf("%s %s\n", if (isTRUE(write)) "migrated" else "would-migrate", sp))
  }
  if (!quiet) {
    cat(sprintf("\n%d file(s) %s, %d already v2.\n",
                length(migrated), if (isTRUE(write)) "migrated" else "would migrate", skipped))
    if (isTRUE(write) && length(migrated)) {
      cat("Review the diff, then run amrr::validate_registry('.') and commit the corpus in one reviewed commit.\n")
    }
  }
  invisible(list(n_migrated = length(migrated), n_skipped = skipped, files = migrated))
}
