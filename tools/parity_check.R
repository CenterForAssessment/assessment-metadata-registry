#!/usr/bin/env Rscript
# Parity harness: prove the R build (tools/build.R) is SEMANTICALLY identical to a
# reference build on the same corpus. Byte parity is NOT expected (jsonlite formats
# JSON differently from Python json.dumps); build/ is derived + republished each merge,
# consumers pin the git SHA, and amrr reads raw sidecars — so semantic parity is the bar.
#
# Usage: Rscript tools/parity_check.R <dir_a> <dir_b>
#   Compares every JSON artifact (ignoring the volatile _registry stamp and manifest
#   file-hashes) and every SQLite table (ignoring registry_meta built_at), order-
#   insensitively for objects and for SQLite rows. Exit non-zero on any divergence.

suppressWarnings(suppressMessages({ library(DBI); library(RSQLite) }))

args <- commandArgs(trailingOnly = TRUE)
dir_a <- if (length(args) >= 1) args[[1]] else "build_py"
dir_b <- if (length(args) >= 2) args[[2]] else "build_r"

read_json <- function(p) jsonlite::fromJSON(p, simplifyVector = FALSE)

# Recursively sort object (named-list) keys; leave arrays (unnamed lists) in order.
canon <- function(x) {
  if (is.list(x)) {
    if (!is.null(names(x)) && all(nzchar(names(x)))) x <- x[order(names(x))]
    return(lapply(x, canon))
  }
  x
}

fail <- 0L
report <- function(name, ok, detail = "") {
  cat(sprintf("%-34s %s%s\n", name, if (ok) "OK" else "MISMATCH",
              if (!ok && nzchar(detail)) paste0("  -- ", detail) else ""))
  if (!ok) fail <<- fail + 1L
}

# ---- JSON artifacts ----------------------------------------------------------------
json_files <- sort(sub(paste0("^", dir_a, "/"), "",
                       list.files(dir_a, pattern = "\\.json$", recursive = TRUE, full.names = TRUE)))
for (rel in json_files) {
  a <- read_json(file.path(dir_a, rel)); b <- read_json(file.path(dir_b, rel))
  a[["_registry"]] <- NULL; b[["_registry"]] <- NULL
  if (basename(rel) == "manifest.json") {          # hashes differ by design; compare keys only
    a$files <- sort(names(a$files)); b$files <- sort(names(b$files))
  }
  report(rel, identical(canon(a), canon(b)))
}

# ---- SQLite ------------------------------------------------------------------------
ca <- dbConnect(RSQLite::SQLite(), file.path(dir_a, "registry.sqlite"))
cb <- dbConnect(RSQLite::SQLite(), file.path(dir_b, "registry.sqlite"))
tbls <- sort(dbListTables(ca))
for (t in tbls) {
  da <- dbReadTable(ca, t); db <- dbReadTable(cb, t)
  if (t == "registry_meta") {
    da <- da[da$key != "built_at", , drop = FALSE]
    db <- db[db$key != "built_at", , drop = FALSE]
  }
  ord <- function(d) if (nrow(d)) d[do.call(order, lapply(d, as.character)), , drop = FALSE] else d
  da <- ord(da); db <- ord(db); rownames(da) <- NULL; rownames(db) <- NULL
  eq <- isTRUE(all.equal(da, db, check.attributes = FALSE))
  report(paste0("sqlite:", t), eq,
         if (!eq) sprintf("rows py=%d r=%d", nrow(da), nrow(db)) else "")
}
dbDisconnect(ca); dbDisconnect(cb)

cat(sprintf("\n%d artifact(s) diverged.\n", fail))
quit(status = if (fail) 1L else 0L, save = "no")
