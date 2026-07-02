---
title: "Pattern: Derivation Pipeline (Tier B)"
type: pattern
created: 2026-07-02
updated: 2026-07-02
status: active
curated: true
sources:
  - tools/build.py
  - schemas/sql/amr-registry.v1.sql
  - wiki/decisions/000-registry-architecture.md
tags: [derivation, build, index, changelog, sqlite, static-bundles, provenance]
---

# Pattern: Derivation Pipeline (Tier B)

Implements ADR-000 D6 (JSON canonical, everything else derived). `tools/build.py` reads
every authored sidecar under `metadata/**` and regenerates the disposable query layer
under `build/` (git-ignored). Nothing here is authored; correctness lives in Tier A.

## Inputs and outputs

```
metadata/**/*.json   (Tier A, canonical)
        |  tools/build.py
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

All rows are sorted by stable keys and JSON is written with sorted, indented output, so
the build is byte-deterministic for a given input: the diff of `build/` is fully
explainable by the change to `metadata/`. This is what lets CI treat regeneration as a
gate.

## SQLite on restrictive mounts

`build.py` builds the SQLite file in a local temp dir and copies the finished bytes to the
destination. SQLite needs POSIX journal locking, which some mounts (FUSE) reject; the
byte-copy sidesteps it. On CI (normal filesystem) this is a no-op cost.

## Publishing

`.github/workflows/build-publish.yml` runs validate -> build -> deploy `build/` to GitHub
Pages on merge to `main`. The static bundles become the canonical fetch target for R
consumption (ADR-000 D7); the SQLite/`index.json` back a future read-only API.

## Extending

- New derived view: add a `build_*` function returning sorted rows, write it under
  `build/tables/`, and it is automatically digested into the manifest.
- Accountability records (ADR-002): add their projection tables to the DDL and a loader
  branch; the changelog gains accountability-field diffs.
