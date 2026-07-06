# Remote registries: get_metadata() against (a) a published derived bundle
# (<base>/dist/<jur>.json) and (b) a GitHub repo pinned to a commit SHA
# (github://owner/repo). Exercised network-free via a file:// URL over a built
# fixture corpus and via mocked GitHub fetch primitives; plus a guarded live test.

test_that(".is_url_registry recognizes URL schemes, not local paths", {
  expect_true(.is_url_registry("https://example.org/registry"))
  expect_true(.is_url_registry("http://example.org"))
  expect_true(.is_url_registry("file:///tmp/build"))
  expect_false(.is_url_registry("."))
  expect_false(.is_url_registry("/abs/path/to/registry"))
  expect_false(.is_url_registry(NULL))
})

test_that("get_metadata reads a file:// bundle and matches the local-checkout result", {
  skip_if_not_installed("DBI"); skip_if_not_installed("RSQLite"); skip_if_not_installed("digest")
  reg <- fixture_registry()
  tmp <- withr::local_tempdir()
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  migrate_registry(tmp, quiet = TRUE)            # v2 corpus
  out <- withr::local_tempdir()
  build_registry(tmp, out = out, quiet = TRUE)   # derive the dist bundles
  base <- paste0("file://", normalizePath(out))

  remote <- get_metadata("IN", system = "ilearn", year = 2024, registry = base)
  expect_s3_class(remote, "amrr_metadata")
  expect_length(remote, 1L)
  expect_identical(remote[[1]]$schema_version, "amr.assessment.v2")

  # Semantically identical to reading the same corpus from the local checkout,
  # including the pin and the accountability target re-merge. (The tempdir build
  # is not a git repo, so both pins are NA — the point is they agree.)
  local <- get_metadata("IN", system = "ilearn", year = 2024, registry = tmp)
  expect_identical(amrr_registry_ref(remote), amrr_registry_ref(local))
  expect_equal(amrr_cutscores(remote[[1]], "ELA"), amrr_cutscores(local[[1]], "ELA"))
  expect_equal(amrr_targets(remote[[1]], "ELA"), amrr_targets(local[[1]], "ELA"))
})

test_that("get_metadata errors clearly when a remote bundle is missing", {
  base <- paste0("file://", normalizePath(withr::local_tempdir()))
  expect_error(get_metadata("ZZ", registry = base), "Could not fetch")
})

test_that("the bundle git_sha becomes the pin, and a ref mismatch warns", {
  out <- withr::local_tempdir()
  dir.create(file.path(out, "dist"))
  bundle <- list(
    `_registry` = list(git_sha = "abc1234"),
    jurisdiction_id = "IN",
    records = list(list(
      schema_version = "amr.assessment.v2",
      jurisdiction = list(id = "IN", name = "Indiana", type = "state"),
      assessment_system = list(id = "ilearn", name = "ILEARN", family = "ILEARN",
                               assessment_type = "summative"),
      administration = list(id = "ilearn-in-2024", year = "2024"),
      content_areas = list(list(id = "ELA", vertical_scale = FALSE,
        enrollment = list(intended_enrollment_grade = "fixed",
                          enrolled_grades_tested = list("3")))))))
  writeLines(jsonlite::toJSON(bundle, auto_unbox = TRUE, null = "null"),
             file.path(out, "dist", "IN.json"))
  base <- paste0("file://", normalizePath(out))

  expect_identical(amrr_registry_ref(get_metadata("IN", registry = base)), "abc1234")
  expect_warning(get_metadata("IN", registry = base, ref = "deadbeef"), "requested ref")
})


# --- Reproducible GitHub mode (github://owner/repo, pinned by commit SHA) ------

test_that(".registry_kind classifies github, derived_url, and local", {
  expect_identical(.registry_kind("github://o/r"), "github")
  expect_identical(.registry_kind("https://github.com/o/r"), "github")
  expect_identical(.registry_kind("http://github.com/o/r.git"), "github")
  # github must win over the generic URL matcher (regression guard):
  expect_identical(.registry_kind("https://example.org/registry"), "derived_url")
  expect_identical(.registry_kind("file:///tmp/build"), "derived_url")
  expect_identical(.registry_kind("."), "local")
  expect_identical(.registry_kind("/abs/path"), "local")
  expect_identical(.registry_kind(NULL), "local")
})

test_that(".parse_github_registry handles both schemes, trailing slash, and .git", {
  expect_identical(
    .parse_github_registry("github://CenterForAssessment/assessment-metadata-registry"),
    list(owner = "CenterForAssessment", repo = "assessment-metadata-registry"))
  expect_identical(.parse_github_registry("https://github.com/o/r/"),
                   list(owner = "o", repo = "r"))
  expect_identical(.parse_github_registry("https://github.com/o/r.git"),
                   list(owner = "o", repo = "r"))
  expect_error(.parse_github_registry("github://not-a-repo"), "owner/repo")
})

test_that(".gh_resolve_sha short-circuits a full SHA without any network call", {
  full <- paste(rep("a", 40), collapse = "")
  testthat::local_mocked_bindings(
    .gh_get_json = function(url, token = "") stop("network must not be called"))
  expect_identical(.gh_resolve_sha("o", "r", ref = full), full)
})

test_that(".gh_resolve_sha resolves a branch/tag to a concrete SHA via the API", {
  beef <- paste(rep("b", 40), collapse = "")
  testthat::local_mocked_bindings(
    .gh_get_json = function(url, token = "") list(sha = beef))
  expect_identical(.gh_resolve_sha("o", "r", ref = "main"), beef)
})

test_that("an unresolvable ref is a clear error", {
  testthat::local_mocked_bindings(
    .gh_get_json = function(url, token = "") stop("HTTP 404"))
  expect_error(.gh_resolve_sha("o", "r", ref = "no-such-ref"), "Could not resolve ref")
})

test_that(".gh_stop_for_status maps a rate-limited 403 / bad token to a hint", {
  expect_error(.gh_stop_for_status("u", 403L, list(`x-ratelimit-remaining` = "0"), ""),
               "rate limit")
  expect_error(.gh_stop_for_status("u", 401L, list(), ""), "token")
})

test_that("github mode assembles the same records as a local checkout read", {
  skip_if_not_installed("jsonvalidate")
  reg <- fixture_registry()
  tmp <- withr::local_tempdir()
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  migrate_registry(tmp, quiet = TRUE)                       # v2 corpus (cutscores present)
  fake_sha <- paste(rep("f", 40), collapse = "")

  testthat::local_mocked_bindings(
    .gh_resolve_sha = function(owner, repo, ref = NULL, token = "") fake_sha,
    .gh_list_jurisdiction_paths = function(owner, repo, sha, jurisdiction, token = "") {
      rel <- list.files(file.path(tmp, "metadata", jurisdiction), recursive = TRUE)
      file.path("metadata", jurisdiction, rel)
    },
    .gh_get_raw = function(url, token = "") {
      path <- regmatches(url, regexpr("metadata/.*$", url))
      f <- file.path(tmp, path)
      readChar(f, file.info(f)$size, useBytes = TRUE)
    })

  gh    <- get_metadata("IN", system = "ilearn", year = 2024, registry = "github://o/r")
  local <- get_metadata("IN", system = "ilearn", year = 2024, registry = tmp)

  expect_s3_class(gh, "amrr_metadata")
  expect_length(gh, 1L)
  expect_identical(gh[[1]]$schema_version, "amr.assessment.v2")
  expect_identical(amrr_registry_ref(gh), fake_sha)                 # concrete pin recorded
  expect_identical(attr(gh, "registry_root", exact = TRUE), "github://o/r")
  expect_equal(amrr_cutscores(gh[[1]], "ELA"), amrr_cutscores(local[[1]], "ELA"))
  expect_equal(amrr_targets(gh[[1]], "ELA"),  amrr_targets(local[[1]], "ELA"))

  gh2 <- get_metadata("IN", system = "ilearn", year = 2024, registry = "github://o/r")
  expect_equal(gh, gh2)                                             # idempotent / byte-stable
})

test_that("github mode fails closed on a missing jurisdiction (no partial return)", {
  fake_sha <- paste(rep("f", 40), collapse = "")
  testthat::local_mocked_bindings(
    .gh_resolve_sha = function(owner, repo, ref = NULL, token = "") fake_sha,
    .gh_list_jurisdiction_paths = function(owner, repo, sha, jurisdiction, token = "") character(0))
  expect_error(get_metadata("ZZ", registry = "github://o/r"), "not found")
})

test_that("github mode aborts if any sidecar fetch fails (fail-closed)", {
  reg <- fixture_registry()
  fake_sha <- paste(rep("f", 40), collapse = "")
  testthat::local_mocked_bindings(
    .gh_resolve_sha = function(owner, repo, ref = NULL, token = "") fake_sha,
    .gh_list_jurisdiction_paths = function(owner, repo, sha, jurisdiction, token = "")
      file.path("metadata", jurisdiction,
                list.files(file.path(reg, "metadata", jurisdiction), recursive = TRUE)),
    .gh_get_raw = function(url, token = "") stop("boom"))
  expect_error(get_metadata("IN", system = "ilearn", registry = "github://o/r"),
               "Failed to fetch sidecar")
})

test_that("[live] github mode reads canonical sidecars at a real commit SHA", {
  skip_on_cran()
  testthat::skip_if_offline()
  skip_if_not_installed("curl")
  reg <- "github://CenterForAssessment/assessment-metadata-registry"
  md <- tryCatch(
    get_metadata("IN", system = "ilearn", year = 2024, registry = reg, ref = "b824b20"),
    error = function(e) skip(paste("live GitHub read unavailable:", conditionMessage(e))))
  expect_s3_class(md, "amrr_metadata")
  expect_length(md, 1L)
  expect_identical(md[[1]]$schema_version, "amr.assessment.v2")
  expect_identical(amrr_achievement_levels(md[[1]], "ELA")$proficient_from, "At Proficiency")
  expect_equal(amrr_targets(md[[1]], "ELA")$per_grade_scale_score$`3`, 497)
  expect_match(amrr_registry_ref(md), "^[0-9a-f]{40}$")            # ref resolved to a full SHA
})
