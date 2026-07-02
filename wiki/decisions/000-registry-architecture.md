---
title: "ADR-000: Assessment Metadata Registry — Foundational Architecture"
type: decision
created: 2026-07-02
updated: 2026-07-02
status: proposed
deciders: Damian Betebenner (+ co-developer)
curated: true
scope:
  - assessment-metadata-registry
  - SGPc-rpkg (first consumer)
sources:
  - SGPc-rpkg/SGPc/R/metadata.R
  - SGPc-rpkg/SGPc/R/metadata-ingest.R
  - SGPc-rpkg/SGPc/R/metadata-consume.R
  - SGPc-rpkg/SGPc/R/data.R
  - SGPc-rpkg/SGPc/inst/sql/sgpc-metadata.v0.1.sql
  - SGPc-rpkg/SGPc/wiki/decisions/011-assessment-metadata-layer.md
  - SGPc-rpkg/SGPc/wiki/decisions/008-assessment-context-registry.md
  - SGPc-rpkg/SGPc/wiki/decisions/012-edfi-alignment.md
  - SGPc-wiki/wiki/patterns/vertical-development-harness.md
  - SGPcMetaData / legacy SGPstateData
tags: [architecture, metadata, registry, versioning, provenance, r-package, harness]
---

# ADR-000: Assessment Metadata Registry — Foundational Architecture

**Status:** Proposed
**Date:** 2026-07-02
**Deciders:** Damian Betebenner and co-developer (sign-off required before Phase 1)

> This is the founding decision for the `assessment-metadata-registry` repo. It sets the
> framing, the unit of record, the schema surface, the storage/derivation model, the
> versioning strategy, the R consumption path, and the development harness. Subsequent
> ADRs (schema details, API surface, scraping pipeline) refine within these bounds.

---

## Context

SGPc analyses depend on a large body of **assessment metadata**: assessment-system
identity, vendors, vertical-scale flags, achievement-level names, cutscores,
proficiency mappings, Ed-Fi descriptors, and comparability caveats. Historically this
lived in the SGP package as a single embedded R object, `SGPstateData[[state]]`. That
object had two structural defects, both already diagnosed in SGPc ADR-011:

1. **Not queryable across jurisdictions** — "which states used a vertical scale in
   grade 3–8 math?" could not be answered without loading and walking the whole object.
2. **History-losing** — when a state re-established performance levels, old values were
   edited or commented out; "what was the metadata in 2017?" became unanswerable. A
   single compressed `.Rdata` blob across all jurisdictions was also large and
   cumbersome to load.

SGPc already took the first abstraction step: it moved metadata into **self-contained
annual JSON sidecars** (`sgpc.assessment_metadata.v0.1`), one per
`jurisdiction × assessment_system × year`, with a three-tier layer around them
(authored sidecars → year-keyed SQLite projection + derived index/changelog → a
precedence resolver `resolve_sgpc_metadata()` reading `arg > store > embedded`). That
layer works and is in production use for Indiana (ILEARN summative, WIDA-ACCESS ELP).

The **next abstraction** is to lift the authored sidecars out of SGPc into their own
repository so the metadata becomes a **durable, versioned, public data product** that
SGPc consumes rather than embeds — and that other tools, states, and researchers can
consume too. This ADR defines that repository.

### Forces at play

- **Reproducibility.** SGPc analyses are re-run years later (audits, corrections,
  longitudinal comparisons). The metadata used by a given run must be recoverable
  exactly, even after the registry has been corrected or extended.
- **Two schema surfaces.** Real jurisdictions run *multiple* programs — e.g.
  Massachusetts has the MCAS general summative (grades 3–8 + high school) **and**
  WIDA-ACCESS for English language proficiency (grades K–12) — and the **accountability
  system** that consumes those assessments is a distinct object from the assessments
  themselves.
- **Size.** A monolithic all-jurisdictions R object is too large to load comfortably;
  consumers want to pull one jurisdiction at a time.
- **Authoring cost.** Metadata authoring mirrors data cleaning: prepared once, reused
  everywhere. The atomic authored unit should match the annual cadence at which states
  publish technical documentation.
- **Federation, not duplication.** A fact lives in exactly
  one place. The registry must be *the* source of truth for assessment metadata;
  SGPc must point to it, not fork it.

---

## Decision

Build a **general state-assessment metadata registry** whose canonical source of truth
is **version-controlled annual JSON sidecars**, with SGPc as the **first consumer** via
a co-located R package. Git itself provides the historical-version axis; a recorded
**commit SHA** is the reproducibility pin. Frame the design as `AssessmentMetaData`
(general) with SGPc-specific views layered on top — **not** `SGPcMetaData`.

The following sub-decisions were confirmed with the deciders on 2026-07-02.

### D1 — Product framing: general registry, SGPc first consumer

The core is a **general assessment metadata registry**. SGPc-specific concerns (SGP
configuration knots/boundaries, copula policy, analysis-run wiring) stay in SGPc and are
**out of scope** for the registry. The registry holds facts that are true about the
assessment and accountability systems independent of any one analysis. This keeps the
product valuable to states and researchers while serving SGPc now.

### D2 — Unit of record: `jurisdiction × system × year`, self-contained annual sidecar

Retain the SGPc Tier A unit: one self-contained JSON file describes exactly one
`(jurisdiction × assessment_system × year)`. Identity is invariant;
administration / program / content-areas / achievement-levels / cutscores are
year-resolved — the file *is* the year. `assessment_type` is **not** added to the key;
it is carried *inside* `assessment_system` (as today: `state-summative`,
`english-language-proficiency`, `alternate`, `science`, `end-of-course`, …), and the
`assessment_system.id` is the disambiguator (`ilearn`, `wida-access`). This is what lets
history coexist rather than overwrite (ADR-011's core property), and it matches the
annual cadence at which technical documentation is published.

Accountability records use the **same annual unit** (see D4).

### D3 — Schema namespace: rebrand to a neutral namespace, keep the SGPc alias

Rename the authored schema from `sgpc.assessment_metadata.v0.1` to a registry-neutral
namespace, proposed **`amr.assessment_system.v1`** (Assessment Metadata Registry), and
introduce a sibling **`amr.accountability_system.v1`**. The registry's validator accepts
the legacy `sgpc.assessment_metadata.v0.1` string as a recognized **alias** during
migration so existing SGPc sidecars validate unchanged, and a one-time migration stamps
them to `amr.*`. Schema version is tracked **separately from data version** (see D5):
the `amr.*.vN` string versions the *shape*; Git versions the *content*.

### D4 — Accountability metadata: a separate, cross-linked record type

Accountability-system metadata is authored as its **own record type**
(`amr.accountability_system.v1`), keyed to the same `jurisdiction × year`, that
**references** one or more assessment systems rather than nesting inside them. Rationale:
a state's accountability frame (participation rules, N-size, indicator weights, business
rules, proficiency/growth targets used for accountability, included assessments) is a
state-wide object that typically spans *multiple* assessments (MCAS + the science test +
WIDA-ACCESS all feed one accountability system). Nesting it inside a single assessment
sidecar would duplicate it and misrepresent the relationship. The link is by
`assessment_system.id` (+ year), so the resolver can join them.

> The precise field set of `amr.accountability_system.v1` is deferred to **ADR-002**;
> this ADR fixes only that it is a separate, cross-linked, annual record.

### D5 — Versioning: Git is the history axis; a commit SHA is the reproducibility pin

Metadata is versioned along two independent axes:

- **Schema version** — the `amr.*.vN` string in each record. Governs shape/validation.
- **Data version** — **the Git commit SHA of the registry** at the moment metadata was
  resolved. Because the authored sidecars are the canonical source and they live in Git,
  the commit SHA *is* the content version. Within-year corrections (a state issues an
  erratum, a cutscore is fixed) are ordinary commits; the SHA distinguishes "the 2024
  metadata as of March" from "the 2024 metadata as of the July correction."

Every consumer (SGPc first) **records the resolved registry SHA** (plus the schema
version and a content digest of the exact records used) into its analysis output bundle
and manifest. To reproduce or audit a past run, a consumer checks out or fetches the
registry at that SHA. This makes the optional API safe: even a live query is pinned to a
SHA, so it can never silently drift. This directly implements the deciders' insight that
year-keying plus a recorded SHA obviates the reproducibility risk of a moving target.

### D6 — Storage & derivation: JSON canonical, everything else derived (three tiers)

Preserve SGPc's three-tier separation, relocated to the registry:

```
Tier A  Authored          version-controlled annual JSON sidecars   (CANONICAL)
          |                 amr.assessment_system.v1
          |                 amr.accountability_system.v1
          v
Tier B  Derived           build step -> SQLite + JSON indexes + changelogs   (GENERATED)
          |                 jurisdiction/system/year/content-area index
          |                 vendor-by-year, vertical-scale, cutscore, levels tables
          |                 per-series changelog (diffs by year)
          v
Tier C  Consumed          R package get_metadata() + resolver; static bundles; optional API
```

- **Tier A is the only place edits happen.** No edits through the database or API. The
  DB and indexes are *always derived* from the sidecars by a build step (CI on every
  push), never authored. This keeps review, diffing, and provenance in Git where they
  belong, and sidesteps the "write edits back to JSON" problem entirely.
- **Tier B** ports the existing DDL (`sgpc-metadata.v0.1.sql`) and index/changelog
  builders (`build_sgpc_metadata_index()`, `sgpc_metadata_changelog()`) into the
  registry's build tooling, generalized to `amr.*` and extended for accountability.
- **Tier C** is the consumption surface (D7).

### D7 — Consumption: monorepo R package, static-canonical with an optional later API

The consuming R package (proposed name **`amrr`** — Assessment Metadata Registry in R)
lives **inside the registry repo** (monorepo), so schemas, sidecars, build tooling, and
the R accessors share one source of truth and one CI. Its primary entry point:

```r
get_metadata(jurisdiction = "MA", system = "mcas", year = 2024,
             ref = NULL)      # ref = a registry commit SHA / tag to pin to
```

`get_metadata()` returns an **R list for one jurisdiction/system/year** (or a filtered
set), assembled from JSON — never a monolithic all-jurisdictions object. It resolves in
priority order, mirroring and extending SGPc's resolver:

1. an explicit local path / records argument (author testing a correction),
2. a **local cache** of previously fetched static bundles (keyed by SHA),
3. **static JSON over HTTPS** — versioned bundles published from Tier A/B to GitHub
   (raw at a pinned SHA, and/or release assets, and/or GitHub Pages). *This is
   canonical for R consumption.*
4. (later, additive) a **read-only REST API** for rich cross-jurisdiction queries.

Static-first keeps R consumption dependency-light, cacheable, and reproducible (a SHA
pins the exact bytes); the API is a convenience for interactive/cross-state exploration
and is never on the critical path for an analysis run. SGPc's existing
`resolve_sgpc_metadata()` precedence (`arg > store > embedded`) gains a new
**`registry`** source slotted between `store` and `embedded` — the resolver design
already anticipates additional sources, so this is additive (see the SGPc integration
section).

### D8 — AI-assisted authoring pipeline (the long-term goal)

Design Tier A so that an AI harness can **find, scrape, and draft** sidecars from
publicly available technical documentation (state technical reports, vendor manuals),
with a human review gate before anything reaches `verified` status. This is enabled by,
not bolted onto, the schema: every record carries **provenance and status** fields (D9)
so a machine-drafted record is explicitly `draft` + `source_confidence: low` with a
citation, and promotion to `verified` is a reviewed commit. The scraping harness is a
Tier-A *producer*; it never writes to Tier B/C. Detailed design is **ADR-003**.

### D9 — Governance: status + provenance on every record

Every sidecar carries a governance block:

```yaml
status: draft | reviewed | verified | deprecated
source_confidence: low | medium | high
provenance:
  source_citation: <URL or document reference>   # required for any non-draft claim
  entered_by: <author or "ai:<harness-id>">
  entered_at: <ISO date>
  last_verified_at: <ISO date | null>
  changed_from_prior: <null | short note>         # what changed vs the prior year/commit
```

Corrections are ordinary commits (D5); the changelog (Tier B) surfaces what changed and
`changed_from_prior` records *why* (assessment-system change vs metadata correction vs
modeling decision). Review policy (who may promote to `verified`, required evidence) is
fixed in **ADR-004 (governance)**; this ADR fixes only that the fields exist and that
non-draft claims require a citation.

### D10 — Development harness + LLM wiki

The repo ships with an **LLM wiki and iterative development harness** modeled on SGPc:
an `AGENTS.md` operating manual (tool-neutral, `CLAUDE.md` imports it), a house-style
`wiki/` (sources/principles/patterns/decisions/analyses + index + log), and a `.claude/`
harness (skills, subagents, hooks, deterministic gates). This is where the "wisdom of
the SGPc iterative harness" lands — see the companion `AGENTS.md` and
`wiki/patterns/development-harness.md`. Rationale: most development quality is
circumstantial (the harness-over-model finding); investing in the harness is what makes
AI-assisted authoring (D8) reliable and safe.

---

## Options considered

### Storage model

| Option | Complexity | Query power | Reproducibility | Review/diff |
|--------|-----------|-------------|-----------------|-------------|
| **A. JSON canonical, DB/indexes derived (chosen)** | Low–Med | Med (via derived DB/API) | High (Git SHA) | Excellent (text diffs) |
| B. Database canonical, JSON exported | Med | High | Med (needs DB snapshots) | Poor (binary/opaque) |
| C. API-backed editing, JSON written back | High | High | Low (write-back drift) | Fragile |

**Pros of A:** Git is the version store, review, and provenance mechanism for free; text
diffs are human-reviewable; no server needed for canonical truth; SHA pinning is exact.
**Cons of A:** cross-jurisdiction queries require the derived DB/API layer (acceptable —
that layer is cheap to regenerate and never authoritative).

### R consumption transport

| Option | Reproducibility | Offline/CRAN-friendliness | Query richness | Ops burden |
|--------|-----------------|---------------------------|----------------|------------|
| **Static JSON + cache, API later (chosen)** | High (SHA-pinned bytes) | High | Med now, High with API | Low |
| Live REST API only | Med (moving target unless pinned) | Low | High | High (always-on) |
| Embed a big R object (status quo ante) | High | Low (too large) | Low | Low |

The deciders' SHA-pinning insight makes the optional API safe *and* preserves
static-first reproducibility, so we get the best of both: static bytes are canonical for
runs; the API is additive for exploration.

### Accountability representation

| Option | Fidelity to reality | Duplication | Resolver complexity |
|--------|--------------------|-------------|---------------------|
| **Separate cross-linked record (chosen)** | High (state-wide, multi-assessment) | None | Small join |
| Nested block in assessment sidecar | Low (couples to one assessment) | High | None |

---

## Trade-off analysis

The central tension is **queryability vs. authoring/review ergonomics**. A database is
better for queries; version-controlled JSON is better for authoring, review, provenance,
and reproducibility. We resolve it dialectically rather than by compromise: **JSON is
canonical and authored; the database/API is derived and disposable.** Every query
capability the colleague listed (vendor-by-year, vertical scales, cross-state
comparisons, changelogs) is a *generated view*, regenerated deterministically from the
sidecars on every push. Nothing that matters for correctness or history lives only in
the derived layer.

The second tension is **general product vs. SGPc's immediate needs**. Framing the core
as general (D1) with SGPc-specific views layered in the `amrr` package (and SGP-only
concerns staying in SGPc) means neither goal compromises the other: SGPc gets exactly
the resolver contract it already has, and the registry stays useful to third parties.

---

## Consequences

**Becomes easier**

- Cross-jurisdiction queries become one-liners on the derived index (as in SGPc today).
- "What was the metadata in 2017, as used by *this* run?" = fetch the registry at the
  recorded SHA and read the leaf. Fully reproducible.
- Correcting metadata is a reviewed commit; it never requires rebuilding SGPc.
- Adding a jurisdiction/program is dropping in validated sidecars — no code change.
- AI-assisted authoring has a clear, safe target (Tier A, `draft` status, citation).

**Becomes harder / needs care**

- SGPc must add a `registry` source to its resolver and record the SHA + digest in
  outputs (a small, additive change — see below).
- Two schema surfaces (assessment + accountability) mean two validators and two derived
  projections to maintain.
- The derived DB/API must be treated as strictly disposable; any temptation to edit it
  directly must be blocked (CI regenerates it from JSON).

**To revisit**

- Whether the read-only API (D7.4) is worth standing up, and where it is hosted.
- Whether `csem_ref` closures (psychometric functions) stay R-side (as in SGPc) or gain
  a registry representation — likely stay R-side (ADR-011's reasoning holds).

---

## Security review

<SECURITY_REVIEW>

- **No microdata, ever.** The registry contains only *system-level* metadata
  (cutscores, level names, vendors, rules). It must never contain student-level or
  school-level assessment records. This is a hard content boundary enforced by review
  and by the harness's inherited microdata bright line (SGPc AGENTS.md SECURITY section).
- **Public-by-default, but sourced.** Registry content is intended to be public
  reference data. Every non-draft claim requires a `source_citation` so published facts
  are traceable to authoritative documentation — this is both a governance and an
  anti-misinformation control.
- **Input validation on ingest.** The registry build (Tier B) and the `amrr` package
  must validate every sidecar against its JSON Schema before projection; a malformed or
  identity-conflicting sidecar fails the build (mirror SGPc's `on_conflict = "error"`).
  Never project unvalidated JSON.
- **Scraping harness containment (D8).** The AI authoring pipeline fetches only public
  documentation, writes only `draft` Tier-A files with citations, and cannot promote to
  `verified` — promotion is a human-reviewed commit. It never touches Tier B/C, never
  writes to the DB/API, and honors the fetch restrictions (no alternative fetch paths).
- **API (if built) is read-only and unauthenticated** for public metadata; it exposes
  only derived, already-public facts, and every response is SHA-stamped. No write path.
- **Supply-chain / pinning.** Because consumers pin by SHA, a compromised or accidental
  bad commit cannot silently poison already-published analyses; runs reference the exact
  SHA they used.

</SECURITY_REVIEW>

---

## SGPc integration (the first consumer)

The registry is designed to drop into SGPc's existing Tier C with minimal change:

1. **Resolver source.** Add a `registry` source to `resolve_sgpc_metadata()` precedence:
   `arg > store > registry > embedded`. The `registry` source is `amrr::get_metadata()`
   (static bundle at a pinned SHA), so SGPc keeps working offline and reproducibly. The
   embedded `SGPcMetaData` becomes a thin, optional fallback (or is retired) once the
   registry is authoritative.
2. **Schema alias.** SGPc's validator already keys on `schema_version`; it accepts both
   `sgpc.assessment_metadata.v0.1` and `amr.assessment_system.v1` during migration.
3. **Provenance in outputs.** SGPc's manifest/output bundle already records a metadata
   provenance block; extend it with `registry_ref` (SHA), `registry_schema_version`, and
   the per-cell content digest (D5). This is additive and preserves byte-identical output
   for metadata-unaware runs.
4. **Migration of authored sidecars.** The Indiana sidecars currently under
   `SGPc-foundry/*/metadata/` and `SGPc-rpkg/SGPc/inst/metadata/` move to the registry as
   the seed corpus; SGPc consumes them from the registry thereafter (federation, not
   duplication).

No SGPc methodology changes; this is a source-of-truth relocation plus one resolver
source and three manifest fields.

---

## Action items (phased roadmap)

Gate each phase on the prior; keep changes small and testable (harness discipline).

**Phase 0 — Decision & scaffold (this ADR)**
1. [ ] Deciders accept ADR-000 (flip status `proposed → accepted`).
2. [ ] Land the LLM wiki + `AGENTS.md` harness (companion deliverables).
3. [ ] Repo layout: `schemas/`, `metadata/<jurisdiction>/<system>/*.json`, `r-pkg/amrr/`,
       `tools/` (build), `wiki/`, `.claude/`.

**Phase 1 — Schema + seed corpus + validation**
4. [ ] Author `amr.assessment_system.v1` JSON Schema (port + rename from
       `sgpc-assessment-metadata.schema.json`; add `status`/`provenance`).
5. [ ] Migrate the Indiana sidecars (ILEARN, WIDA-ACCESS) into `metadata/`.
6. [ ] CI: validate every sidecar on push (fail on malformed / identity conflict).

**Phase 2 — Derived layer (Tier B)**
7. [ ] Port the SQLite DDL + `build_index` / `changelog` builders to `tools/`; generate
       `index.json`, per-view tables, and changelogs on push.
8. [ ] Publish static bundles (per-jurisdiction JSON + index) as release/Pages assets,
       SHA-stamped.

**Phase 3 — R consumption (Tier C)**
9. [ ] Build `amrr` with `get_metadata(..., ref=)`, local SHA-keyed cache, static
       fetch, and thin accessors (`cutscores()`, `achievement_levels()`, `vendor()`).
10. [ ] Wire SGPc: add `registry` resolver source; add `registry_ref` to the manifest.

**Phase 4 — Accountability surface (ADR-002)**
11. [ ] Design + author `amr.accountability_system.v1`; add validator + derived views;
        seed Massachusetts (MCAS + WIDA-ACCESS) as the multi-program exemplar.

**Phase 5 — AI authoring pipeline (ADR-003) & optional API**
12. [ ] Scraping harness that drafts cited `draft` sidecars from public tech docs.
13. [ ] (Optional) Read-only, SHA-stamped REST API for cross-jurisdiction queries.

---

## Related (to be authored)

- ADR-001 — `amr.assessment_system.v1` schema specification.
- ADR-002 — accountability-system record type + Massachusetts exemplar.
- ADR-003 — AI-assisted authoring/scraping pipeline.
- ADR-004 — governance: authorship, review, promotion to `verified`.
- Pattern — `development-harness.md` (ported SGPc harness wisdom).
- Connection — `sgpc-registry-consumption-contract.md` (the Tier C boundary with SGPc).
