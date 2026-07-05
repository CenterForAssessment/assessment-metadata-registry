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
md  <- amrr::get_metadata("IN", system = "wida-access", year = 2024, registry = ".")
ref <- amrr::amrr_registry_ref(md)   # the commit SHA to record with your run
```

See **Validate locally** and **Consume from R** below for the full workflow, and
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
- **Governance:** every record carries `status` (draft/reviewed/verified/deprecated),
  `source_confidence`, and `provenance`. Non-draft claims require a `source_citation`.

## Validate locally

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

## Consume from R

Install `amrr` from the monorepo, point it at a registry checkout, and read records. The
merged `achievement_targets` are re-attached from the accountability record at read time.

```r
# install.packages("r-pkg/amrr", repos = NULL, type = "source")  # or devtools::load_all
md <- amrr::get_metadata("IN", system = "wida-access", year = 2024,
                         registry = ".")          # a registry checkout
amrr::amrr_registry_ref(md)                        # commit SHA to pin the run
amrr::amrr_targets(md[[1]], "ELP_COMPOSITE")       # exit target, merged from accountability
```

## Status

- Tier A (canonical): `amr.assessment_system.v1` + `amr.accountability_system.v1`
  schemas; **48 records across 3 jurisdictions** — Indiana (ILEARN, WIDA-ACCESS, and its
  accountability system) plus demonstration jurisdictions SC and SD. Records are
  `status: draft` (scaffold values) pending review.
- Tier B (derived): `amrr::build_registry()` → index, changelog, per-jurisdiction bundles,
  SQLite, SHA-stamped manifest; published to Pages by CI.
- Tier C (consume): `r-pkg/amrr` — `get_metadata()` with SHA pinning and target re-merge;
  and a Quarto **catalog** (`site/`) that renders the derived JSON for humans (ADR-007).

See `wiki/decisions/000-registry-architecture.md` for the architecture and roadmap.
