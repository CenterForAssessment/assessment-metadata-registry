# amrr — Assessment Metadata Registry Client

<!-- badges: start -->
[![R-CMD-check](https://github.com/CenterForAssessment/assessment-metadata-registry/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/CenterForAssessment/assessment-metadata-registry/actions/workflows/R-CMD-check.yml)
<!-- badges: end -->

`amrr` is the R interface to the [**Assessment Metadata
Registry**](https://github.com/CenterForAssessment/assessment-metadata-registry) — a
version-controlled catalog of U.S. state assessment- and accountability-system metadata
(identities, vendors, scales, achievement levels, cutscores, comparability caveats, and
accountability targets). The canonical source of truth is a set of self-contained **annual
JSON sidecars**; `amrr` reads them into R, one `jurisdiction × system × year` at a time.

The package lives inside the registry monorepo (`r-pkg/amrr/`) and plays two roles:

- **Consume** (the common case) — `get_metadata()` and accessors read the registry for
  analysis. Needs only **`jsonlite`**.
- **Maintain** (registry tooling) — `validate_registry()` and `build_registry()` gate and
  derive the registry. Their heavier dependencies are **`Suggests`**, so consumers never pay
  for them.

## Installation

```r
# From a local checkout of the registry monorepo:
pkgload::load_all("r-pkg/amrr")                       # development
# install.packages("r-pkg/amrr", repos = NULL, type = "source")   # or R CMD INSTALL r-pkg/amrr

# Or straight from GitHub (the package is in a subdirectory):
remotes::install_github("CenterForAssessment/assessment-metadata-registry",
                        subdir = "r-pkg/amrr")
```

A `get_metadata()` consumer needs only `jsonlite`. To *build* or *validate* the registry,
also install the `Suggests`: `jsonvalidate`, `DBI`, `RSQLite`, `digest`.

## Consume

```r
library(amrr)

# Read one jurisdiction/system/year from a registry checkout.
md <- get_metadata("IN", system = "wida-access", year = 2024,
                   registry = "~/GitHub/CenterForAssessment/assessment-metadata-registry")

md                      # an `amrr_metadata` object (a list of records; has a print method)
rec <- md[[1]]          # the first matching record
```

`get_metadata(jurisdiction, system = NULL, year = NULL, registry = NULL, ref = NULL,
attach_targets = TRUE)` returns an `amrr_metadata` list of assessment records. Omit `system`
or `year` to get everything for the jurisdiction.

**Locating the registry.** The `registry` argument points at a checkout (the directory
containing `metadata/`). If omitted, `amrr` falls back to `option("amrr.registry")` and then
the `AMRR_REGISTRY` environment variable:

```r
options(amrr.registry = "~/GitHub/CenterForAssessment/assessment-metadata-registry")
md <- get_metadata("IN", "ilearn", 2024)
```

**Accessors** pull fields out of a record (`content_area` is optional and filters where it
applies):

```r
amrr_vendor(rec)                               # administration vendor
amrr_cutscores(rec, "ELP_COMPOSITE")           # cutscores (all content areas, or one)
amrr_achievement_levels(rec, "ELP_COMPOSITE")  # level labels + proficient mask
amrr_comparability(rec)                        # scale-transition / COVID-gap caveats
amrr_targets(rec, "ELP_COMPOSITE")             # accountability targets, re-merged (see below)
```

**Merged targets.** Accountability achievement targets are authored in *separate*
accountability records (ADR-002), but many consumers (e.g. SGPc) expect them attached to the
assessment record. With `attach_targets = TRUE` (the default), `get_metadata()` resolves and
merges them onto each record under `achievement_targets`, keyed by content area.

## Reproducibility (pin by commit SHA)

The registry's history axis is Git; a **commit SHA is the reproducibility pin**. Every
`amrr_metadata` object carries the checkout's SHA — record it with your analysis so the exact
bytes can be reconstructed later.

```r
ref <- amrr_registry_ref(md)   # the registry commit SHA this run resolved against
```

Pass `ref =` to `get_metadata()` to assert an expected SHA; if the checkout's `HEAD` differs
you get a warning (check out that ref yourself to guarantee the bytes).

## Maintain (registry tooling)

These regenerate and gate the registry. They read the canonical sidecars directly and are the
same functions CI runs.

```r
# Tier A gate — validate every sidecar against its JSON Schema + registry invariants.
validate_registry(".")                 # errors (non-zero exit) if any file fails

# Tier B derivation — regenerate the disposable query layer under build/.
build_registry(".", out = "build")     # index, changelog, per-record bundles, SQLite, manifest
```

`build_registry()` and `validate_registry()` require the `Suggests` packages and raise a clear
error if they are missing. See the registry repo's `Makefile` (`make validate | build`) and
`wiki/decisions/004-tooling-language.md` for how they fit the toolchain.

## What this package is *not*

It is not the source of truth. The authored JSON sidecars under `metadata/` are canonical;
everything `amrr` returns or builds is derived from them. Never hand-edit derived artifacts —
regenerate them with `build_registry()`.

## License

MIT © Center for Assessment. See `LICENSE`. Part of the
[assessment-metadata-registry](https://github.com/CenterForAssessment/assessment-metadata-registry).
