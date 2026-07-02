# assessment-metadata-registry

> The canonical, versioned home for U.S. state large-scale **assessment metadata** —
> a durable public data product, not project-specific helper code.

**What it is.** A general, version-controlled registry of state assessment metadata:
assessment-system identity, vendors, scales, achievement levels, cutscores, comparability
caveats, Ed-Fi descriptors, and (forthcoming) accountability rules. The canonical source of
truth is a set of self-contained **annual JSON sidecars**; every other artifact — query
indexes, changelogs, static bundles, the R package — is *derived* from them and disposable.

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
| **B — Derived** (generated) | SQLite, index, changelog, SHA-stamped bundles | built by `tools/build.py`; published to Pages by CI |
| **C — Consumed** | `amrr` R package: `get_metadata()` with SHA pinning | `r-pkg/amrr/` |

**Quick start:**

```bash
# Validate the canonical sidecars locally (expects 48 files, 0 errors)
python3 tools/validate.py
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
tools/        Migration + validation tooling (Tier A gates)
r-pkg/amrr/   R consumption package: get_metadata(...) with SHA pinning
wiki/         LLM wiki: decisions (ADRs), patterns, sources, analyses
Makefile      Local dogfooding loop: make validate | build | check | test | all
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

`make validate` bootstraps a local venv (the tooling needs `jsonschema`) and runs the Tier A
gate; `make build` regenerates the derived layer after validating. CI runs the same
validation on every PR.

```bash
make validate            # or: python3 -m pip install -r tools/requirements.txt && python3 tools/validate.py
make build               # validate, then derive Tier B into build/
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
  schemas; Indiana seed corpus (ILEARN, WIDA-ACCESS, accountability). Records are
  `status: draft` (scaffold values) pending review.
- Tier B (derived): `tools/build.py` → index, changelog, per-jurisdiction bundles,
  SQLite, SHA-stamped manifest; published to Pages by CI.
- Tier C (consume): `r-pkg/amrr` — `get_metadata()` with SHA pinning and target re-merge.

See `wiki/decisions/000-registry-architecture.md` for the architecture and roadmap.
