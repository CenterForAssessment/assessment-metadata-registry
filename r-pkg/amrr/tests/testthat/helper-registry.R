# Shared test helper: the bundled fixture registry (inst/extdata/registry), a
# self-contained mini-registry with schemas + DDL. Skips when not installed.
fixture_registry <- function() {
  reg <- system.file("extdata", "registry", package = "amrr")
  testthat::skip_if(!nzchar(reg) || !dir.exists(file.path(reg, "schemas")),
                    "fixture registry (with schemas) not installed")
  reg
}
