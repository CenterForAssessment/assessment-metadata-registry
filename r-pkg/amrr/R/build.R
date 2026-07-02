# Derive the registry query layer (Tier B) from the authored sidecars (Tier A).
# Ported from the former Python tools/build.py (ADR-004). Emits index / targets /
# changelog / tables / dist bundles / registry.sqlite / manifest under `out`.

.br_order_rows <- function(rows, keys) {
  if (!length(rows)) return(rows)
  cols <- lapply(keys, function(k) vapply(rows, function(r) as.character(r[[k]] %||% NA), NA_character_))
  rows[do.call(order, c(cols, list(method = "radix")))]
}

.br_index <- function(records) {
  rows <- list()
  for (rec in records) {
    if (!is_assessment_record(rec)) next
    jur <- rec$jurisdiction; sys_ <- rec$assessment_system; adm <- rec$administration
    levels <- rec$achievement_levels %||% list()
    comp <- rec$comparability %||% list()
    cutscores <- rec$cutscores %||% list()
    for (ca in rec$content_areas %||% list()) {
      ca_id <- ca$id
      rows[[length(rows) + 1L]] <- list(
        jurisdiction_id = jur$id, jurisdiction_name = jur$name,
        assessment_system_id = sys_$id, assessment_system_name = sys_$name,
        assessment_type = sys_$assessment_type, year = adm$year,
        content_area = ca_id, vertical_scale = isTRUE(ca$vertical_scale %||% FALSE),
        scale_name = ca$scale_name, vendor = adm$vendor,
        n_levels = length((levels[[ca_id]] %||% list())$labels %||% list()),
        has_cutscores = ca_id %in% names(cutscores),
        scale_transition = comp$scale_transition,
        comparable_to_prior_year = comp$comparable_to_prior_year,
        status = rec$status, source_confidence = rec$source_confidence,
        source_path = rec[["_source_path"]]
      )
    }
  }
  .br_order_rows(rows, c("jurisdiction_id", "assessment_system_id", "year", "content_area"))
}

.br_targets <- function(records) {
  rows <- list()
  for (rec in records) {
    if (!is_accountability_record(rec)) next
    jur <- rec$jurisdiction; acct <- rec$accountability_system; adm <- rec$administration
    for (t in rec$targets %||% list()) {
      rows[[length(rows) + 1L]] <- list(
        jurisdiction_id = jur$id, accountability_system_id = acct$id,
        assessment_system_id = t$assessment_system_id, content_area = t$content_area,
        year = adm$year, semantics = t$semantics, basis = t$basis,
        comparison = t$comparison, label = t$label,
        has_per_grade_scale_score = length(t$per_grade_scale_score %||% list()) > 0
      )
    }
  }
  .br_order_rows(rows, c("jurisdiction_id", "accountability_system_id",
                         "assessment_system_id", "content_area", "year"))
}

.br_vendor_by_year <- function(records) {
  rows <- list()
  for (r in records) if (is_assessment_record(r)) {
    rows[[length(rows) + 1L]] <- list(
      jurisdiction_id = r$jurisdiction$id, assessment_system_id = r$assessment_system$id,
      year = r$administration$year, vendor = r$administration$vendor)
  }
  .br_order_rows(rows, c("jurisdiction_id", "assessment_system_id", "year"))
}

.br_vertical_scale <- function(records) {
  rows <- list()
  for (r in records) if (is_assessment_record(r)) {
    for (ca in r$content_areas %||% list()) {
      rows[[length(rows) + 1L]] <- list(
        jurisdiction_id = r$jurisdiction$id, assessment_system_id = r$assessment_system$id,
        content_area = ca$id, year = r$administration$year,
        vertical_scale = isTRUE(ca$vertical_scale %||% FALSE), scale_name = ca$scale_name)
    }
  }
  .br_order_rows(rows, c("jurisdiction_id", "assessment_system_id", "content_area", "year"))
}

.br_changelog <- function(records) {
  events <- list()
  add <- function(e) events[[length(events) + 1L]] <<- e
  year_of <- function(r) as.character(r$administration$year)

  a_series <- list()
  for (r in records) if (is_assessment_record(r)) {
    k <- paste(r$jurisdiction$id, r$assessment_system$id, sep = .amrr_sep)
    a_series[[k]] <- c(a_series[[k]], list(r))
  }
  for (k in sort(names(a_series))) {
    recs <- a_series[[k]]
    recs <- recs[order(vapply(recs, year_of, NA_character_), method = "radix")]
    jid <- recs[[1]]$jurisdiction$id; sid <- recs[[1]]$assessment_system$id
    for (i in seq_len(length(recs) - 1L)) {
      prev <- recs[[i]]; cur <- recs[[i + 1L]]
      base <- list(record_type = "assessment", jurisdiction_id = jid, assessment_system_id = sid,
                   year_from = prev$administration$year, year_to = cur$administration$year)
      if (!identical(prev$administration$vendor, cur$administration$vendor)) {
        add(c(base, list(field = "vendor", from = prev$administration$vendor,
                         to = cur$administration$vendor)))
      }
      pv <- list(); for (cc in prev$content_areas %||% list()) pv[[cc$id]] <- isTRUE(cc$vertical_scale %||% FALSE)
      cv <- list(); for (cc in cur$content_areas %||% list())  cv[[cc$id]] <- isTRUE(cc$vertical_scale %||% FALSE)
      for (ca in sort(unique(c(names(pv), names(cv))))) {
        if (!identical(pv[[ca]], cv[[ca]])) {
          add(c(base, list(content_area = ca, field = "vertical_scale", from = pv[[ca]], to = cv[[ca]])))
        }
      }
      pl <- prev$achievement_levels %||% list(); cl <- cur$achievement_levels %||% list()
      for (ca in sort(unique(c(names(pl), names(cl))))) {
        if (!identical((pl[[ca]] %||% list())$labels, (cl[[ca]] %||% list())$labels)) {
          add(c(base, list(content_area = ca, field = "achievement_levels",
                           from = (pl[[ca]] %||% list())$labels, to = (cl[[ca]] %||% list())$labels)))
        }
      }
      pc <- prev$cutscores %||% list(); cc2 <- cur$cutscores %||% list()
      for (ca in sort(unique(c(names(pc), names(cc2))))) {
        if (!identical(pc[[ca]], cc2[[ca]])) {
          add(c(base, list(content_area = ca, field = "cutscores", from = pc[[ca]], to = cc2[[ca]])))
        }
      }
    }
  }

  target_map <- function(rec) {
    m <- list()
    for (t in rec$targets %||% list()) m[[paste(t$assessment_system_id, t$content_area, sep = .amrr_sep)]] <- t
    m
  }
  b_series <- list()
  for (r in records) if (is_accountability_record(r)) {
    k <- paste(r$jurisdiction$id, r$accountability_system$id, sep = .amrr_sep)
    b_series[[k]] <- c(b_series[[k]], list(r))
  }
  fields <- c("semantics", "basis", "comparison", "per_grade_scale_score", "level_value")
  for (k in sort(names(b_series))) {
    recs <- b_series[[k]]
    recs <- recs[order(vapply(recs, year_of, NA_character_), method = "radix")]
    jid <- recs[[1]]$jurisdiction$id; aid <- recs[[1]]$accountability_system$id
    for (i in seq_len(length(recs) - 1L)) {
      prev <- recs[[i]]; cur <- recs[[i + 1L]]
      pm <- target_map(prev); cm <- target_map(cur)
      for (kk in sort(unique(c(names(pm), names(cm))))) {
        p <- pm[[kk]] %||% list(); c_ <- cm[[kk]] %||% list()
        if (!identical(p[fields], c_[fields])) {
          parts <- strsplit(kk, .amrr_sep, fixed = TRUE)[[1]]
          from_v <- p[fields][!vapply(p[fields], is.null, logical(1))]
          to_v <- c_[fields][!vapply(c_[fields], is.null, logical(1))]
          add(list(record_type = "accountability", jurisdiction_id = jid,
                   accountability_system_id = aid, assessment_system_id = parts[1],
                   content_area = parts[2], field = "target",
                   year_from = prev$administration$year, year_to = cur$administration$year,
                   from = if (length(from_v)) from_v else NULL,
                   to = if (length(to_v)) to_v else NULL))
        }
      }
    }
  }
  events
}

.br_sqlite <- function(records, db_path, ddl_path, prov) {
  p <- function(x) if (is.null(x) || length(x) == 0) NA else x[[1]]
  tri <- function(v) if (is.null(v)) NA_integer_ else if (isTRUE(v)) 1L else 0L
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(db_path)) unlink(db_path)
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  lines <- readLines(ddl_path, warn = FALSE)
  lines <- lines[!grepl("^\\s*--", lines)]
  for (stmt in strsplit(paste(lines, collapse = "\n"), ";", fixed = TRUE)[[1]]) {
    s <- trimws(stmt); if (nzchar(s)) DBI::dbExecute(con, s)
  }
  for (kv in list(list("git_sha", prov$sha %||% NA), list("built_at", prov$built_at),
                  list("schema_version", "amr.registry.v1"))) {
    DBI::dbExecute(con, "INSERT INTO registry_meta(key, value) VALUES (?, ?)", params = kv)
  }

  seen_jur <- seen_sys <- seen_acct <- character(0)
  for (r in records) {
    jur <- r$jurisdiction
    if (!(jur$id %in% seen_jur)) {
      DBI::dbExecute(con, "INSERT OR REPLACE INTO jurisdiction VALUES (?,?,?,?,?)",
                     params = list(jur$id, jur$name, jur$type, p(jur$nces_id), p(jur$fips)))
      seen_jur <- c(seen_jur, jur$id)
    }
    if (is_assessment_record(r)) {
      sys_ <- r$assessment_system; adm <- r$administration
      if (!(sys_$id %in% seen_sys)) {
        DBI::dbExecute(con, "INSERT OR REPLACE INTO assessment_system VALUES (?,?,?,?)",
                       params = list(sys_$id, sys_$name, sys_$family, sys_$assessment_type))
        seen_sys <- c(seen_sys, sys_$id)
      }
      prv <- r$provenance %||% list()
      DBI::dbExecute(con, "INSERT OR REPLACE INTO administration VALUES (?,?,?,?,?,?,?,?,?,?)",
                     params = list(jur$id, sys_$id, as.character(adm$year), p(adm$id), p(adm$vendor),
                                   p(adm$window), p(adm$csem_ref), p(r$status),
                                   p(r$source_confidence), p(prv$source_citation)))
      prog <- r$assessment_program %||% list(); org <- prog$organization %||% list()
      DBI::dbExecute(con, "INSERT OR REPLACE INTO assessment_program VALUES (?,?,?,?,?,?,?,?)",
                     params = list(jur$id, sys_$id, as.character(adm$year), p(prog$assessment_name),
                                   p(prog$abbreviation), p(org$name), p(org$abbreviation), p(org$url)))
      comp <- r$comparability
      if (!is.null(comp)) {
        DBI::dbExecute(con, "INSERT OR REPLACE INTO comparability VALUES (?,?,?,?,?,?,?,?)",
                       params = list(jur$id, sys_$id, as.character(adm$year), tri(comp$administered),
                                     tri(comp$scale_transition), tri(comp$comparable_to_prior_year),
                                     p(comp$prior_scale_name), p(comp$notes)))
      }
      for (ca in r$content_areas %||% list()) {
        DBI::dbExecute(con, "INSERT OR REPLACE INTO vertical_scale VALUES (?,?,?,?,?,?,?)",
                       params = list(jur$id, sys_$id, ca$id, as.character(adm$year),
                                     if (isTRUE(ca$vertical_scale %||% FALSE)) 1L else 0L,
                                     p(ca$scale_name), p(ca$label)))
      }
      for (ca in names(r$achievement_levels %||% list())) {
        block <- r$achievement_levels[[ca]]
        labels <- block$labels %||% list(); prof <- block$proficient %||% vector("list", length(labels))
        for (i in seq_along(labels)) {
          pf <- if (i <= length(prof)) prof[[i]] else NULL
          DBI::dbExecute(con, "INSERT OR REPLACE INTO achievement_level VALUES (?,?,?,?,?,?,?)",
                         params = list(jur$id, sys_$id, ca, as.character(adm$year), i - 1L, labels[[i]],
                                       if (is.null(pf)) NA_integer_ else if (as_logical_flag(pf)) 1L else 0L))
        }
      }
      for (ca in names(r$cutscores %||% list())) {
        for (grade in names(r$cutscores[[ca]] %||% list())) {
          cuts <- r$cutscores[[ca]][[grade]]
          for (i in seq_along(cuts)) {
            DBI::dbExecute(con, "INSERT OR REPLACE INTO cutscore VALUES (?,?,?,?,?,?,?)",
                           params = list(jur$id, sys_$id, ca, as.character(adm$year),
                                         as.character(grade), i, as.numeric(cuts[[i]])))
          }
        }
      }
    } else if (is_accountability_record(r)) {
      acct <- r$accountability_system; adm <- r$administration
      if (!(acct$id %in% seen_acct)) {
        DBI::dbExecute(con, "INSERT OR REPLACE INTO accountability_system VALUES (?,?,?)",
                       params = list(acct$id, acct$name, p(acct$framework)))
        seen_acct <- c(seen_acct, acct$id)
      }
      for (t in r$targets %||% list()) {
        DBI::dbExecute(con,
          "INSERT OR REPLACE INTO accountability_target VALUES (?,?,?,?,?,?,?,?,?,?,?)",
          params = list(jur$id, acct$id, t$assessment_system_id, t$content_area,
                        as.character(adm$year), p(t$label), p(t$semantics), p(t$basis),
                        p(t$comparison), p(r$status), p(r$source_confidence)))
        for (grade in names(t$per_grade_scale_score %||% list())) {
          DBI::dbExecute(con,
            "INSERT OR REPLACE INTO accountability_target_scale_score VALUES (?,?,?,?,?,?,?)",
            params = list(jur$id, acct$id, t$assessment_system_id, t$content_area,
                          as.character(adm$year), as.character(grade),
                          as.numeric(t$per_grade_scale_score[[grade]])))
        }
      }
    }
  }
  invisible(NULL)
}

.br_clean <- function(rec) { rec[["_source_path"]] <- NULL; rec }

.br_write_json <- function(path, payload) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  txt <- jsonlite::toJSON(payload, pretty = TRUE, auto_unbox = TRUE,
                          null = "null", na = "null", digits = NA)
  writeLines(txt, path, useBytes = TRUE)
}

#' Build the derived registry layer (Tier B)
#'
#' Reads every authored sidecar under `<registry>/metadata/` and regenerates the
#' disposable query layer under `out`: `index.json`, `targets.json`,
#' `changelog.json`, `tables/*.json`, per-jurisdiction/system `dist/**` bundles,
#' `registry.sqlite` (from the DDL), and a SHA-stamped `manifest.json`. Every
#' bundle carries a `_registry` provenance block. Derived, never canonical.
#'
#' @param registry Path to a registry checkout (containing `metadata/`, `schemas/`).
#'   Defaults to `option("amrr.registry")` then `AMRR_REGISTRY`.
#' @param out Output directory (wiped and rewritten). Default `"build"`.
#' @param ddl Path to the SQLite DDL. Default `<registry>/schemas/sql/amr-registry.v1.sql`.
#' @param quiet Suppress the one-line build summary.
#' @return Invisibly, the manifest list (record counts + provenance stamp).
#' @examples
#' \dontrun{
#' amrr::build_registry(".", out = "build")
#' }
#' @export
build_registry <- function(registry = NULL, out = "build", ddl = NULL, quiet = FALSE) {
  need_pkgs(c("DBI", "RSQLite", "digest"))
  root <- amrr_registry_root(registry)
  ddl <- ddl %||% file.path(root, "schemas", "sql", "amr-registry.v1.sql")

  records <- read_all_records(root)
  if (!length(records)) stop("No sidecars under ", file.path(root, "metadata"), call. = FALSE)

  prov <- amrr_git_provenance(root)
  prov$built_at <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%OS3+00:00")
  stamp <- list(schema_version = "amr.registry.v1", git_sha = prov$sha,
                dirty = prov$dirty, built_at = prov$built_at)

  if (dir.exists(out)) unlink(out, recursive = TRUE)

  .br_write_json(file.path(out, "index.json"), list(`_registry` = stamp, records = .br_index(records)))
  .br_write_json(file.path(out, "targets.json"), list(`_registry` = stamp, rows = .br_targets(records)))
  .br_write_json(file.path(out, "changelog.json"), list(`_registry` = stamp, events = .br_changelog(records)))
  .br_write_json(file.path(out, "tables", "vendor_by_year.json"),
                 list(`_registry` = stamp, rows = .br_vendor_by_year(records)))
  .br_write_json(file.path(out, "tables", "vertical_scale.json"),
                 list(`_registry` = stamp, rows = .br_vertical_scale(records)))

  by_jur <- list(); by_sys <- list()
  for (r in records) {
    jid <- r$jurisdiction$id
    by_jur[[jid]] <- c(by_jur[[jid]], list(.br_clean(r)))
    sk <- paste(jid, record_system_id(r), sep = .amrr_sep)
    by_sys[[sk]] <- c(by_sys[[sk]], list(.br_clean(r)))
  }
  for (jid in names(by_jur)) {
    .br_write_json(file.path(out, "dist", paste0(jid, ".json")),
                   list(`_registry` = stamp, jurisdiction_id = jid, records = by_jur[[jid]]))
  }
  for (sk in names(by_sys)) {
    parts <- strsplit(sk, .amrr_sep, fixed = TRUE)[[1]]
    .br_write_json(file.path(out, "dist", parts[1], paste0(parts[2], ".json")),
                   list(`_registry` = stamp, jurisdiction_id = parts[1],
                        system_id = parts[2], records = by_sys[[sk]]))
  }

  .br_sqlite(records, file.path(out, "registry.sqlite"), ddl, prov)

  n_assess <- sum(vapply(records, is_assessment_record, logical(1)))
  n_acct <- sum(vapply(records, is_accountability_record, logical(1)))
  all_files <- sort(list.files(out, recursive = TRUE, full.names = TRUE), method = "radix")
  files <- list()
  for (f in all_files) {
    if (basename(f) == "manifest.json") next
    rel <- sub(paste0(out, "/"), "", f, fixed = TRUE)
    files[[rel]] <- digest::digest(file = f, algo = "sha256")
  }
  manifest <- list(`_registry` = stamp, n_records = length(records),
                   n_assessment_records = n_assess, n_accountability_records = n_acct,
                   n_jurisdictions = length(by_jur), files = files)
  .br_write_json(file.path(out, "manifest.json"), manifest)

  if (!quiet) {
    dirty <- if (isTRUE(prov$dirty)) " (DIRTY working tree -- not publishable)" else ""
    cat(sprintf("Built %d record(s) [%d assessment, %d accountability] across %d jurisdiction(s) @ %s%s\n",
                length(records), n_assess, n_acct, length(by_jur), prov$sha %||% "no-git", dirty))
  }
  invisible(manifest)
}
