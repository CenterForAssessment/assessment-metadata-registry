# The compact assessment-config view (ADR-010): as_config() projection and the
# read_config() inverse, exercised against a migrated (v2) fixture corpus.

# Migrate the fixture to a v2 corpus in a tempdir and return IN ilearn records.
ilearn_v2_records <- function(env = parent.frame()) {
  reg <- fixture_registry()
  tmp <- withr::local_tempdir(.local_envir = env)
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  migrate_registry(tmp, quiet = TRUE)
  recs <- read_jurisdiction_records(tmp, "IN")
  Filter(function(r) is_assessment_record(r) && identical(r$assessment_system$id, "ilearn"), recs)
}

test_that("as_config projects one system into the compact shape with deduped level schemes", {
  cfg <- as_config(ilearn_v2_records())
  expect_identical(cfg$schema_version, "amr.assessment_config.v1")
  expect_identical(cfg$program$id, "ilearn")
  # ELA + MATH share one 4-level scheme -> exactly one scheme, both tests reference it.
  expect_length(cfg$level_schemes, 1L)
  expect_identical(cfg$tests$ela$level_scheme, cfg$tests$mathematics$level_scheme)
  expect_identical(cfg$level_schemes[[cfg$tests$ela$level_scheme]]$proficient_from, "At Proficiency")
  # map: enrolled grade 3 ELA -> the ela test; unified cuts carry values.
  expect_identical(cfg$map$ELA$`3`, "ela")
  expect_length(cfg$tests$ela$cuts$`3`$values, 3L)
  # snapshot is the latest year; tested_years spans the corpus.
  expect_identical(cfg$program$year, max(unlist(cfg$years$tested_years)))
})

test_that("as_config rejects mixed jurisdictions/systems", {
  reg <- fixture_registry()
  recs <- Filter(is_assessment_record, read_jurisdiction_records(reg, "IN"))
  expect_error(as_config(recs), "one jurisdiction")
})

test_that("read_config(as_config(x)) round-trips the core facts for the snapshot year", {
  recs <- ilearn_v2_records()
  cfg <- as_config(recs)
  snap_year <- max(vapply(recs, function(r) as.integer(r$administration$year), integer(1)))
  orig <- Filter(function(r) as.integer(r$administration$year) == snap_year, recs)[[1]]
  back <- read_config(cfg)

  expect_identical(back$schema_version, "amr.assessment.v2")
  expect_identical(back$assessment_system$assessment_type, orig$assessment_system$assessment_type)
  expect_identical(back$administration$id, orig$administration$id)

  ca_back <- Filter(function(c) identical(c$id, "ELA"), back$content_areas)[[1]]
  ca_orig <- Filter(function(c) identical(c$id, "ELA"), orig$content_areas)[[1]]
  expect_identical(unlist(ca_back$enrollment$enrolled_grades_tested),
                   unlist(ca_orig$enrollment$enrolled_grades_tested))
  expect_identical(ca_back$enrollment$intended_enrollment_grade,
                   ca_orig$enrollment$intended_enrollment_grade)
  expect_identical(back$achievement_levels$ELA$proficient_from, "At Proficiency")
  expect_equal(unlist(back$cutscores$ELA$`3`), unlist(orig$cutscores$ELA$`3`))
})

test_that("the reconstructed record validates as a v2 assessment", {
  skip_if_not_installed("jsonvalidate")
  back <- read_config(as_config(ilearn_v2_records()))
  raw <- jsonlite::toJSON(back, auto_unbox = TRUE, null = "null", digits = NA)
  v <- .load_validator(file.path(fixture_registry(), "schemas", "amr.assessment.v2.schema.json"))
  expect_length(.schema_errors(v, raw), 0L)
  expect_length(.v2_assessment_invariants(back), 0L)
})

test_that("build_registry emits the compact config projection (build/config/*.json)", {
  skip_if_not_installed("DBI"); skip_if_not_installed("RSQLite"); skip_if_not_installed("digest")
  reg <- fixture_registry()
  tmp <- withr::local_tempdir()
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  migrate_registry(tmp, quiet = TRUE)  # v2 corpus so as_config sees enrollment
  out <- withr::local_tempdir()
  build_registry(tmp, out = out, quiet = TRUE)
  cfgs <- list.files(file.path(out, "config"), pattern = "\\.json$")
  expect_true(length(cfgs) >= 1L)
  ex <- jsonlite::fromJSON(file.path(out, "config", cfgs[[1]]), simplifyVector = FALSE)
  expect_identical(ex$schema_version, "amr.assessment_config.v1")
})

test_that("EOC records project to a single 'eoc' cut key + not_grade_bound, and restore", {
  eoc <- list(
    schema_version = "amr.assessment.v2", status = "draft",
    jurisdiction = list(id = "XX", name = "Example State", type = "state"),
    assessment_system = list(id = "ex-alg1", name = "Algebra I EOC", family = "EX",
                             assessment_type = "end-of-course"),
    administration = list(id = "ex-alg1-2025", year = "2025"),
    content_areas = list(list(id = "ALGEBRA_I", label = "Algebra I", vertical_scale = FALSE,
      scale_name = "Algebra I EOC scale",
      enrollment = list(intended_enrollment_grade = "variable",
                        enrolled_grades_tested = as.list(c("7", "8", "9", "10", "11", "12"))))),
    achievement_levels = list(ALGEBRA_I = list(labels = list("BB", "B", "P", "A"),
                                               proficient_from = "P")),
    cutscores = list(ALGEBRA_I = list(eoc = list(480, 520, 560))),
    scale_bounds = list(ALGEBRA_I = list(eoc = list(loss = 400, hoss = 640)))
  )
  cfg <- as_config(eoc)
  expect_identical(cfg$tests$algebra_i$intended_grades, "not_grade_bound")
  expect_equal(unlist(cfg$tests$algebra_i$cuts$eoc$values), c(480, 520, 560))
  expect_identical(cfg$map$ALGEBRA_I$`7`, "algebra_i")  # map still lists enrolled grades

  back <- read_config(cfg)
  expect_equal(unlist(back$cutscores$ALGEBRA_I$eoc), c(480, 520, 560))
  expect_identical(unlist(back$content_areas[[1]]$enrollment$enrolled_grades_tested),
                   c("7", "8", "9", "10", "11", "12"))
  expect_length(.v2_assessment_invariants(back), 0L)
})
