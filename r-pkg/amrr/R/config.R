# The compact "assessment config" view (ADR-010). A lens that projects canonical
# v2 sidecars into the DRY authoring shape proposed by the colleague's
# amr.assessment_config.v1 -- reusable named level_schemes, tests keyed by content
# area, a content_area x grade -> test map, and unified per-grade cuts
# ({loss, hoss, values}) -- and back. The registry stays normalized v2; this is an
# ergonomic surface for authoring and review, not a second source of truth
# (ADR-008 tier-3). Extension blocks (measurement.*), provenance, comparability,
# and source_documents are intentionally dropped by the projection.

CONFIG_SCHEMA <- "amr.assessment_config.v1"

# Deterministic, readable scheme name: general_<n>, disambiguated on collision.
.config_scheme_name <- function(n_levels, taken) {
  base <- paste0("general_", n_levels)
  if (!(base %in% taken)) return(base)
  i <- 2L
  while (paste0(base, "_", i) %in% taken) i <- i + 1L
  paste0(base, "_", i)
}

# Slug a content-area id into a test id (colleague style: lowercase).
.config_test_id <- function(ca_id) tolower(gsub("[^A-Za-z0-9]+", "_", ca_id))

.collect_assessment_records <- function(x) {
  recs <- if (inherits(x, "amrr_metadata")) unclass(x) else x
  if (is_assessment_record(recs)) recs <- list(recs)
  recs <- Filter(is_assessment_record, recs)
  if (!length(recs)) stop("No assessment records found in `x`.", call. = FALSE)
  recs
}

#' Project registry records into the compact assessment-config view (ADR-010)
#'
#' Renders one jurisdiction x assessment-system's records into the compact, DRY
#' authoring shape from the colleague spec (`amr.assessment_config.v1`): reusable
#' named `level_schemes`, `tests` keyed by content area, a
#' `content_area -> grade -> test` `map`, and unified per-grade `cuts`
#' (`{loss, hoss, values}`). This is a *lens* on the canonical v2 sidecars, not a
#' replacement -- extension blocks (`measurement.*`), provenance, comparability,
#' and source documents are intentionally dropped. Use [read_config()] for the
#' inverse.
#'
#' A config describes one program (= one assessment system). Cuts/levels are a
#' single-year snapshot; `years$tested_years` records the full span present.
#'
#' @param x An `amrr_metadata` set or list of assessment records for a single
#'   jurisdiction and assessment system (multiple years allowed).
#' @param year Snapshot year for `tests`/`cuts` (default: the latest present).
#' @return A named list with the config shape (`schema_version`, `jurisdiction`,
#'   `program`, `level_schemes`, `tests`, `map`, `years`).
#' @seealso [read_config()]
#' @export
as_config <- function(x, year = NULL) {
  recs <- .collect_assessment_records(x)

  jids <- unique(vapply(recs, function(r) r$jurisdiction$id, character(1)))
  sids <- unique(vapply(recs, function(r) r$assessment_system$id, character(1)))
  if (length(jids) != 1L || length(sids) != 1L) {
    stop("as_config() describes one jurisdiction x assessment system; got ",
         length(jids), " jurisdiction(s) and ", length(sids), " system(s). Filter `x` first.",
         call. = FALSE)
  }

  years <- sort(unique(vapply(recs, function(r) as.integer(r$administration$year), integer(1))))
  snap_year <- if (is.null(year)) max(years) else as.integer(year)
  snap <- Filter(function(r) as.integer(r$administration$year) == snap_year, recs)
  if (!length(snap)) stop("No record for snapshot year ", snap_year, ".", call. = FALSE)
  rec <- snap[[1]]

  jur <- rec$jurisdiction
  sys_ <- rec$assessment_system
  adm <- rec$administration
  program <- list(
    id = sys_$id, name = sys_$name, family = sys_$family, type = sys_$assessment_type,
    year = snap_year,
    umbrella_name = (rec$assessment_program %||% list())$assessment_name %||% sys_$name,
    administration_id = adm$id, vendor = adm$vendor
  )

  cutscores <- rec$cutscores %||% list()
  bounds <- rec$scale_bounds %||% list()
  levels <- rec$achievement_levels %||% list()

  level_schemes <- list()
  scheme_key_to_name <- list()     # "labels...@proficient_from" -> scheme name
  tests <- list()
  map <- list()

  for (ca in rec$content_areas %||% list()) {
    ca_id <- ca$id
    tid <- .config_test_id(ca_id)
    block <- levels[[ca_id]] %||% list()
    labels <- block[["labels"]] %||% list()
    pfrom <- block[["proficient_from"]]

    scheme_name <- NA_character_
    if (length(labels)) {
      key <- paste0(paste(unlist(labels), collapse = "|"), "@", pfrom %||% "")
      scheme_name <- scheme_key_to_name[[key]]
      if (is.null(scheme_name)) {
        scheme_name <- .config_scheme_name(length(labels), names(level_schemes))
        scheme <- list(labels = labels)
        if (!is.null(pfrom)) scheme$proficient_from <- pfrom
        level_schemes[[scheme_name]] <- scheme
        scheme_key_to_name[[key]] <- scheme_name
      }
    }

    # unified per-grade cuts: {loss, hoss, values}
    cut_keys <- union(names(cutscores[[ca_id]] %||% list()), names(bounds[[ca_id]] %||% list()))
    cuts <- list()
    for (g in cut_keys) {
      entry <- list()
      sb <- (bounds[[ca_id]] %||% list())[[g]]
      if (!is.null(sb$loss)) entry$loss <- sb$loss
      if (!is.null(sb$hoss)) entry$hoss <- sb$hoss
      vals <- (cutscores[[ca_id]] %||% list())[[g]]
      if (!is.null(vals)) entry$values <- vals
      cuts[[g]] <- entry
    }

    enr <- (ca$enrollment %||% list())
    enr_grades <- as.character(unlist(enr$enrolled_grades_tested))
    intended <- if (identical(names(cuts), INSTRUMENT_LEVEL_KEY) || !length(enr_grades)) {
      "not_grade_bound"
    } else {
      as.list(enr_grades)
    }

    tests[[tid]] <- list(
      label = ca$label %||% ca_id,
      content_area = ca_id,
      intended_grades = intended,
      # v2 carries the fixed|variable axis (ADR-009) that the colleague's
      # intended_grades alone cannot express (ILEARN tests grades 3-8 yet is
      # "fixed"); the config view preserves it so the round-trip is lossless.
      intended_enrollment_grade = enr$intended_enrollment_grade,
      vendor = adm$vendor,
      level_scheme = scheme_name,
      scale = list(name = ca$scale_name, vertical = isTRUE(ca$vertical_scale)),
      cuts = cuts
    )

    # map: content_area x enrolled grade -> test id
    if (length(enr_grades)) {
      m <- list()
      for (g in enr_grades) m[[g]] <- tid
      map[[ca_id]] <- m
    }
  }

  list(
    schema_version = CONFIG_SCHEMA,
    jurisdiction = jur,
    program = program,
    level_schemes = level_schemes,
    tests = tests,
    map = map,
    years = list(tested_years = as.list(years))
  )
}

#' Expand a compact assessment-config back into a v2 record (ADR-010)
#'
#' The inverse of [as_config()]: reconstructs the canonical `amr.assessment.v2`
#' assessment record for the config's snapshot year -- resolving `level_scheme`
#' references, splitting unified `cuts` back into `cutscores` + `scale_bounds`,
#' and rebuilding each content area's `enrollment` from the `map`. Returns an
#' in-memory record (it does not write a sidecar); blocks the config view drops
#' (`measurement.*`, provenance, comparability, source_documents) are not
#' reconstructed, so a config round-trip preserves the *core* facts, not byte
#' identity. Validate the result with [validate_registry()] before authoring.
#'
#' @param config A config list from [as_config()] (or the colleague's
#'   `amr.assessment_config.v1` shape).
#' @return A single `amr.assessment.v2` assessment record (a named list).
#' @seealso [as_config()]
#' @export
read_config <- function(config) {
  if (!identical(config$schema_version, CONFIG_SCHEMA)) {
    stop("Not an ", CONFIG_SCHEMA, " config (schema_version = ",
         sQuote(config$schema_version %||% "NULL"), ").", call. = FALSE)
  }
  prog <- config$program
  jur <- config$jurisdiction
  schemes <- config$level_schemes %||% list()
  year <- as.character(prog$year)

  content_areas <- list()
  achievement_levels <- list()
  cutscores <- list()
  scale_bounds <- list()

  for (tid in names(config$tests)) {
    t <- config$tests[[tid]]
    ca_id <- t$content_area

    map_grades <- names((config$map %||% list())[[ca_id]] %||% list())
    ig <- t$intended_grades
    enrolled <- if (length(map_grades)) {
      map_grades
    } else if (identical(ig, "not_grade_bound")) {
      character(0)
    } else {
      as.character(unlist(ig))
    }
    intended <- t$intended_enrollment_grade %||%
      (if (identical(ig, "not_grade_bound") || length(enrolled) > 1L) "variable" else "fixed")

    content_areas[[length(content_areas) + 1L]] <- list(
      id = ca_id,
      label = t$label,
      vertical_scale = isTRUE(t$scale$vertical),
      scale_name = t$scale$name,
      enrollment = list(
        intended_enrollment_grade = intended,
        enrolled_grades_tested = as.list(.grade_order(enrolled))
      )
    )

    sch <- schemes[[t$level_scheme]]
    if (!is.null(sch)) {
      block <- list(labels = sch$labels)
      if (!is.null(sch$proficient_from)) block$proficient_from <- sch$proficient_from
      achievement_levels[[ca_id]] <- block
    }

    cs <- list(); sb <- list()
    for (g in names(t$cuts %||% list())) {
      entry <- t$cuts[[g]]
      if (!is.null(entry$values)) cs[[g]] <- entry$values
      if (!is.null(entry$loss) || !is.null(entry$hoss)) {
        b <- list()
        if (!is.null(entry$loss)) b$loss <- entry$loss
        if (!is.null(entry$hoss)) b$hoss <- entry$hoss
        sb[[g]] <- b
      }
    }
    if (length(cs)) cutscores[[ca_id]] <- cs
    if (length(sb)) scale_bounds[[ca_id]] <- sb
  }

  rec <- list(
    schema_version = "amr.assessment.v2",
    status = "draft",
    jurisdiction = jur,
    assessment_system = list(
      id = prog$id, name = prog$name,
      family = prog$family %||% prog$name, assessment_type = prog$type
    ),
    administration = list(
      id = prog$administration_id %||% paste(prog$id, tolower(jur$id), year, sep = "-"),
      year = year
    ),
    content_areas = content_areas
  )
  if (!is.null(prog$vendor)) rec$administration$vendor <- prog$vendor
  if (length(achievement_levels)) rec$achievement_levels <- achievement_levels
  if (length(cutscores)) rec$cutscores <- cutscores
  if (length(scale_bounds)) rec$scale_bounds <- scale_bounds
  rec
}
