---
title: "Pattern: Derivation Pipeline (Tier B)"
type: pattern
created: 2026-07-02
updated: 2026-07-02
status: active
curated: true
sources:
  - r-pkg/amrr/R/build.R
  - schemas/sql/amr-registry.v1.sql
  - wiki/decisions/000-registry-architecture.md
  - wiki/decisions/004-tooling-language.md
tags: [derivation, build, index, changelog, sqlite, static-bundles, provenance]
---

# Pattern: Derivation Pipeline (Tier B)

Implements ADR-000 D6 (JSON canonical, everything else derived). `amrr::build_registry()`
reads every authored sidecar under `metadata/**` and regenerates the disposable query layer
under `build/` (git-ignored). Nothing here is authored; correctness lives in Tier A.
(The tooling is R, and lives in the `amrr` package — ADR-004.)

## Inputs and outputs

```
metadata/**/*.json   (Tier A, canonical)
        |  amrr::build_registry()
        v
build/manifest.json          provenance: git SHA + built_at + schema + per-file sha256
build/index.json             flat: one row per jurisdiction x system x year x content_area
build/changelog.json         per (jurisdiction, system) year-over-year diffs
build/dist/<JUR>.json         per-jurisdiction bundle  (amrr::get_metadata unit)
build/dist/<JUR>/<sys>.json   per-system bundle
build/tables/*.json          derived cross-cutting views (vendor-by-year, vertical-scale)
build/registry.sqlite        self-contained SQLite projection (amr.registry.v1)
```

## The reproducibility pin (ADR-000 D5)

Every emitted bundle carries a `_registry` block: `{schema_version, git_sha, dirty,
built_at}`. On CI the working tree is clean, so `git_sha` is the exact commit and `dirty`
is `false` — a publishable pin. A local build with uncommitted changes is stamped
`dirty: true` and flagged "not publishable", so an unpinnable artifact is never mistaken
for a released one. A consumer records the `git_sha` it fetched; to reproduce, fetch the
bundle published from that SHA.

## Determinism

All rows are sorted by stable keys and JSON is written deterministically, so — modulo the
`_registry` timestamp — the diff of `build/` is fully explainable by the change to
`metadata/`. This is what lets CI treat regeneration as a gate. The R build is *semantically*
identical to the prior Python build (parity verified during the port; see ADR-004); byte
formatting is not load-bearing because consumers pin the git SHA, not a content hash.

## SQLite

`build.R` writes `build/registry.sqlite` directly via `RSQLite`/`DBI`, executing the
`schemas/sql/amr-registry.v1.sql` DDL then inserting the projection. (The former Python
build used a temp-dir byte-copy to sidestep FUSE journal locking; the R build does not need
that on the CI/native filesystem.)

## Publishing

`.github/workflows/build-publish.yml` runs validate -> build -> deploy `build/` to GitHub
Pages on merge to `main`. The static bundles become the canonical fetch target for R
consumption (ADR-000 D7); the SQLite/`index.json` back a future read-only API.

## Extending

- New derived view: add a `build_*` function returning sorted rows, write it under
  `build/tables/`, and it is automatically digested into the manifest.
- Accountability records (ADR-002): add their projection tables to the DDL and a loader
  branch; the changelog gains accountability-field diffs.
