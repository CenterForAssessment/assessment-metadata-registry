registry <- function() system.file("extdata/registry", package = "amrr")

test_that("a second jurisdiction (demo State C) reads independently", {
  md <- get_metadata("SC", system = "sc-summative", year = 2015, registry = registry())
  expect_length(md, 1L)
  expect_identical(md[[1]]$jurisdiction$id, "SC")
})

test_that("scale_score exit target on a summative attaches from accountability", {
  md <- get_metadata("SC", system = "sc-summative", year = 2015, registry = registry())
  tgt <- amrr_targets(md[[1]], "ELA")
  expect_identical(tgt$semantics, "exit")
  expect_identical(tgt$basis, "scale_score")
  expect_equal(tgt$per_grade_scale_score[["3"]], 730)
})

test_that("comparability block surfaces the scale transition", {
  md <- get_metadata("SC", system = "sc-summative", year = 2015, registry = registry())
  comp <- amrr_comparability(md[[1]])
  expect_true(comp$scale_transition)
  expect_false(comp$comparable_to_prior_year)
  expect_identical(comp$prior_scale_name, "State C Legacy Scale")
})
