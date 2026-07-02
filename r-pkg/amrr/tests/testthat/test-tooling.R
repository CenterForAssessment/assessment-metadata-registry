# validate_registry() + build_registry() against the bundled fixture registry
# (inst/extdata/registry: a self-contained mini-registry with schemas + DDL).

fixture_registry <- function() {
  reg <- system.file("extdata", "registry", package = "amrr")
  testthat::skip_if(!nzchar(reg) || !dir.exists(file.path(reg, "schemas")),
                    "fixture registry (with schemas) not installed")
  reg
}

test_that("validate_registry passes on the fixture (5 records, 0 errors)", {
  skip_if_not_installed("jsonvalidate")
  reg <- fixture_registry()
  r <- validate_registry(reg, quiet = TRUE, error = FALSE)
  expect_equal(r$n_files, 5L)
  expect_equal(r$n_errors, 0L)
  expect_length(r$results, 0L)
})

test_that("validate_registry(error = TRUE) errors when a sidecar is invalid", {
  skip_if_not_installed("jsonvalidate")
  reg <- fixture_registry()
  tmp <- withr::local_tempdir()
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  # break monotonicity in one cutscore vector
  f <- file.path(tmp, "metadata", "IN", "ilearn", "ilearn-in-2024.json")
  rec <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  rec$cutscores$ELA$`3` <- list(500, 100, 900)
  writeLines(jsonlite::toJSON(rec, pretty = TRUE, auto_unbox = TRUE, null = "null"), f)
  expect_error(validate_registry(tmp, quiet = TRUE), "validation error")
})

test_that("build_registry reproduces the derived layer", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  reg <- fixture_registry()
  out <- withr::local_tempdir()
  m <- build_registry(reg, out = out, quiet = TRUE)

  expect_equal(m$n_records, 5L)
  expect_equal(m$n_assessment_records, 3L)
  expect_equal(m$n_accountability_records, 2L)
  expect_equal(m$n_jurisdictions, 2L)
  for (f in c("index.json", "targets.json", "changelog.json", "manifest.json",
              "registry.sqlite", "tables/vendor_by_year.json")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(out, "registry.sqlite"))
  on.exit(DBI::dbDisconnect(con))
  n_targets <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM accountability_target")$n
  expect_gt(n_targets, 0L)
})
