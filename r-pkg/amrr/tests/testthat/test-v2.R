# v2 surface (ADR-009): schema routing, the enrollment axis rule, scale-bound
# invariants, migration, accessors, and materialization -- against the bundled
# fixture registry (which mixes v1 records with one v2 record,
# wida-access-in-2025.json).

v2_fixture_path <- c("metadata", "IN", "wida-access", "wida-access-in-2025.json")

read_fixture_record <- function(reg, path_parts) {
  jsonlite::fromJSON(do.call(file.path, c(list(reg), as.list(path_parts))),
                     simplifyVector = FALSE)
}

# Copy the fixture registry to a tempdir, apply `mutate` to the v2 record, and
# validate; returns the validation report (error = FALSE, warnings suppressed --
# the fixture's v1/v2 mix always raises the dual-window warning).
validate_mutated_v2 <- function(mutate) {
  reg <- fixture_registry()
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  f <- do.call(file.path, c(list(tmp), as.list(v2_fixture_path)))
  rec <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  rec <- mutate(rec)
  writeLines(jsonlite::toJSON(rec, pretty = 2, auto_unbox = TRUE,
                              null = "null", digits = NA), f)
  suppressWarnings(validate_registry(tmp, quiet = TRUE, error = FALSE))
}

test_that("the v2 fixture record validates cleanly as-is", {
  skip_if_not_installed("jsonvalidate")
  r <- validate_mutated_v2(identity)
  expect_equal(r$n_errors, 0L)
})

test_that("axis rule: cutscore grade key outside enrolled_grades_tested fails", {
  skip_if_not_installed("jsonvalidate")
  r <- validate_mutated_v2(function(rec) {
    rec$content_areas[[1]]$enrollment$enrolled_grades_tested <- list("K")  # drops "1"
    rec
  })
  expect_gt(r$n_errors, 0L)
  expect_true(any(grepl("axis rule", unlist(r$results))))
})

test_that("scale envelope: loss above min(cuts) fails", {
  skip_if_not_installed("jsonvalidate")
  r <- validate_mutated_v2(function(rec) {
    rec$scale_bounds$ELP_COMPOSITE$K$loss <- 250  # min cut is 210
    rec
  })
  expect_true(any(grepl("loss 250 > min\\(cutscores\\)", unlist(r$results))))
})

test_that("scale envelope: hoss below max(cuts) fails", {
  skip_if_not_installed("jsonvalidate")
  r <- validate_mutated_v2(function(rec) {
    rec$scale_bounds$ELP_COMPOSITE$`1`$hoss <- 400  # max cut is 420
    rec
  })
  expect_true(any(grepl("hoss 400 < max\\(cutscores\\)", unlist(r$results))))
})

test_that("cutscores_source for a grade with no cutscores fails", {
  skip_if_not_installed("jsonvalidate")
  r <- validate_mutated_v2(function(rec) {
    rec$cutscores_source$ELP_COMPOSITE$`2` <- "official"
    rec$content_areas[[1]]$enrollment$enrolled_grades_tested <-
      as.list(c("K", "1", "2"))
    rec
  })
  expect_true(any(grepl("no cutscores", unlist(r$results))))
})

test_that("schema: measurement.elp on a non-elp assessment_type fails", {
  skip_if_not_installed("jsonvalidate")
  r <- validate_mutated_v2(function(rec) {
    rec$assessment_system$assessment_type <- "summative"
    rec
  })
  expect_gt(r$n_errors, 0L)
})

test_that("schema: enrollment block is required on v2 content areas", {
  skip_if_not_installed("jsonvalidate")
  r <- validate_mutated_v2(function(rec) {
    rec$content_areas[[1]]$enrollment <- NULL
    rec
  })
  expect_gt(r$n_errors, 0L)
})

test_that("migrate_registry dry run reports v1 files and touches nothing", {
  reg <- fixture_registry()
  tmp <- withr::local_tempdir()
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  before <- read_fixture_record(tmp, c("metadata", "IN", "ilearn", "ilearn-in-2024.json"))
  m <- migrate_registry(tmp, write = FALSE, quiet = TRUE)
  expect_equal(m$n_migrated, 5L)   # 6 fixture records, 1 already v2
  expect_equal(m$n_skipped, 1L)
  after <- read_fixture_record(tmp, c("metadata", "IN", "ilearn", "ilearn-in-2024.json"))
  expect_identical(before, after)
})

test_that("migrate_registry rewrites v1 records to a valid v2 corpus", {
  skip_if_not_installed("jsonvalidate")
  reg <- fixture_registry()
  tmp <- withr::local_tempdir()
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  m <- migrate_registry(tmp, quiet = TRUE)
  expect_equal(m$n_migrated, 5L)

  ilearn <- read_fixture_record(tmp, c("metadata", "IN", "ilearn", "ilearn-in-2024.json"))
  expect_identical(ilearn$schema_version, "amr.assessment.v2")
  expect_identical(ilearn$assessment_system$assessment_type, "summative")
  ela <- Filter(function(ca) identical(ca$id, "ELA"), ilearn$content_areas)[[1]]
  expect_identical(ela$enrollment$intended_enrollment_grade, "fixed")
  expect_identical(unlist(ela$enrollment$enrolled_grades_tested),
                   c("3", "4", "5", "6", "7", "8"))

  wida <- read_fixture_record(tmp, c("metadata", "IN", "wida-access", "wida-access-in-2024.json"))
  expect_identical(wida$assessment_system$assessment_type, "elp")
  expect_identical(wida$content_areas[[1]]$enrollment$intended_enrollment_grade, "variable")
  # WIDA v1 fixture has no cutscores -> seeded empty, flagged for authoring.
  expect_length(wida$content_areas[[1]]$enrollment$enrolled_grades_tested, 0L)

  acct <- read_fixture_record(tmp, c("metadata", "IN", "in-accountability", "in-accountability-2024.json"))
  expect_identical(acct$schema_version, "amr.accountability.v2")

  # Fully migrated corpus validates with NO dual-window warning.
  expect_no_warning(r <- validate_registry(tmp, quiet = TRUE, error = FALSE))
  expect_equal(r$n_errors, 0L)

  # Idempotent: a second run skips everything.
  m2 <- migrate_registry(tmp, quiet = TRUE)
  expect_equal(m2$n_migrated, 0L)
  expect_equal(m2$n_skipped, 6L)
})

test_that("v2 accessors read the fixture record; v1 records return NULL", {
  reg <- fixture_registry()
  md <- get_metadata("IN", system = "wida-access", year = 2025, registry = reg)
  expect_length(md, 1L)
  rec <- md[[1]]

  enr <- amrr_enrollment(rec, "ELP_COMPOSITE")
  expect_identical(enr$intended_enrollment_grade, "variable")
  expect_true("K" %in% unlist(enr$enrolled_grades_tested))

  sb <- amrr_scale_bounds(rec, "ELP_COMPOSITE")
  expect_equal(sb$K$loss, 100)
  expect_equal(sb$K$hoss, 600)

  elp <- amrr_elp(rec)
  expect_identical(elp$instrument, "ACCESS for ELLs Online")
  expect_equal(elp$composites$ELP_COMPOSITE$weights$READING, 0.35)
  expect_null(amrr_alternate(rec))

  docs <- amrr_source_documents(rec)
  expect_length(docs, 1L)

  # v1 record: v2 accessors degrade to NULL.
  md_v1 <- get_metadata("IN", system = "wida-access", year = 2024, registry = reg)
  expect_null(amrr_enrollment(md_v1[[1]]))
  expect_null(amrr_scale_bounds(md_v1[[1]]))
  expect_null(amrr_elp(md_v1[[1]]))
})

test_that("accountability v2 accessors return NULL when blocks are absent", {
  reg <- fixture_registry()
  recs <- read_jurisdiction_records(reg, "IN")
  acct <- Filter(is_accountability_record, recs)[[1]]
  expect_null(amrr_growth_targets(acct))
  expect_null(amrr_timelines(acct))
  expect_null(amrr_participation(acct))
})

test_that("amrr_materialize round-trips .rds and .rda with the registry ref", {
  reg <- fixture_registry()
  md <- get_metadata("IN", system = "wida-access", year = 2025, registry = reg)

  rds <- withr::local_tempfile(fileext = ".rds")
  amrr_materialize(md, rds)
  back <- readRDS(rds)
  expect_s3_class(back, "amrr_metadata")
  expect_identical(back[[1]]$administration$id, "wida-access-in-2025")
  expect_identical(amrr_registry_ref(back), amrr_registry_ref(md))
  expect_false(is.null(attr(back, "materialized_at", exact = TRUE)))

  rda <- withr::local_tempfile(fileext = ".rda")
  amrr_materialize(md, rda, name = "wida_in_2025")
  env <- new.env(parent = emptyenv())
  load(rda, envir = env)
  expect_true(exists("wida_in_2025", envir = env))
  expect_identical(env$wida_in_2025[[1]]$assessment_system$id, "wida-access")

  expect_error(amrr_materialize(md, withr::local_tempfile(fileext = ".txt")), "must end in")
  expect_error(amrr_materialize(list(), "x.rds"), "amrr_metadata")
})
