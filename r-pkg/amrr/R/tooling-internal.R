# Internal helpers shared by validate_registry() and build_registry() (ADR-004).
# The build/validation tooling lives in amrr; its heavier dependencies
# (jsonvalidate, DBI, RSQLite, digest) are Suggests, checked at call time so
# consumers of get_metadata() never need them.

# Composite grouping-key separator. IDs and content-area codes are [A-Za-z0-9_-]
# only, so "|" is safe and unambiguous to split back on.
.amrr_sep <- "|"

# Error unless every package in `pkgs` is installed.
need_pkgs <- function(pkgs) {
  miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(miss)) {
    stop(sprintf(
      paste0("The registry tooling needs package(s) that are not installed: %s.\n",
             "These are Suggests (build/validate only); install them and retry."),
      paste(miss, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

# git provenance {sha, dirty} for the build manifest (NULLs when not a checkout).
amrr_git_provenance <- function(root) {
  sha <- amrr_git_sha_of(root)
  if (is.na(sha)) return(list(sha = NULL, dirty = NULL))
  status <- tryCatch(
    suppressWarnings(system2("git", c("-C", shQuote(root), "status", "--porcelain"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character(0)
  )
  list(sha = sha, dirty = length(status) > 0L && any(nzchar(status)))
}

# Load every sidecar under root/metadata in byte-sorted path order, each tagged
# with `_source_path` relative to root (e.g. "metadata/IN/ilearn/...json").
read_all_records <- function(root) {
  mdir <- file.path(root, "metadata")
  files <- list.files(mdir, pattern = "\\.json$", recursive = TRUE, full.names = TRUE)
  files <- sort(files, method = "radix")
  lapply(files, function(f) {
    rec <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    rec[["_source_path"]] <- sub(paste0(root, "/"), "", f, fixed = TRUE)
    rec
  })
}

record_system_id <- function(rec) {
  if (is_assessment_record(rec)) rec$assessment_system$id else rec$accountability_system$id
}
