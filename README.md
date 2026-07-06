# assessment-metadata-registry

> The canonical, versioned home for U.S. state large-scale **assessment metadata** —
> a durable public data product, not project-specific helper code.

**What it is.** A general, version-controlled registry of state assessment metadata:
assessment-system identity, vendors, scales, achievement levels, cutscores, comparability
caveats, accountability targets, and Ed-Fi descriptors. The canonical source of truth is a
set of self-contained **annual JSON sidecars**; every other artifact — query indexes,
changelogs, static bundles, the R package, the Pages catalog — is *derived* from them and
disposable.

**Why it exists.** This metadata used to live as a single embedded R object that could not
be queried across states and lost history whenever a state re-established performance
levels. The registry gives it a **canonical, versioned home**: **Git is the history axis and
a commit SHA is the reproducibility pin**, so any past analysis is exactly reconstructable.
It is a **general registry with SGPc as its first consumer** — the guiding rule is
**federation, not duplication: a fact lives in exactly one place**, and consumers point at
it rather than fork it.

**How it fits together (three tiers):**

| Tier | What | Where |
|------|------|-------|
| **A — Authored** (canonical) | Hand-authored annual JSON sidecars | `metadata/<jur>/<system>/*.json`, gated by `schemas/` |
| **B — Derived** (generated) | SQLite, index, changelog, SHA-stamped bundles | built by `amrr::build_registry()`; published to Pages by CI |
| **C — Consumed** | `amrr` R package + a human-readable **catalog** | `r-pkg/amrr/`, `site/` |

The whole toolchain is R (see `wiki/decisions/004-tooling-language.md`).

**Browse the catalog:** <https://centerforassessment.github.io/assessment-metadata-registry/> —
a Quarto site that renders every record human-readably (a searchable catalog, per-record
Display / Explore-JSON / Raw views, a spec viewer, and a changelog). The machine-readable JSON
(`index.json`, `dist/**`, …) is published at the same URLs for programmatic consumers (ADR-007).

**Quick start:**

```bash
# Validate the canonical sidecars locally (expects 48 files, 0 errors)
make validate            # or: Rscript -e 'amrr::validate_registry(".")'
```
```r
# Consume from R — pin the exact registry bytes by commit SHA
md  <- amrr::get_metadata("IN", system = "ilearn", year = 2024, registry = ".")
ref <- amrr::amrr_registry_ref(md)   # the commit SHA to record with your run
```

See **Basic usage** and **Validate & build locally** below for the full workflow, and
`wiki/decisions/000-registry-architecture.md` for the architecture and roadmap.

## Layout

```
schemas/      JSON Schemas for authored records (Tier A contract)
metadata/     Canonical annual sidecars: <jurisdiction>/<system>/<system>-<jur>-<year>.json
tools/        archive/ = historical one-time seed scripts (live tooling is amrr::*_registry)
r-pkg/amrr/   R package: get_metadata() consumer + build_registry()/validate_registry() tooling
site/         Quarto catalog (Tier C presentation): renders the derived JSON for humans
wiki/         LLM wiki: decisions (ADRs), patterns, sources, analyses
Makefile      Local dogfooding loop: make validate | build | check | test | all | site
AGENTS.md     Operating manual (read first); CLAUDE.md imports it
```

## Key ideas

- **Unit of record:** one file = one `jurisdiction × assessment_system × year`. The file
  *is* the year, so history coexists instead of overwriting.
- **Versioning:** Git is the history axis; a recorded **commit SHA** is the reproducibility
  pin. Consumers record the SHA they resolved against, so any past analysis is exactly
  reconstructable.
- **Enrollment-grade model (v2):** each content area declares whether its instrument targets
  one enrolled grade (`fixed`) or many (`variable`); cutscores and scale bounds are always
  keyed by *enrolled grade*, never by instrument/form name (the axis rule, ADR-009).
- **Governance:** every record carries `status` (draft/reviewed/verified/deprecated),
  `source_confidence`, and `provenance`. Non-draft claims require a `source_citation`;
  proficiency is stored as a single `proficient_from` label, not a positional mask (ADR-010).

## Validate & build locally

`make validate` runs the Tier A gate (schema via `jsonvalidate` + registry invariants);
`make build` regenerates the derived layer after validating. Both are `Rscript` under the
hood — the only requirement is R plus the tooling packages (`make setup` installs them). CI
runs the same validation on every PR.

```bash
make setup               # once: install the R tooling + site packages
make validate            # or: Rscript -e 'amrr::validate_registry(".")'
make build               # validate, then derive Tier B into build/
make site                # render the human-readable catalog into site/_site/
```

## Basic usage

Point `amrr` at a registry checkout and read a cell (`jurisdiction × system × year`).
Accountability `achievement_targets` are re-merged onto the assessment record at read time,
and the resolved **commit SHA** pins the exact bytes your analysis used.

```r
# install.packages("r-pkg/amrr", repos = NULL, type = "source")   # or devtools::load_all("r-pkg/amrr")
library(amrr)

md  <- get_metadata("IN", system = "ilearn", year = 2024, registry = ".")
rec <- md[[1]]
amrr_registry_ref(md)                       # commit SHA — record this with your run

amrr_cutscores(rec, "ELA")                  # enrolled grade -> level lower bounds
amrr_achievement_levels(rec, "ELA")$proficient_from   # "At Proficiency" (ADR-010)
amrr_enrollment(rec, "ELA")                 # $intended_enrollment_grade "fixed" + enrolled grades
amrr_targets(rec, "ELA")                    # proficiency target, merged from accountability
```

**Reproducible remote (pin by SHA).** `registry` also accepts a **GitHub repo** —
`get_metadata()` reads the canonical sidecars straight from GitHub **pinned to an exact
commit SHA** (via the git-trees + raw-content APIs), no checkout required. `ref` (a SHA,
branch, or tag) is resolved to a concrete commit SHA and recorded as the pin, so the read
is byte-for-byte reconstructable.

```r
repo <- "github://CenterForAssessment/assessment-metadata-registry"
md   <- get_metadata("IN", system = "ilearn", year = 2024, registry = repo, ref = "b824b20")
amrr_registry_ref(md)                       # the resolved 40-hex SHA — the reproducibility pin
```

For quick, non-reproducible access there's also a **derived-layer URL** — point `registry`
at the published catalog and it fetches `…/dist/<jurisdiction>.json` over HTTP. Convenient,
but it serves the *latest* build only; use the `github://` form (or a checkout at a SHA)
when you need a reproducible pin.

```r
pages <- "https://centerforassessment.github.io/assessment-metadata-registry"
get_metadata("IN", system = "ilearn", year = 2024, registry = pages)
```

Omit `year` to get every year for a system as an `amrr_metadata` set, and project it into the
compact **assessment-config** authoring shape — reusable level schemes, tests, a grade→test
map, and unified cuts (ADR-010). `read_config()` expands it back into records.

```r
cfg <- as_config(get_metadata("IN", system = "ilearn", registry = "."))
names(cfg$level_schemes)                    # "general_4" — one scheme, shared by ELA + Math
cfg$tests$ela$intended_enrollment_grade     # "fixed" (the axis a bare grade list can't carry)
back <- read_config(cfg)                     # -> an amr.assessment.v2 record
```

Browse the same projection rendered for humans on the
[**Config view**](https://centerforassessment.github.io/assessment-metadata-registry/config-view.html)
page of the catalog.

## Status

- **Tier A (canonical):** `amr.assessment.v2` + `amr.accountability.v2` schemas (the v1
  schemas remain accepted during the migration window). **48 records across 3
  jurisdictions** — Indiana (ILEARN, WIDA-ACCESS, and its accountability system) plus
  demonstration jurisdictions SC and SD, all migrated to v2. Records are `status: draft`
  (scaffold values) pending review. v2 adds the enrollment-grade model (`fixed`/`variable`
  + `enrolled_grades_tested`), enrolled-grade-keyed `scale_bounds`, `proficient_from`
  benchmarks, an end-of-course `"eoc"` cut key, and type-discriminated measurement
  extensions (ADR-009 / ADR-010).
- **Tier B (derived):** `amrr::build_registry()` → index, changelog, per-jurisdiction
  bundles, SQLite, the compact `config/` projection, and a SHA-stamped manifest; published
  to Pages by CI.
- **Tier C (consume):** `r-pkg/amrr` 0.5.0 — `get_metadata()` with SHA pinning and target
  re-merge, v2 accessors, and the `as_config()` / `read_config()` config view; reads from a
  local checkout, a **reproducible `github://` remote** pinned by commit SHA (ADR-011), or a
  derived-layer URL (latest); plus a Quarto **catalog** (`site/`) with a **Config view** page
  (ADR-007 / ADR-010).

See `wiki/decisions/000-registry-architecture.md` for the architecture and roadmap.
