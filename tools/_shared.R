# tools/_shared.R — shared helpers for the R derivation/validation tooling.
#
# Sourced by validate.R and build.R. These mirror the semantics of the former Python
# tools/ (validate.py + build.py). Tier A JSON sidecars are canonical; everything the
# build emits is DERIVED and disposable. Deterministic; no network.

suppressWarnings(suppressMessages(library(jsonlite)))

ASSESSMENT_SCHEMAS <- c("amr.assessment_system.v1", "sgpc.assessment_metadata.v0.1")
ACCT_SCHEMA <- "amr.accountability_system.v1"

# Separator for composite grouping keys. IDs and content-area codes are [A-Za-z0-9_-]
# only, so "|" is safe and unambiguous to split back on.
SEP <- "|"

`%||%` <- function(x, y) if (is.null(x)) y else x

is_assessment <- function(rec) isTRUE(rec$schema_version %in% ASSESSMENT_SCHEMAS)
is_accountability <- function(rec) identical(rec$schema_version, ACCT_SCHEMA)

system_id <- function(rec) {
  if (is_assessment(rec)) rec$assessment_system$id else rec$accountability_system$id
}

# Proficiency-flag coercion — mirrors build.py as_bool().
as_bool <- function(value) {
  if (is.logical(value)) return(isTRUE(value))
  tolower(trimws(as.character(value))) %in% c("true", "1", "yes")
}

# Build provenance: {sha, dirty}, matching build.py git_sha(). NULLs when not a checkout.
git_provenance <- function(repo) {
  sha <- tryCatch(
    suppressWarnings(system2("git", c("-C", repo, "rev-parse", "HEAD"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character(0))
  if (length(sha) == 0 || is.na(sha[1]) || !nzchar(sha[1])) {
    return(list(sha = NULL, dirty = NULL))
  }
  status <- tryCatch(
    suppressWarnings(system2("git", c("-C", repo, "status", "--porcelain"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character(0))
  list(sha = sha[1], dirty = length(status) > 0 && any(nzchar(status)))
}

# Load every sidecar under metadata_root, in byte-sorted path order (matches Python
# sorted(rglob)), each tagged with _source_path relative to metadata_root's parent.
load_records <- function(metadata_root) {
  files <- list.files(metadata_root, pattern = "\\.json$",
                      recursive = TRUE, full.names = TRUE)
  files <- sort(files, method = "radix")  # C/byte order, like Python sorted()
  parent <- dirname(metadata_root)
  lapply(files, function(f) {
    rec <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    sp <- if (parent == ".") f else sub(paste0("^", parent, "/"), "", f)
    rec[["_source_path"]] <- sub("^\\./", "", sp)
    rec
  })
}

# Tiny "--key value" parser so the scripts need no argparse dependency.
parse_args <- function(args, defaults) {
  out <- defaults
  i <- 1L
  while (i <= length(args)) {
    key <- sub("^--", "", args[[i]])
    if (i + 1L <= length(args)) {
      out[[key]] <- args[[i + 1L]]
      i <- i + 2L
    } else {
      i <- i + 1L
    }
  }
  out
}
