# ADR-013: design block, amrr_design(), and the six D3 invariants.

naep_like <- function(mutate = identity) {
  rec <- list(
    schema_version = "amr.assessment.v2",
    status = "draft",
    jurisdiction = list(id = "US", name = "United States", type = "nation"),
    assessment_system = list(
      id = "naep",
      name = "NAEP",
      family = "NAEP",
      assessment_type = "national-sample"
    ),
    administration = list(id = "naep-us-2015", year = "2015"),
    design = list(
      student_sampling = "multistage",
      scoring_model = "scale",
      plausible_values = list(count = 20L, variable_prefix = "MRPCM"),
      weights = list(
        full_sample_variable = "ORIGWT",
        replicate = list(
          method = "JK1",
          zones = 62L,
          replicates = 62L,
          variance_factor = 1,
          variable_prefix = "SRWT"
        )
      ),
      cycle_years = list("2015")
    )
  )
  mutate(rec)
}

timss_like <- function(mutate = identity) {
  rec <- list(
    schema_version = "amr.assessment.v2",
    status = "draft",
    jurisdiction = list(
      id = "INTL",
      name = "International",
      type = "international"
    ),
    assessment_system = list(
      id = "timss",
      name = "TIMSS",
      family = "TIMSS",
      assessment_type = "international-sample"
    ),
    administration = list(id = "timss-intl-2019", year = "2019"),
    design = list(
      student_sampling = "multistage",
      scoring_model = "scale",
      plausible_values = list(
        count = 5L,
        variable_prefix = list(
          MATHEMATICS = list(`4` = "ASMMAT", `8` = "BSMMAT")
        )
      ),
      weights = list(
        full_sample_variable = "TOTWGT",
        replicate = list(
          method = "JK2",
          zones = 75L,
          replicates = 150L,
          variance_factor = 0.5,
          zone_variable = "JKZONE",
          rep_variable = "JKREP"
        )
      ),
      cycle_years = list("2018", "2019")
    )
  )
  mutate(rec)
}

write_sidecar <- function(root, rel, rec) {
  path <- file.path(root, rel)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  rec[["_source_path"]] <- NULL
  writeLines(
    jsonlite::toJSON(
      rec,
      pretty = 2,
      auto_unbox = TRUE,
      null = "null",
      digits = NA
    ),
    path
  )
}

local_copied_registry <- function(env = parent.frame()) {
  reg <- fixture_registry()
  tmp <- withr::local_tempdir(.local_envir = env)
  file.copy(list.files(reg, full.names = TRUE), tmp, recursive = TRUE)
  tmp
}

mutate_v2_fixture <- function(mutate) {
  tmp <- local_copied_registry()
  f <- file.path(
    tmp,
    "metadata",
    "IN",
    "wida-access",
    "wida-access-in-2025.json"
  )
  rec <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  rec <- mutate(rec)
  writeLines(
    jsonlite::toJSON(
      rec,
      pretty = 2,
      auto_unbox = TRUE,
      null = "null",
      digits = NA
    ),
    f
  )
  suppressWarnings(validate_registry(tmp, quiet = TRUE, error = FALSE))
}

# --- D3.1 / D3.2 type pairing ------------------------------------------------

test_that("D3.1 international-sample requires international or benchmarking-entity", {
  ok <- timss_like()
  expect_length(.design_invariants(ok), 0L)

  bench <- timss_like(function(rec) {
    rec$jurisdiction$type <- "benchmarking-entity"
    rec
  })
  expect_length(.design_invariants(bench), 0L)

  bad <- timss_like(function(rec) {
    rec$jurisdiction$type <- "nation"
    rec
  })
  expect_match(
    .design_invariants(bad),
    "international-sample' requires jurisdiction.type in \\{international, benchmarking-entity\\}",
    all = FALSE
  )
})

test_that("D3.2 national-sample requires nation", {
  expect_length(.design_invariants(naep_like()), 0L)

  bad <- naep_like(function(rec) {
    rec$jurisdiction$type <- "state"
    rec
  })
  expect_match(
    .design_invariants(bad),
    "national-sample' requires jurisdiction.type = 'nation'",
    all = FALSE
  )
})

# --- D3.3 plausible values => scale ------------------------------------------

test_that("D3.3 PV count >= 1 requires design.scoring_model scale", {
  omit_sm <- naep_like(function(rec) {
    rec$design$scoring_model <- NULL
    rec
  })
  expect_length(.design_invariants(omit_sm), 0L)

  bad <- naep_like(function(rec) {
    rec$design$scoring_model <- "profile"
    rec
  })
  expect_match(
    .design_invariants(bad),
    "plausible_values.count >= 1 requires design.scoring_model = 'scale'",
    all = FALSE
  )
})

test_that("D3.3 design and alternate scoring_model must agree when PVs are present", {
  bad <- naep_like(function(rec) {
    rec$measurement <- list(alternate = list(scoring_model = "profile"))
    rec
  })
  expect_match(
    .design_invariants(bad),
    "disagrees with measurement.alternate.scoring_model",
    all = FALSE
  )

  ok <- naep_like(function(rec) {
    rec$measurement <- list(alternate = list(scoring_model = "scale"))
    rec
  })
  expect_length(.design_invariants(ok), 0L)
})

# --- D3.4 replicate variance rule --------------------------------------------

test_that("D3.4 JK1/BRR require variable_prefix; zones/replicates/factor match", {
  expect_length(.design_invariants(naep_like()), 0L)

  brr <- naep_like(function(rec) {
    rec$design$weights$replicate$method <- "BRR"
    rec
  })
  expect_length(.design_invariants(brr), 0L)

  missing_prefix <- naep_like(function(rec) {
    rec$design$weights$replicate$variable_prefix <- NULL
    rec
  })
  expect_match(
    .design_invariants(missing_prefix),
    "method 'JK1' requires variable_prefix",
    all = FALSE
  )

  bad_count <- naep_like(function(rec) {
    rec$design$weights$replicate$replicates <- 63L
    rec
  })
  expect_match(
    .design_invariants(bad_count),
    "replicates must equal zones or 2 \\* zones",
    all = FALSE
  )

  bad_factor <- naep_like(function(rec) {
    rec$design$weights$replicate$variance_factor <- 0.5
    rec
  })
  expect_match(
    .design_invariants(bad_factor),
    "variance_factor must be 1 when replicates = zones",
    all = FALSE
  )
})

test_that("D3.4 JK2 requires zone_variable and rep_variable and forbids prefix", {
  expect_length(.design_invariants(timss_like()), 0L)

  with_prefix <- timss_like(function(rec) {
    rec$design$weights$replicate$variable_prefix <- "SRWT"
    rec
  })
  expect_match(
    .design_invariants(with_prefix),
    "method 'JK2' requires zone_variable and rep_variable and forbids variable_prefix",
    all = FALSE
  )

  missing_zone <- timss_like(function(rec) {
    rec$design$weights$replicate$zone_variable <- NULL
    rec
  })
  expect_match(
    .design_invariants(missing_zone),
    "method 'JK2' requires zone_variable",
    all = FALSE
  )

  bad_factor <- timss_like(function(rec) {
    rec$design$weights$replicate$variance_factor <- 1
    rec
  })
  expect_match(
    .design_invariants(bad_factor),
    "variance_factor must be 0.5 when replicates = 2 \\* zones",
    all = FALSE
  )
})

test_that("D3.4 missing zones/replicates/variance_factor are reported", {
  stripped <- naep_like(function(rec) {
    rec$design$weights$replicate$zones <- NULL
    rec$design$weights$replicate$replicates <- NULL
    rec$design$weights$replicate$variance_factor <- NULL
    rec
  })
  errs <- .design_invariants(stripped)
  expect_match(errs, "replicate.zones is required", all = FALSE)
  expect_match(errs, "replicate.replicates is required", all = FALSE)
  expect_match(errs, "replicate.variance_factor is required", all = FALSE)
})

# --- D3.5 cycle_years --------------------------------------------------------

test_that("D3.5 cycle_years must include administration.year", {
  expect_length(.design_invariants(timss_like()), 0L)

  bad <- timss_like(function(rec) {
    rec$design$cycle_years <- list("2018")
    rec
  })
  expect_match(
    .design_invariants(bad),
    "cycle_years must include administration.year '2019'",
    all = FALSE
  )
})

# --- D3.6 longitudinal_link --------------------------------------------------

test_that("D3.6 linked_administration_id must be in the corpus; span_years >= 1", {
  linked <- naep_like(function(rec) {
    rec$design$longitudinal_link <- list(
      linked_administration_id = "timss-intl-2023",
      span_years = 1L,
      cohort_label = "test cohort"
    )
    rec
  })
  expect_length(.design_invariants(linked, "timss-intl-2023"), 0L)

  missing <- .design_invariants(linked, character(0))
  expect_match(missing, "identity conflict", all = FALSE)

  bad_span <- naep_like(function(rec) {
    rec$design$longitudinal_link <- list(
      linked_administration_id = "timss-intl-2023",
      span_years = 0L
    )
    rec
  })
  expect_match(
    .design_invariants(bad_span, "timss-intl-2023"),
    "span_years must be >= 1",
    all = FALSE
  )
})

# --- amrr_design() -----------------------------------------------------------

test_that("amrr_design() returns the block or NULL", {
  rec <- naep_like()
  d <- amrr_design(rec)
  expect_identical(d$student_sampling, "multistage")
  expect_identical(d$plausible_values$count, 20L)
  expect_identical(d$weights$replicate$method, "JK1")

  expect_null(amrr_design(list(schema_version = "amr.assessment.v2")))

  reg <- fixture_registry()
  md <- get_metadata("IN", system = "wida-access", year = 2025, registry = reg)
  expect_null(amrr_design(md[[1]]))
})

# --- schema + corpus via validate_registry -----------------------------------

test_that("NAEP-shaped and TIMSS-shaped draft records validate", {
  skip_if_not_installed("jsonvalidate")
  tmp <- local_copied_registry()

  write_sidecar(
    tmp,
    "metadata/US/naep/naep-us-2015.json",
    naep_like(function(rec) {
      rec$content_areas <- list(list(
        id = "MATHEMATICS",
        vertical_scale = FALSE,
        enrollment = list(
          intended_enrollment_grade = "fixed",
          enrolled_grades_tested = list("4", "8")
        )
      ))
      rec
    })
  )
  write_sidecar(
    tmp,
    "metadata/INTL/timss/timss-intl-2019.json",
    timss_like(function(rec) {
      rec$content_areas <- list(list(
        id = "MATHEMATICS",
        vertical_scale = FALSE,
        enrollment = list(
          intended_enrollment_grade = "fixed",
          enrolled_grades_tested = list("4", "8")
        )
      ))
      rec
    })
  )

  r <- suppressWarnings(validate_registry(tmp, quiet = TRUE, error = FALSE))
  expect_equal(r$n_errors, 0L)
})

test_that("D3.6 unknown linked_administration_id fails validate_registry", {
  skip_if_not_installed("jsonvalidate")
  r <- mutate_v2_fixture(function(rec) {
    rec$design <- list(
      student_sampling = "census",
      longitudinal_link = list(
        linked_administration_id = "does-not-exist",
        span_years = 1L
      )
    )
    rec
  })
  expect_match(
    unlist(r$results),
    "identity conflict",
    all = FALSE
  )
})

test_that("D3.6 linked_administration_id present in the corpus validates", {
  skip_if_not_installed("jsonvalidate")
  r <- mutate_v2_fixture(function(rec) {
    rec$design <- list(
      student_sampling = "census",
      longitudinal_link = list(
        linked_administration_id = "wida-access-in-2025",
        span_years = 1L
      )
    )
    rec
  })
  expect_equal(r$n_errors, 0L)
})

test_that("schema rejects an undeclared property on design", {
  skip_if_not_installed("jsonvalidate")
  tmp <- local_copied_registry()
  rec <- naep_like(function(r) {
    r$content_areas <- list(list(
      id = "MATHEMATICS",
      vertical_scale = FALSE,
      enrollment = list(
        intended_enrollment_grade = "fixed",
        enrolled_grades_tested = list("4")
      )
    ))
    r$design$not_a_field <- "nope"
    r
  })
  write_sidecar(tmp, "metadata/US/naep/naep-us-2015.json", rec)
  r <- suppressWarnings(validate_registry(tmp, quiet = TRUE, error = FALSE))
  expect_gt(r$n_errors, 0L)
  expect_match(unlist(r$results), "additional", all = FALSE)
})
