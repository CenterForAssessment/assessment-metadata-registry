---
title: "ADR-004: Single-Language R Tooling"
type: decision
created: 2026-07-02
updated: 2026-07-02
status: proposed
deciders: Damian Betebenner
curated: true
sources:
  - tools/validate.R
  - tools/build.R
  - tools/_shared.R
  - tools/parity_check.R
  - schemas/amr.assessment_system.v1.schema.json
  - wiki/decisions/000-registry-architecture.md
  - wiki/patterns/development-harness.md
tags: [tooling, language, R, jsonvalidate, sqlite, derivation, pipeline]
---

# ADR-004: Single-Language R Tooling

**Status:** Proposed

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

- **Placement:** standalone `tools/*.R` scripts invoked by `Rscript` (`validate.R`,
  `build.R`, shared `_shared.R`), mirroring the former `tools/` layout. The tooling stays
  **separate from `amrr`** — `build`/`amrr` are parallel Tier A consumers, not a pipeline —
  preserving ADR-000's producer/consumer split. It is *not* folded into `amrr` (that would
  force analysis consumers to carry `RSQLite`/`jsonvalidate`/`V8` they don't need).
- **Validation:** `jsonvalidate` (ajv engine) validates the JSON Schemas. They declare Draft
  2020-12 but use only draft-07-compatible vocabulary (`const`, `if`/`then`,
  `additionalProperties`, `required` — no `prefixItems`/`unevaluated*`/`$dynamicRef`), so
  `validate.R` normalizes the `$schema` line to draft-07 at load. The custom invariants
  (path/identity, cutscore-count-vs-labels, monotonicity, cross-link, provenance) are ported
  directly. **The `.schema.json` files remain the executable Tier A contract.**
- **Build:** `jsonlite` (JSON I/O), `DBI` + `RSQLite` (the SQLite projection from the
  existing DDL), `digest` (per-file sha256), and `system2("git")` (the SHA pin). Reproduces
  every `build/` artifact and its `_registry` provenance stamp.
- **One-time scripts** (`migrate_sgpc_sidecars.py`, `split_accountability.py`,
  `seed_demo.py`) already did their job; they are moved to `tools/archive/` as historical
  Python provenance, not ported.

## Consequences

- **One toolchain.** Contributors, CI, and the local `Makefile` need only R (already
  required for `amrr`). Simpler dogfooding; no PEP 668 friction.
- **Semantic parity verified (not byte parity).** `tools/parity_check.R` compared the R and
  Python builds on the 48-record corpus: all 16 JSON artifacts and all 12 SQLite tables are
  identical (10 changelog events, 45 index rows, 45 targets), and the two validators agree
  file-for-file. Byte parity is intentionally *not* a goal — `build/` is derived, gitignored,
  republished each merge, consumers pin the **git SHA**, and `amrr` reads raw sidecars — so
  `jsonlite`'s formatting differing from Python `json.dumps` is immaterial.
- **CI gains a `jsonvalidate` → `V8`/libv8 system dependency**, and because `validate` runs
  on every PR (required check), the gate is heavier than the former ~8s Python step —
  mitigated by `r-lib/actions/setup-r-dependencies` caching.
- **Small R↔R duplication** of Tier A primitives remains between `tools/_shared.R` and
  `amrr` (flag coercion, cross-link key, git SHA). It is minor and now single-language;
  unifying it into a shared internal helper is a possible later step.

## Alternatives considered

- **Keep Python.** Rejected: maintenance outlier for an R shop; the motivating friction stands.
- **Fold the tooling into `amrr`.** Rejected: mixes the Tier B producer into the Tier C
  consumer (against ADR-000) and imposes build-only deps on analysis consumers.
- **Sibling R builder package (`amrrbuild`).** Deferred: best-tested/DRY but more plumbing;
  revisit if the shared-primitive duplication grows.
- **Hand-port the schema checks to pure R** (drop `jsonvalidate`/`V8`). Rejected by default:
  it demotes the `.schema.json` from executable contract to documentation. Kept as the
  fallback if the `V8`/libv8 CI cost proves painful.

## Revisit trigger

If the `V8`/libv8 CI dependency becomes a burden, or the `tools/_shared.R`↔`amrr`
duplication grows, reconsider either the pure-R validator or a shared internal package.
