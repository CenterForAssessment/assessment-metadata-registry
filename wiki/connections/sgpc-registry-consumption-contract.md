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
to reproduce, check out the registry at that SHA and re-resolve. Because R consumption
reads committed Tier A sidecars, the SHA fully determines the bytes — no live service on
the critical path.

## Invariants SGPc can rely on

- One record per `jurisdiction × system × year`; identity is invariant.
- `achievement_targets` (when attached) is keyed by content area; each has
  `per_grade_scale_score`, `semantics`, `basis`, `comparison`.
- A `proficiency_boundary` target's scale scores are derived from the same record's
  cutscores + proficient mask (the boundary entering the first proficient level).

## Open item

Remote (non-checkout) pinning: raw-by-SHA needs the consumed artifact committed. v1 reads
a local checkout (fully SHA-pinnable); a published-bundle distribution model is a future
ADR. Until then SGPc consumes a local/submoduled registry checkout.
