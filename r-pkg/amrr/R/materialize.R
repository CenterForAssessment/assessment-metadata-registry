# Optional binary materialization of a pinned API response (ADR-008 priority 3,
# ADR-009 Phase F). The artifact is a CACHE of registry bytes at a SHA -- never
# an alternate source of truth. Serves SGPstateData-style offline embedding.

#' Materialize a resolved metadata object to a binary artifact
#'
#' Persists the object returned by [get_metadata()] to `.rds` or `.rda` for
#' embedding in another R package (the SGPstateData-style offline pattern).
#' The artifact carries the registry commit SHA it was derived from
#' (`amrr_registry_ref()`) plus a `materialized_at` timestamp, so it is always
#' traceable back to canonical bytes. It is a derived cache: to update it,
#' re-query the registry and re-materialize -- never edit the binary.
#'
#' @param x An `amrr_metadata` object from [get_metadata()].
#' @param file Output path ending in `.rds` (single object, read with
#'   [readRDS()]) or `.rda`/`.RData` (named object, loaded with [load()]).
#' @param name Object name used inside `.rda` files. Default `"amr_metadata"`.
#' @return Invisibly, `file`.
#' @examples
#' \dontrun{
#' md <- get_metadata("IN", system = "wida-access", year = 2024, registry = ".")
#' amrr_materialize(md, "wida_in_2024.rda", name = "wida_in_2024")
#' load("wida_in_2024.rda")
#' amrr_registry_ref(wida_in_2024)  # the pinned SHA travels with the artifact
#' }
#' @export
amrr_materialize <- function(x, file, name = "amr_metadata") {
  if (!inherits(x, "amrr_metadata")) {
    stop("x must be an amrr_metadata object from get_metadata().", call. = FALSE)
  }
  ref <- amrr_registry_ref(x)
  if (is.na(ref)) {
    warning("No registry commit SHA on this object (registry was not a git checkout); ",
            "the artifact will not be pinned to canonical bytes.", call. = FALSE)
  }
  attr(x, "materialized_at") <-
    format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%OS3+00:00")

  ext <- tolower(tools::file_ext(file))
  if (identical(ext, "rds")) {
    saveRDS(x, file)
  } else if (ext %in% c("rda", "rdata")) {
    env <- new.env(parent = emptyenv())
    assign(name, x, envir = env)
    save(list = name, file = file, envir = env)
  } else {
    stop("file must end in .rds, .rda, or .RData; got: ", file, call. = FALSE)
  }
  invisible(file)
}
