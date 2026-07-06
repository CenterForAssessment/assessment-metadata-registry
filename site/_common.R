# Shared rendering helpers for the registry catalog. The site consumes the derived
# build/ JSON directly (jsonlite) — it does NOT depend on amrr — so the presentation
# layer stays cleanly decoupled from the data pipeline.

suppressPackageStartupMessages({
  library(jsonlite)
  library(htmltools)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

# Escape a free-text value for safe embedding in HTML.
esc <- function(x) if (is.null(x) || !length(x)) "" else htmltools::htmlEscape(as.character(x))

# build/ lives at the repo root; the Quarto project root is site/.
BUILD_DIR <- Sys.getenv("AMRR_BUILD_DIR", file.path("..", "build"))

amr_read_json <- function(...) fromJSON(file.path(BUILD_DIR, ...), simplifyVector = FALSE)

amr_manifest <- function() {
  p <- file.path(BUILD_DIR, "manifest.json")
  if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else list()
}

amr_registry_stamp <- function() (amr_manifest()[["_registry"]]) %||% list()

# ---- record model ----------------------------------------------------------
amr_is_accountability <- function(rec) {
  (rec$schema_version %||% "") %in% c("amr.accountability_system.v1", "amr.accountability.v2")
}
amr_type <- function(rec) if (amr_is_accountability(rec)) "accountability" else "assessment"
amr_system <- function(rec) if (amr_is_accountability(rec)) rec$accountability_system else rec$assessment_system
amr_sys_id <- function(rec) amr_system(rec)$id
amr_year <- function(rec) as.character(rec$administration$year)
amr_slug <- function(rec) paste(rec$jurisdiction$id, amr_sys_id(rec), amr_year(rec), sep = "-")
amr_title <- function(rec) {
  sys <- amr_system(rec)
  sprintf("%s — %s — %s", sys$name %||% sys$id, rec$jurisdiction$name %||% rec$jurisdiction$id, amr_year(rec))
}
amr_page <- function(slug) paste0("record-", slug, ".html")

# Resolve a single record from its slug (<JUR>-<SYS>-<YEAR>; SYS may be hyphenated).
amr_record_by_slug <- function(slug) {
  m <- regmatches(slug, regexec("^([^-]+)-(.+)-([0-9]{4})$", slug))[[1]]
  jur <- m[2]; sys <- m[3]; yr <- m[4]
  bundle <- fromJSON(file.path(BUILD_DIR, "dist", jur, paste0(sys, ".json")), simplifyVector = FALSE)
  for (r in bundle$records) if (identical(amr_year(r), yr) && identical(amr_sys_id(r), sys)) return(r)
  stop("record not found for slug: ", slug)
}

# Load every record from the per-system dist bundles (deterministic order).
amr_all_records <- function() {
  jdirs <- sort(list.dirs(file.path(BUILD_DIR, "dist"), recursive = FALSE))
  recs <- list()
  for (jd in jdirs) {
    for (f in sort(list.files(jd, pattern = "\\.json$", full.names = TRUE))) {
      bundle <- fromJSON(f, simplifyVector = FALSE)
      for (r in bundle$records) recs[[length(recs) + 1L]] <- r
    }
  }
  recs
}

# ---- small HTML builders ---------------------------------------------------
amr_badge <- function(value, kind = "status") {
  if (is.null(value) || !nzchar(value)) return("")
  as.character(tags$span(class = sprintf("amr-badge amr-%s-%s", kind, value), value))
}

amr_dl <- function(pairs) {
  pairs <- pairs[!vapply(pairs, function(v) is.null(v) || !nzchar(as.character(v)), logical(1))]
  if (!length(pairs)) return(NULL)
  items <- unlist(lapply(names(pairs), function(k) {
    list(tags$dt(k), tags$dd(HTML(as.character(pairs[[k]]))))
  }), recursive = FALSE)
  tags$dl(class = "amr-dl", items)
}

amr_section <- function(kicker, ...) {
  tags$section(class = "amr-section amr-reveal",
    if (!is.null(kicker)) tags$div(class = "amr-kicker", kicker), ...)
}

# rows: list of character vectors (cell HTML already formed). num: 1-based numeric cols.
amr_html_table <- function(headers, rows, caption = NULL, num = integer(0)) {
  th <- lapply(headers, function(h) tags$th(HTML(h)))
  trs <- lapply(rows, function(r) {
    tds <- lapply(seq_along(r), function(i) {
      tags$td(class = if (i %in% num) "amr-num" else NULL, HTML(r[[i]] %||% ""))
    })
    tags$tr(tds)
  })
  tags$table(class = "amr-table",
    if (!is.null(caption)) tags$caption(caption),
    tags$thead(tags$tr(th)), tags$tbody(trs))
}

# ---- Display view ----------------------------------------------------------
amr_display_html <- function(rec) {
  sys <- amr_system(rec)
  jur <- rec$jurisdiction
  adm <- rec$administration
  parts <- list()

  # Identity
  parts[[length(parts) + 1L]] <- amr_section("Identity",
    amr_dl(list(
      "Jurisdiction" = sprintf("%s <span class='amr-callno'>(%s · %s)</span>",
                               esc(jur$name %||% jur$id), esc(jur$id), esc(jur$type)),
      "System"       = sprintf("%s <span class='amr-callno'>(%s)</span>", esc(sys$name %||% sys$id), esc(sys$id)),
      "Family"       = esc(sys$family),
      "Type"         = esc(sys$assessment_type %||% amr_type(rec)),
      "Year"         = esc(adm$year),
      "Vendor"       = esc(adm$vendor),
      "Window"       = esc(adm$window),
      "CSEM ref"     = esc(adm$csem_ref)
    )))

  if (amr_is_accountability(rec)) {
    parts <- c(parts, amr_display_accountability(rec))
  } else {
    parts <- c(parts, amr_display_assessment(rec))
  }

  # Provenance stamp
  prov <- rec$provenance %||% list()
  stamp <- paste(c(
    if (!is.null(prov$entered_by)) sprintf("entered by %s", prov$entered_by),
    if (!is.null(prov$entered_at)) sprintf("on %s", prov$entered_at),
    if (!is.null(prov$last_verified_at)) sprintf("· verified %s", prov$last_verified_at),
    if (!is.null(prov$source_citation)) sprintf("· source: %s", prov$source_citation)
  ), collapse = " ")
  parts[[length(parts) + 1L]] <- amr_section("Provenance",
    tags$div(class = "amr-stamp", HTML(if (nzchar(stamp)) htmltools::htmlEscape(stamp) else "—")))

  # Source documents (v2): evidence beyond the primary citation
  docs <- rec$source_documents %||% list()
  if (length(docs)) {
    items <- vapply(docs, function(d) {
      t <- htmltools::htmlEscape(d$title %||% "")
      if (!is.null(d$url)) sprintf("<a href='%s'>%s</a>", htmltools::htmlEscape(d$url), t) else t
    }, character(1))
    parts[[length(parts) + 1L]] <- amr_section("Source documents",
      tags$div(class = "amr-stamp", HTML(paste(items, collapse = "<br/>"))))
  }

  as.character(tagList(parts))
}

amr_display_assessment <- function(rec) {
  out <- list()
  # Program
  prog <- rec$assessment_program %||% list()
  org <- prog$organization %||% list()
  if (length(prog)) {
    org_html <- esc(org$name)
    if (!is.null(org$url)) org_html <- sprintf("<a href='%s'>%s</a>", esc(org$url), esc(org$name %||% org$url))
    out[[length(out) + 1L]] <- amr_section("Program",
      amr_dl(list("Assessment" = esc(prog$assessment_name), "Abbreviation" = esc(prog$abbreviation),
                  "Organization" = org_html)))
  }

  # Cutscore caveat
  if (!is.null(rec$cutscores_provenance)) {
    out[[length(out) + 1L]] <- amr_section("Cutscore provenance",
      tags$div(class = "amr-caveat", rec$cutscores_provenance))
  }

  # Content areas (v2 adds the enrollment-grade model, ADR-009)
  cas <- rec$content_areas %||% list()
  if (length(cas)) {
    has_enr <- any(vapply(cas, function(ca) !is.null(ca$enrollment), logical(1)))
    rows <- lapply(cas, function(ca) {
      base <- c(
        sprintf("<code>%s</code>", esc(ca$id)), esc(ca$label),
        if (isTRUE(ca$vertical_scale)) "yes" else "no", esc(ca$scale_name))
      if (has_enr) {
        enr <- ca$enrollment %||% list()
        base <- c(base, esc(enr$intended_enrollment_grade %||% "—"),
                  esc(paste(unlist(enr$enrolled_grades_tested), collapse = ", ")))
      }
      base
    })
    heads <- c("ID", "Label", "Vertical scale", "Scale name")
    if (has_enr) heads <- c(heads, "Enrollment", "Enrolled grades tested")
    out[[length(out) + 1L]] <- amr_section("Content areas", amr_html_table(heads, rows))
    enr_notes <- Filter(nzchar, vapply(cas, function(ca)
      as.character((ca$enrollment %||% list())$note %||% ""), character(1)))
    if (length(enr_notes)) {
      out[[length(out) + 1L]] <- tags$div(class = "amr-callno",
        HTML(paste(vapply(enr_notes, htmltools::htmlEscape, character(1)), collapse = "<br/>")))
    }
  }

  # Scale bounds (v2): loss/hoss per enrolled grade, mirrors cutscore keying
  sb <- rec$scale_bounds %||% list()
  for (ca in names(sb)) {
    grades <- names(sb[[ca]])
    grades <- grades[order(suppressWarnings(as.numeric(grades)), na.last = FALSE)]
    rows <- lapply(grades, function(g) {
      b <- sb[[ca]][[g]]
      c(sprintf("Grade %s", esc(g)), format(b$loss), format(b$hoss), esc(b$source %||% "—"))
    })
    out[[length(out) + 1L]] <- amr_section(sprintf("Scale bounds · %s", ca),
      amr_html_table(c("Grade", "LOSS", "HOSS", "Source"), rows, num = c(2, 3)))
  }

  # Measurement extension blocks (v2): vendor/psychometric facts only
  elp <- (rec$measurement %||% list())$elp
  if (!is.null(elp)) {
    comps <- elp$composites %||% list()
    comp_html <- paste(vapply(names(comps), function(id) {
      w <- comps[[id]]$weights %||% list()
      ws <- paste(sprintf("%s %s", names(w), vapply(w, format, character(1))), collapse = ", ")
      sprintf("<code>%s</code> (%s)", htmltools::htmlEscape(id), htmltools::htmlEscape(ws))
    }, character(1)), collapse = "<br/>")
    out[[length(out) + 1L]] <- amr_section("ELP measurement",
      amr_dl(list("Instrument" = esc(elp$instrument),
                  "Domains" = esc(paste(unlist(elp$domains), collapse = ", ")),
                  "Composites" = comp_html,
                  "Grade clusters (forms)" = esc(paste(unlist(elp$grade_clusters), collapse = ", ")),
                  "Band scheme" = esc(elp$band_scheme))))
  }
  alt <- (rec$measurement %||% list())$alternate
  if (!is.null(alt)) {
    out[[length(out) + 1L]] <- amr_section("Alternate measurement",
      amr_dl(list("Instrument" = esc(alt$instrument),
                  "Achievement standard" = esc(alt$achievement_standard),
                  "Scoring model" = esc(alt$scoring_model),
                  "Linkage levels" = esc(paste(unlist(alt$linkage_levels), collapse = ", ")),
                  "Equating notes" = esc(alt$equating_notes))))
  }

  # Achievement levels
  lv <- rec$achievement_levels %||% list()
  for (ca in names(lv)) {
    labels <- lv[[ca]]$labels %||% list()
    prof <- lv[[ca]]$proficient %||% vector("list", length(labels))
    rows <- lapply(seq_along(labels), function(i) {
      p <- if (i <= length(prof)) prof[[i]] else NULL
      pf <- if (isTRUE(p) || identical(p, "true")) "<span class='amr-proficient'>proficient</span>" else "—"
      c(as.character(i - 1L), esc(labels[[i]]), pf)
    })
    out[[length(out) + 1L]] <- amr_section(sprintf("Achievement levels · %s", ca),
      amr_html_table(c("Index", "Label", "Proficient"), rows, num = 1))
  }

  # Cutscores — grade × level-boundary matrix
  cs <- rec$cutscores %||% list()
  for (ca in names(cs)) {
    grades <- names(cs[[ca]])
    grades <- grades[order(suppressWarnings(as.numeric(grades)))]
    labels <- (lv[[ca]]$labels %||% list())
    max_cuts <- max(vapply(cs[[ca]], length, integer(1)), 0L)
    heads <- c("Grade", vapply(seq_len(max_cuts), function(j) {
      lbl <- if ((j + 1L) <= length(labels)) labels[[j + 1L]] else NULL
      if (!is.null(lbl)) sprintf("&ge; %s", esc(lbl)) else sprintf("Cut %d", j)
    }, character(1)))
    rows <- lapply(grades, function(g) {
      cuts <- cs[[ca]][[g]]
      c(sprintf("Grade %s", g),
        vapply(seq_len(max_cuts), function(j) if (j <= length(cuts)) format(cuts[[j]]) else "", character(1)))
    })
    out[[length(out) + 1L]] <- amr_section(sprintf("Cutscores · %s", ca),
      amr_html_table(heads, rows, num = seq(2, max_cuts + 1L)))
  }

  # Comparability
  comp <- rec$comparability
  if (!is.null(comp)) {
    yn <- function(x) if (is.null(x)) "—" else if (isTRUE(x)) "yes" else "no"
    out[[length(out) + 1L]] <- amr_section("Comparability",
      amr_dl(list("Administered" = yn(comp$administered), "Scale transition" = yn(comp$scale_transition),
                  "Comparable to prior year" = yn(comp$comparable_to_prior_year),
                  "Prior scale name" = esc(comp$prior_scale_name), "Notes" = esc(comp$notes))))
  }
  out
}

amr_display_accountability <- function(rec) {
  out <- list()
  acct <- rec$accountability_system
  if (!is.null(acct$framework)) {
    out[[length(out) + 1L]] <- amr_section("Framework", amr_dl(list("Framework" = acct$framework)))
  }
  tgts <- rec$targets %||% list()
  jid <- rec$jurisdiction$id
  yr <- amr_year(rec)
  rows <- lapply(tgts, function(t) {
    xslug <- paste(jid, t$assessment_system_id, yr, sep = "-")
    xlink <- sprintf("<a class='amr-xlink' href='%s'>%s</a>", amr_page(xslug), esc(t$assessment_system_id))
    c(xlink, sprintf("<code>%s</code>", esc(t$content_area)), esc(t$semantics),
      esc(t$basis), esc(t$comparison), esc(t$label))
  })
  out[[length(out) + 1L]] <- amr_section("Targets",
    amr_html_table(c("Assessment", "Content area", "Semantics", "Basis", "Comparison", "Label"), rows))

  # Per-grade scale-score thresholds (only for scale_score targets)
  for (t in tgts) {
    pgss <- t$per_grade_scale_score %||% list()
    if (length(pgss)) {
      grades <- names(pgss)[order(suppressWarnings(as.numeric(names(pgss))))]
      rows <- lapply(grades, function(g) c(sprintf("Grade %s", g), format(pgss[[g]])))
      out[[length(out) + 1L]] <- amr_section(
        sprintf("Per-grade scale-score threshold · %s / %s", t$assessment_system_id, t$content_area),
        amr_html_table(c("Grade", "Scale score"), rows, num = 2))
    }
  }
  out
}

# ---- Explore + Raw views ---------------------------------------------------
amr_json <- function(rec, pretty = FALSE) {
  toJSON(rec, pretty = pretty, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
}

amr_explore_html <- function(rec) {
  id <- paste0("jv-", amr_slug(rec))
  sprintf(paste0(
    "<andypf-json-viewer data-src=\"%s\" expanded=\"2\" show-toolbar=\"true\" ",
    "show-copy=\"true\" show-size=\"true\" show-data-types=\"true\" indent=\"2\"></andypf-json-viewer>\n",
    "<script type=\"application/json\" id=\"%s\">%s</script>"),
    id, id, amr_json(rec, pretty = FALSE))
}

# Record identity header: monospace "call number" + type + status/confidence badges.
amr_record_header <- function(rec) {
  hdr <- tags$div(class = "amr-record-head",
    tags$span(class = "amr-callno", sprintf("%s · %s · %s",
              rec$jurisdiction$id, amr_sys_id(rec), amr_year(rec))),
    tags$span(class = "amr-type", amr_type(rec)),
    tags$span(class = "amr-badges",
      HTML(amr_badge(rec$status %||% "", "status")),
      HTML(amr_badge(rec$source_confidence %||% "", "conf"))))
  as.character(hdr)
}

# Wrap a block of literal HTML so Pandoc passes it through verbatim (an `output:
# asis` chunk is otherwise re-parsed as markdown, which mangles values like ">=").
amr_raw_html <- function(html) paste0("\n```{=html}\n", html, "\n```\n\n")

# Emit the full Display / Explore / Raw tabset for a record (call from an
# `#| output: asis` chunk).
amr_render_record <- function(rec) {
  cat(amr_raw_html(amr_record_header(rec)))
  cat("::: {.panel-tabset}\n\n")
  cat("## Display\n", amr_raw_html(amr_display_html(rec)))
  cat("## Explore\n", amr_raw_html(amr_explore_html(rec)))
  cat("## Raw JSON\n\n```json\n", amr_json(rec, pretty = TRUE), "\n```\n\n", sep = "")
  cat(":::\n")
}
