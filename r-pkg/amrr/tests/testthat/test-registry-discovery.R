# Local registry ergonomics: auto-discovery of a checkout from the working
# directory, so get_metadata() needs no registry argument when R is run inside a
# clone. Discovery only fires when nothing is set explicitly (arg/option/env).

test_that(".discover_registry_root finds a checkout at or above the start dir", {
  reg <- fixture_registry()
  expect_identical(normalizePath(.discover_registry_root(reg)), normalizePath(reg))
  # from a nested subdirectory it walks up to the same root
  sub <- file.path(reg, "metadata", "IN")
  skip_if_not(dir.exists(sub))
  expect_identical(normalizePath(.discover_registry_root(sub)), normalizePath(reg))
})

test_that(".discover_registry_root returns NULL when no checkout is above", {
  tmp <- withr::local_tempdir()   # under the session tmpdir, outside any checkout
  expect_null(.discover_registry_root(tmp))
})

test_that("amrr_registry_root() discovers from the working directory when unset", {
  reg <- fixture_registry()
  withr::local_dir(reg)
  withr::local_options(amrr.registry = NULL)
  withr::local_envvar(AMRR_REGISTRY = NA)
  expect_identical(normalizePath(amrr_registry_root()), normalizePath(reg))
})

test_that("get_metadata() needs no registry arg when run inside a checkout", {
  reg <- fixture_registry()
  withr::local_dir(reg)
  withr::local_options(amrr.registry = NULL)
  withr::local_envvar(AMRR_REGISTRY = NA)
  md <- get_metadata("IN", system = "ilearn", year = 2024)
  expect_s3_class(md, "amrr_metadata")
  expect_length(md, 1L)
})

test_that("amrr_registry_root() errors helpfully when nothing is set and none is found", {
  tmp <- withr::local_tempdir()
  withr::local_dir(tmp)
  withr::local_options(amrr.registry = NULL)
  withr::local_envvar(AMRR_REGISTRY = NA)
  expect_error(amrr_registry_root(), "no checkout was found")
})
