# Remote registry: get_metadata() against a published derived bundle
# (<base>/dist/<jur>.json) instead of a local checkout. Exercised network-free via
# a file:// URL over a freshly built fixture corpus.

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
