---
title: "Connection: SGPc ↔ Registry Consumption Contract"
type: connection
created: 2026-07-02
updated: 2026-07-02
status: active
curated: true
sources:
  - r-pkg/amrr/R/get_metadata.R
  - r-pkg/amrr/R/targets.R
  - SGPc-rpkg/SGPc/R/metadata-consume.R
  - SGPc-rpkg/SGPc/R/metadata.R
  - wiki/decisions/000-registry-architecture.md
  - wiki/decisions/002-accountability-system-record.md
tags: [sgpc, consumption, resolver, contract, reproducibility]
---

# Connection: SGPc ↔ Registry Consumption Contract

The boundary between the registry (source of truth) and SGPc (first consumer). The
registry owns the facts; SGPc points to them via the `amrr` package.

## The `amrr` surface SGPc consumes

```r
md <- amrr::get_metadata("IN", system = "wida-access", year = 2024,
                         registry = <checkout>, ref = <sha>, attach_targets = TRUE)
amrr::amrr_registry_ref(md)     # commit SHA to stamp into the SGPc run
amrr::amrr_cutscores(md[[1]], "ELP_COMPOSITE")
amrr::amrr_targets(md[[1]], "ELP_COMPOSITE")   # exit target, re-merged from accountability
```

`get_metadata()` returns assessment records with accountability targets **re-merged**
under `achievement_targets` (ADR-002), so SGPc sees the shape it already expects even
though targets are authored separately.

## The three SGPc-side changes (additive)

1. **Resolver source.** Add `registry` to `resolve_sgpc_metadata()` precedence:
   `arg > store > registry > embedded`. The `registry` source calls
   `amrr::get_metadata()`. See `SGPc-rpkg/SGPc/R/metadata.R` (the resolver builds an
   ordered named `sources` list; inserting one entry before `embedded` is additive).
2. **Schema alias.** SGPc keys on `schema_version` with `identical()` in two places
   (`sgpc_assessment_metadata_schema_version()` use-sites and `is_sgpc_metadata_record`).
   Accept both `amr.assessment_system.v1` and the legacy
   `sgpc.assessment_metadata.v0.1` during migration.
3. **Provenance in outputs.** Extend the SGPc manifest/output bundle metadata block with
   `registry_ref` (SHA), `registry_schema_version`, and a per-cell content digest, so a
   run records exactly which registry bytes it used (ADR-000 D5).

## Reproducibility handshake

The registry is pinned by commit SHA. SGPc records `amrr_registry_ref(md)` in its output;
to reproduce, resolve the registry at that SHA and re-read. Because R consumption reads
committed Tier A sidecars, the SHA fully determines the bytes — no live service on the
critical path. This works from either a **local/submoduled checkout** (`registry = <path>`,
pinned by checking out the SHA) or, since `amrr` 0.5.0, a **reproducible remote**
(`registry = "github://CenterForAssessment/assessment-metadata-registry"`, `ref = <SHA>`),
which fetches the canonical sidecars straight from GitHub at that SHA — no checkout needed
(ADR-011).

## Invariants SGPc can rely on

- One record per `jurisdiction × system × year`; identity is invariant.
- `achievement_targets` (when attached) is keyed by content area; each has
  `per_grade_scale_score`, `semantics`, `basis`, `comparison`.
- A `proficiency_boundary` target's scale scores are derived from the same record's
  cutscores + proficient mask (the boundary entering the first proficient level).

## Resolved: remote (non-checkout) pinning — ADR-011

**Resolved (2026-07-06, `amrr` 0.5.0).** Reproducible remote pinning reads the **canonical
Tier A sidecars** raw-by-SHA from GitHub (git-trees + raw content, both addressed by the
commit SHA), *not* the git-ignored derived bundle. `get_metadata()` accepts
`registry = "github://owner/repo"` + `ref` (resolved to a concrete SHA and recorded as
`amrr_registry_ref()`). SGPc may now consume the registry either as a local/submoduled
checkout **or** as a `github://` remote pinned by `ref`, both byte-reproducible. The
derived-URL mode (`amrr` 0.4.0) remains available for convenience but serves the *latest*
build only — use the checkout or `github://` form for reproducible runs. See ADR-011.
