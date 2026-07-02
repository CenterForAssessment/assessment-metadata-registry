# Merge accountability achievement targets onto an assessment record, resolving
# each to per-grade scale-score thresholds. Targets are authored in accountability
# records (ADR-002); consumers see them re-merged here under achievement_targets.

# Coerce a proficiency flag (logical, or "true"/"false" string) to logical.
as_logical_flag <- function(x) {
  if (is.logical(x)) return(isTRUE(x))
  isTRUE(tolower(as.character(x)) %in% c("true", "1", "yes"))
}

# Resolve a basis="proficiency_boundary" target to per-grade scale scores from the
# assessment record's own cutscores + proficient mask: the scale score entering the
# first proficient level. Returns a named list grade -> number, or NULL if it
# cannot be resolved (no proficient level, or the first level is proficient).
resolve_proficiency_boundary <- function(record, content_area) {
  levels <- record$achievement_levels[[content_area]]
  cuts <- record$cutscores[[content_area]]
  if (is.null(levels) || is.null(cuts) || is.null(levels$proficient)) {
    return(NULL)
  }
  proficient <- vapply(levels$proficient, as_logical_flag, logical(1))
  k <- which(proficient)
  if (length(k) == 0L) return(NULL)
  k <- k[[1]]                       # first proficient level (1-based)
  if (k < 2L) return(NULL)          # cut k-1 is the boundary entering level k
  out <- list()
  for (grade in names(cuts)) {
    g_cuts <- cuts[[grade]]
    if (length(g_cuts) >= (k - 1L)) {
      out[[grade]] <- as.numeric(g_cuts[[k - 1L]])
    }
  }
  if (length(out) == 0L) NULL else out
}

# Resolve one target (from an accountability record) to a merged target block.
resolve_target <- function(record, target) {
  basis <- target$basis
  per_grade <- switch(
    basis,
    scale_score = target$per_grade_scale_score,
    proficiency_boundary = resolve_proficiency_boundary(record, target$content_area),
    stop(sprintf("Unsupported target basis '%s' (content_area %s)",
                 basis %||% "<none>", target$content_area), call. = FALSE)
  )
  list(
    label = target$label,
    semantics = target$semantics,
    basis = basis,
    comparison = target$comparison %||% ">=",
    per_grade_scale_score = per_grade,
    provenance = target$provenance,
    resolved_from = if (identical(basis, "proficiency_boundary")) "cutscores" else "explicit"
  )
}

# Attach all cross-linked accountability targets to an assessment record.
attach_targets_to_record <- function(record, accountability_records) {
  jid <- record$jurisdiction$id
  yr <- as.character(record$administration$year)
  sid <- record$assessment_system$id

  merged <- record$achievement_targets %||% list()
  for (acct in accountability_records) {
    if (!identical(acct$jurisdiction$id, jid)) next
    if (!identical(as.character(acct$administration$year), yr)) next
    for (target in acct$targets %||% list()) {
      if (!identical(target$assessment_system_id, sid)) next
      merged[[target$content_area]] <- resolve_target(record, target)
    }
  }
  if (length(merged) > 0L) {
    record$achievement_targets <- merged
  }
  record
}
