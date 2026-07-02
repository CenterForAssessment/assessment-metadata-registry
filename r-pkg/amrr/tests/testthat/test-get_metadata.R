registry <- function() system.file("extdata/registry", package = "amrr")

test_that("get_metadata reads a jurisdiction and filters by system + year", {
  md <- get_metadata("IN", system = "wida-access", year = 2024, registry = registry())
  expect_s3_class(md, "amrr_metadata")
  expect_length(md, 1L)
  expect_identical(md[[1]]$assessment_system$id, "wida-access")
  expect_identical(md[[1]]$administration$year, "2024")
})

test_that("year filter accepts numeric or character", {
  a <- get_metadata("IN", system = "ilearn", year = 2024, registry = registry())
  b <- get_metadata("IN", system = "ilearn", year = "2024", registry = registry())
  expect_length(a, 1L)
  expect_length(b, 1L)
})

test_that("unknown jurisdiction errors", {
  expect_error(get_metadata("ZZ", registry = registry()), "Jurisdiction not found")
})

test_that("missing registry root errors clearly", {
  withr::local_options(amrr.registry = NULL)
  withr::local_envvar(AMRR_REGISTRY = "")
  expect_error(get_metadata("IN"), "No registry root")
})

test_that("accessors return expected fields", {
  md <- get_metadata("IN", system = "ilearn", year = 2024, registry = registry())
  rec <- md[[1]]
  expect_identical(amrr_vendor(rec), "Indiana Department of Education")
  expect_true("ELA" %in% names(amrr_cutscores(rec)))
  expect_true(!is.null(amrr_achievement_levels(rec, "ELA")$labels))
})
