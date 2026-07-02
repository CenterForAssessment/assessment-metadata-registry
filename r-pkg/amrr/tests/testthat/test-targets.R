registry <- function() system.file("extdata/registry", package = "amrr")

test_that("WIDA exit target (scale_score) is attached from accountability record", {
  md <- get_metadata("IN", system = "wida-access", year = 2024, registry = registry())
  tgt <- amrr_targets(md[[1]], "ELP_COMPOSITE")
  expect_identical(tgt$semantics, "exit")
  expect_identical(tgt$basis, "scale_score")
  expect_identical(tgt$resolved_from, "explicit")
  expect_equal(tgt$per_grade_scale_score[["5"]], 364.4)
})

test_that("ILEARN proficiency target resolves from cutscores (boundary = first proficient level)", {
  md <- get_metadata("IN", system = "ilearn", year = 2024, registry = registry())
  tgt <- amrr_targets(md[[1]], "ELA")
  expect_identical(tgt$semantics, "proficiency")
  expect_identical(tgt$basis, "proficiency_boundary")
  expect_identical(tgt$resolved_from, "cutscores")
  # ELA proficient mask [F,F,T,T]; grade 3 cuts [462,497,525] -> entering level 3 = 497
  expect_equal(tgt$per_grade_scale_score[["3"]], 497)
})

test_that("attach_targets = FALSE leaves the assessment record target-free", {
  md <- get_metadata("IN", system = "wida-access", year = 2024,
                     registry = registry(), attach_targets = FALSE)
  expect_null(md[[1]]$achievement_targets)
})
