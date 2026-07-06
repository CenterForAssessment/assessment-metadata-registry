---
title: "ADR-004: Single-Language R Tooling"
type: decision
created: 2026-07-02
updated: 2026-07-06
status: accepted
deciders: Damian Betebenner
curated: true
sources:
  - r-pkg/amrr/R/validate.R
  - r-pkg/amrr/R/build.R
  - r-pkg/amrr/R/tooling-internal.R
  - schemas/amr.assessment_system.v1.schema.json
  - wiki/decisions/000-registry-architecture.md
  - wiki/patterns/development-harness.md
tags: [tooling, language, R, amrr, jsonvalidate, sqlite, derivation, pipeline]
---

# ADR-004: Single-Language R Tooling

**Status:** Accepted (sign-off Damian Betebenner, 2026-07-06)

## Context

The registry launched two-language: **Python** for the Tier A→B derivation/validation
pipeline (`tools/validate.py`, `tools/build.py`) and **R** for the Tier C consumption
package (`amrr`). ADR-000 recorded the monorepo and the tier split but never recorded *why*
the tooling was Python — an unstated gap.

CenterForAssessment is an R shop (SGP, SGPc, `amrr`). A Python pipeline is a maintenance
outlier: every contributor must context-switch, CI carries two toolchains, and local setup
hit real friction (PEP 668 externally-managed-Python broke a plain `pip install`). The two
scripts are small and mechanical (165 + 381 LOC) and depend on nothing Python-specific that
R cannot match.

## Decision

Port the derivation/validation tooling to **R** and drop the Python toolchain.

- **Placement:** the tooling lives **inside the `amrr` package** as exported functions —
  `amrr::validate_registry(registry)` and `amrr::build_registry(registry, out)` — mirroring
  `get_metadata()`'s `registry =` argument. All the registry's R lives in one package with
  one test suite and one `R CMD check`. The producer/consumer separation (ADR-000) is
  preserved **functionally, by dependency scoping**: the build/validate-only packages
  (`jsonvalidate`, `DBI`, `RSQLite`, `digest`) are **`Suggests`** with `requireNamespace()`
  runtime checks, so a consumer of `get_metadata()` still installs only `jsonlite` (`Imports`).
  *(Superseded the initial choice of standalone `tools/*.R` scripts: consolidating into
  `amrr` is tidier, DRYs the shared Tier A internals, and the "consumers carry heavy deps"
  objection dissolves once those deps are `Suggests`.)*
- **Validation:** `jsonvalidate` (ajv engine) validates the JSON Schemas. They declare Draft
  2020-12 but use only draft-07-compatible vocabulary (`const`, `if`/`then`,
  `additionalProperties`, `required` — no `prefixItems`/`unevaluated*`/`$dynamicRef`), so
  `validate.R` normalizes the `$schema` line to draft-07 at load. The custom invariants
  (path/identity, cutscore-count-vs-labels, monotonicity, cross-link, provenance) are ported
  directly. **The `.schema.json` files remain the executable Tier A contract.**
- **Build:** `jsonlite` (JSON I/O), `DBI` + `RSQLite` (the SQLite projection from the
  existing DDL), `digest` (per-file sha256), and `system2("git")` (the SHA pin). Reproduces
  every `build/` artifact and its `_registry` provenance stamp. Reuses `amrr`'s existing
  internals (`is_assessment_record`, `as_logical_flag`, `amrr_registry_root`,
  `amrr_git_sha_of`), so the shared Tier A semantics live in exactly one place.
- **One-time scripts** (`migrate_sgpc_sidecars.py`, `split_accountability.py`,
  `seed_demo.py`) already did their job; they are moved to `tools/archive/` as historical
  Python provenance, not ported.

## Consequences

- **One toolchain.** Contributors, CI, and the local `Makefile` need only R (already
  required for `amrr`). Simpler dogfooding; no PEP 668 friction.
- **Semantic parity verified (not byte parity).** The port was checked twice: `build.R` vs
  the Python build (all 16 JSON artifacts + 12 SQLite tables identical; 10 changelog events,
  45 index rows, 45 targets; validators agree file-for-file), then `amrr::build_registry`
  vs. that R build (0 artifacts diverged) when the logic moved into the package. Byte parity
  is intentionally *not* a goal — `build/` is derived, gitignored, republished each merge,
  consumers pin the **git SHA**, and `amrr` reads raw sidecars — so `jsonlite`'s formatting
  differing from Python `json.dumps` is immaterial. A bundled fixture registry
  (`inst/extdata/registry`, with schemas + DDL) makes the tooling tests self-contained.
- **`amrr`'s `R-CMD-check` and the `validate`/`build-publish` jobs gain a `jsonvalidate` →
  `V8`/libv8 system dependency** (installed by `setup-r-dependencies`, cached). Because
  `validate` runs on every PR (required check), the gate is heavier than the former ~8s
  Python step. `V8` etc. are `Suggests`, so consumers installing `amrr` for `get_metadata()`
  are unaffected.
- **No cross-language duplication.** The shared Tier A semantics now have a single home in
  `amrr`, used by both `get_metadata()` and `build_registry()`.

## Alternatives considered

- **Keep Python.** Rejected: maintenance outlier for an R shop; the motivating friction stands.
- **Standalone `tools/*.R` scripts** (the initial form of this ADR). Superseded: consolidating
  into `amrr` is tidier, gives the tooling a test/`R CMD check` harness, and DRYs the shared
  internals. The producer/consumer separation is kept via `Suggests`, not file layout.
- **Sibling R builder package (`amrrbuild`).** Not chosen: more plumbing (cross-package
  exports) than exported functions in `amrr` with `Suggests`-scoped deps.
- **Hand-port the schema checks to pure R** (drop `jsonvalidate`/`V8`). Rejected by default:
  it demotes the `.schema.json` from executable contract to documentation. Kept as the
  fallback if the `V8`/libv8 CI cost proves painful.

## Revisit trigger

If the `V8`/libv8 CI dependency becomes a burden, reconsider the pure-R validator fallback
(schema constraints as explicit R checks, at the cost of the executable `.schema.json`).
