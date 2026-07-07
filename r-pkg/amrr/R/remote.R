# Reproducible remote mode -----------------------------------------------------
#
# Read canonical Tier A sidecars straight from GitHub, pinned to an exact commit
# SHA -- no local checkout, byte-for-byte reconstructable (ADR-011). Only
# `metadata/` and `schemas/` are committed per SHA (the derived `dist/` layer is
# git-ignored), so reproducibility comes from fetching the sidecars at the SHA via
# the git-trees + raw-content APIs, then running the SAME filter/attach pipeline as
# a local read. All helpers are internal and dot-prefixed so tests can mock them.

# Which kind of registry is this? github must win before the generic URL test,
# because https://github.com/owner/repo also matches .is_url_registry().
.registry_kind <- function(registry) {
  if (is.character(registry) && length(registry) == 1L &&
      grepl("^(github://|https?://github\\.com/)", registry)) {
    return("github")
  }
  if (.is_url_registry(registry)) return("derived_url")
  "local"
}

# "github://owner/repo" or "https://github.com/owner/repo(.git)" -> list(owner, repo).
.parse_github_registry <- function(registry) {
  spec <- sub("^github://", "", registry)
  spec <- sub("^https?://github\\.com/", "", spec)
  spec <- sub("/+$", "", spec)          # trailing slashes
  spec <- sub("\\.git$", "", spec)      # a .git suffix
  parts <- strsplit(spec, "/", fixed = TRUE)[[1]]
  if (length(parts) != 2L || !all(nzchar(parts))) {
    stop(sprintf(
      "Could not parse a GitHub 'owner/repo' from registry '%s'.", registry),
      call. = FALSE)
  }
  list(owner = parts[[1L]], repo = parts[[2L]])
}

# First non-empty GitHub token from the environment (empty string = unauthenticated).
.gh_token <- function() {
  for (v in c("AMRR_GITHUB_TOKEN", "GITHUB_PAT", "GITHUB_TOKEN")) {
    tok <- Sys.getenv(v, "")
    if (nzchar(tok)) return(tok)
  }
  ""
}

# One HTTP GET. curl is the engine when available (real headers, status codes,
# token); otherwise a base-R unauthenticated fallback so a public read needs no
# new hard dependency. Returns list(status, headers, body); classifies the common
# GitHub failures into actionable errors.
.gh_http_get <- function(url, token = .gh_token(),
                         accept = "application/vnd.github+json") {
  if (requireNamespace("curl", quietly = TRUE)) {
    h <- curl::new_handle()
    hdrs <- list(Accept = accept, `X-GitHub-Api-Version` = "2022-11-28",
                 `User-Agent` = "amrr-r-client")
    if (nzchar(token)) hdrs$Authorization <- paste("Bearer", token)
    curl::handle_setheaders(h, .list = hdrs)
    resp <- curl::curl_fetch_memory(url, handle = h)
    status <- resp$status_code
    headers <- curl::parse_headers_list(resp$headers)
    body <- rawToChar(resp$content)
    if (status != 200L) .gh_stop_for_status(url, status, headers, body)
    list(status = status, headers = headers, body = body)
  } else {
    if (nzchar(token)) {
      warning("A GitHub token is set but the 'curl' package is not installed; ",
              "reading unauthenticated. Install 'curl' to use the token.",
              call. = FALSE)
    }
    body <- tryCatch({
      con <- base::url(url, encoding = "UTF-8")
      on.exit(close(con))
      paste(readLines(con, warn = FALSE), collapse = "\n")
    }, error = function(e) stop(sprintf(
      "HTTP GET failed for %s: %s (install the 'curl' package for robust, authenticated remote reads).",
      url, conditionMessage(e)), call. = FALSE))
    list(status = 200L, headers = list(), body = body)
  }
}

# Turn a non-200 GitHub response into an actionable error.
.gh_stop_for_status <- function(url, status, headers, body) {
  remaining <- headers[["x-ratelimit-remaining"]]
  if (status %in% c(403L, 429L) && identical(remaining, "0")) {
    stop("GitHub API rate limit exceeded. Set AMRR_GITHUB_TOKEN (or GITHUB_PAT) ",
         "to a personal access token to raise the limit; unauthenticated is ",
         "60 requests/hour.", call. = FALSE)
  }
  if (status == 401L) {
    stop("GitHub rejected the token (HTTP 401); check AMRR_GITHUB_TOKEN.",
         call. = FALSE)
  }
  stop(sprintf("GitHub request failed (HTTP %d) for %s", status, url),
       call. = FALSE)
}

# Immutable-read seam: every content-addressed fetch (trees at a SHA, raw sidecar
# at a SHA) flows through these two. A future on-disk cache keyed by URL/SHA/path
# wraps them here, with zero change to callers (ADR-011).
.gh_get_json <- function(url, token = .gh_token()) {
  jsonlite::fromJSON(.gh_http_get(url, token)$body, simplifyVector = FALSE)
}
.gh_get_raw <- function(url, token = .gh_token()) {
  .gh_http_get(url, token, accept = "application/vnd.github.raw")$body
}

# Resolve a ref (SHA | branch | tag | NULL->HEAD) to a concrete 40-hex commit SHA.
# This is the ONLY mutable step -- a branch/tag moves, a SHA never does -- so it is
# isolated and never cached. A full SHA short-circuits without any network call.
.gh_resolve_sha <- function(owner, repo, ref = NULL, token = .gh_token()) {
  if (is.character(ref) && length(ref) == 1L && grepl("^[0-9a-f]{40}$", ref)) {
    return(ref)
  }
  target <- if (is.null(ref)) "HEAD" else ref
  url <- sprintf("https://api.github.com/repos/%s/%s/commits/%s", owner, repo,
                 utils::URLencode(target, reserved = TRUE))
  commit <- tryCatch(
    .gh_get_json(url, token),
    error = function(e) stop(sprintf(
      "Could not resolve ref '%s' in %s/%s: %s",
      target, owner, repo, conditionMessage(e)), call. = FALSE)
  )
  sha <- commit$sha
  if (!is.character(sha) || !nzchar(sha)) {
    stop(sprintf("GitHub returned no commit SHA for ref '%s' in %s/%s.",
                 target, owner, repo), call. = FALSE)
  }
  sha
}

# Repo-relative paths of a jurisdiction's sidecars at a SHA, via one recursive
# git-trees call filtered to metadata/<jur>/*.json. Falls back to a jurisdiction-
# scoped subtree walk if the recursive tree is truncated (large-repo guard).
.gh_list_jurisdiction_paths <- function(owner, repo, sha, jurisdiction,
                                        token = .gh_token()) {
  base <- sprintf("https://api.github.com/repos/%s/%s/git/trees", owner, repo)
  tree <- .gh_get_json(sprintf("%s/%s?recursive=1", base, sha), token)
  pat <- sprintf("^metadata/%s/.*\\.json$", jurisdiction)
  if (isTRUE(tree$truncated)) {
    return(.gh_list_jurisdiction_paths_subtree(base, sha, jurisdiction, token))
  }
  paths <- vapply(tree$tree, function(e) {
    if (identical(e$type, "blob") && grepl(pat, e$path)) e$path else NA_character_
  }, character(1L))
  paths[!is.na(paths)]
}

# Truncation fallback: descend blob-by-blob into metadata/<jur>/ (a single
# jurisdiction subtree is tiny and will not truncate), then re-prefix the paths.
.gh_list_jurisdiction_paths_subtree <- function(base, sha, jurisdiction, token) {
  find_child <- function(tree_sha, name) {
    node <- .gh_get_json(sprintf("%s/%s", base, tree_sha), token)
    for (e in node$tree) if (identical(e$path, name) && identical(e$type, "tree")) {
      return(e$sha)
    }
    NULL
  }
  meta_sha <- find_child(sha, "metadata")
  jur_sha <- if (!is.null(meta_sha)) find_child(meta_sha, jurisdiction) else NULL
  if (is.null(jur_sha)) return(character(0L))
  sub <- .gh_get_json(sprintf("%s/%s?recursive=1", base, jur_sha), token)
  rel <- vapply(sub$tree, function(e) {
    if (identical(e$type, "blob") && grepl("\\.json$", e$path)) e$path else NA_character_
  }, character(1L))
  rel <- rel[!is.na(rel)]
  sprintf("metadata/%s/%s", jurisdiction, rel)
}

# Fetch + parse every canonical sidecar for a jurisdiction at a concrete SHA.
# Fail-closed: if the jurisdiction is absent, or ANY sidecar fails to fetch/parse,
# abort -- a partial jurisdiction would silently break reproducibility. Records are
# parsed exactly like read_jurisdiction_records() so they flow through the existing
# filter/attach pipeline unchanged.
.fetch_github_records <- function(owner, repo, sha, jurisdiction,
                                  token = .gh_token()) {
  paths <- .gh_list_jurisdiction_paths(owner, repo, sha, jurisdiction, token)
  if (length(paths) == 0L) {
    stop(sprintf("Jurisdiction '%s' not found in %s/%s at %s.",
                 jurisdiction, owner, repo, substr(sha, 1L, 8L)), call. = FALSE)
  }
  paths <- sort(paths, method = "radix")   # deterministic assembly order
  lapply(paths, function(path) {
    raw_url <- sprintf("https://raw.githubusercontent.com/%s/%s/%s/%s",
                       owner, repo, sha, path)
    txt <- tryCatch(.gh_get_raw(raw_url, token), error = function(e) stop(sprintf(
      "Failed to fetch sidecar '%s' at %s: %s",
      path, substr(sha, 1L, 8L), conditionMessage(e)), call. = FALSE))
    rec <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
      error = function(e) stop(sprintf(
        "Failed to parse sidecar '%s' at %s: %s",
        path, substr(sha, 1L, 8L), conditionMessage(e)), call. = FALSE))
    attr(rec, "source_path") <- raw_url
    rec
  })
}
